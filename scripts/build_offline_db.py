#!/usr/bin/env python3
"""
构建离线文档数据库 offline_content.db

从 scp.db 目录读取全部条目，逐个爬取 Wikidot 页面内容，
提取 #page-content HTML，gzip 压缩后存入 SQLite + FTS5 全文索引。

爬取策略：令牌桶限流 + 随机抖动 + UA 轮换 + URL 乱序，防反爬。

用法:
  python3 build_offline_db.py [--catalog assets/scp.db] [--output offline_content.db]
      [--types 1,2,7,8] [--workers 4] [--rate 4] [--resume]

选项:
  --catalog PATH   scp.db 路径 (默认: assets/scp.db)
  --output PATH    输出数据库路径 (默认: offline_content.db)
  --types LIST     只构建指定类型 (逗号分隔，如 1,2,7,8，默认全部)
  --workers N      并发工作线程数 (默认: 4)
  --rate N         全局每秒请求上限 (默认: 4)
  --resume         继续已有构建 (跳过已存在的页面)
  --no-fetch       只重建 FTS 索引，不重新爬取
  --stats-only     只输出统计信息，不操作
"""

import sqlite3, gzip, re, time, sys, os, json, random, threading
from html.parser import HTMLParser
from urllib.request import Request, build_opener, HTTPHandler, HTTPSHandler
from urllib.error import URLError, HTTPError
from html import unescape as html_unescape

# ── 配置 ──
HOME = 'https://scp-wiki-cn.wikidot.com'

# 轮换 User-Agent 列表（都是真实移动端 UA）
USER_AGENTS = [
    # Chrome Android
    'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.6478.122 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; Android 13; SM-S908E) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.6422.165 Mobile Safari/537.36',
    # Samsung Browser
    'Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 '
    '(KHTML, like Gecko) SamsungBrowser/25.0 Chrome/122.0.6261.105 Mobile Safari/537.36',
    # MIUI Browser
    'Mozilla/5.0 (Linux; Android 14; 23127PN0CC) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Version/4.0 Chrome/120.0.6099.244 Mobile Safari/537.36 XiaoMi/MiuiBrowser/17.3.1401',
    # Huawei Browser
    'Mozilla/5.0 (Linux; Android 12; HarmonyOS; ALN-AL00) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/99.0.4844.88 HuaweiBrowser/15.0.2.311 Mobile Safari/537.36',
]

# 轮换 Referer 列表
REFERERS = [
    'https://scp-wiki-cn.wikidot.com/',
    'https://scp-wiki-cn.wikidot.com/scp-series',
    'https://scp-wiki-cn.wikidot.com/scp-series-2',
    'https://scp-wiki-cn.wikidot.com/system:recent-changes',
    'https://scp-wiki-cn.wikidot.com/most-recently-created-cn',
    'https://www.google.com/search?q=scp+foundation',
    'https://www.bing.com/search?q=scp',
]

# 全局 HTTP 连接池
_opener = build_opener(HTTPHandler(), HTTPSHandler())


# ── 令牌桶限流器（线程安全）──

class TokenBucket:
    """令牌桶限流器 — 控制全局请求速率，防反爬"""

    def __init__(self, rate=4, burst=2):
        self.rate = rate           # 每秒发放令牌数
        self.burst = burst         # 最大突发
        self.tokens = float(burst)
        self.last_refill = time.monotonic()
        self.lock = threading.Lock()

    def acquire(self):
        """获取一个令牌，阻塞直到可用"""
        while True:
            with self.lock:
                now = time.monotonic()
                elapsed = now - self.last_refill
                self.tokens = min(self.burst, self.tokens + elapsed * self.rate)
                self.last_refill = now
                if self.tokens >= 1:
                    self.tokens -= 1
                    return
            # 没有令牌，等一会再试
            time.sleep(0.02 + random.random() * 0.03)


# 全局限流器
_rate_limiter = TokenBucket(rate=4, burst=2)


def make_headers():
    """生成带随机 UA 和 Referer 的请求头（更像真实浏览）"""
    # 随机 ±20% 的 Accept-Language 权重
    lang_weight = random.randint(5, 10)
    return {
        'User-Agent': random.choice(USER_AGENTS),
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': f'zh-CN,zh;q=0.{lang_weight},en;q=0.5',
        # 不设置 Accept-Encoding，urllib 自动处理压缩
        'Referer': random.choice(REFERERS),
        'Connection': 'keep-alive',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
    }


def fetch_page(path, timeout=25):
    """从 Wikidot 获取页面 HTML（带限流 + 随机头）"""
    # 获取令牌（阻塞直到允许请求）
    _rate_limiter.acquire()

    # 随机额外延迟（150~450ms 抖动，像人类阅读间隔）
    jitter = 0.15 + random.random() * 0.30
    time.sleep(jitter)

    url = f'{HOME}/{path.lstrip("/")}'
    req = Request(url, headers=make_headers())
    with _opener.open(req, timeout=timeout) as resp:
        raw = resp.read()
    return raw.decode('utf-8', errors='replace')


# Wikidot 页面中需要移除的干扰元素
REMOVE_PATTERNS = [
    re.compile(r'<div class="scp-rating-block[^>]*>.*?</div>', re.DOTALL),
    re.compile(r'<div class="page-rate-widget[^>]*>.*?</div>', re.DOTALL),
    re.compile(r'<div class="licensebox[^>]*>.*?</div>', re.DOTALL),
    re.compile(r'<div class="footer-wiki-nav[^>]*>.*?</div>', re.DOTALL),
    re.compile(r'<div class="options[^>]*>.*?</div>', re.DOTALL),
    re.compile(r'<a class="action-btn[^>]*>.*?</a>', re.DOTALL),
]

IMAGE_PATTERNS = [
    re.compile(r'<img[^>]*>', re.DOTALL),
    re.compile(r'<picture[^>]*>.*?</picture>', re.DOTALL),
    re.compile(r'<figure[^>]*>.*?</figure>', re.DOTALL),
    re.compile(r'<figcaption[^>]*>.*?</figcaption>', re.DOTALL),
    re.compile(r'<video[^>]*>.*?</video>', re.DOTALL),
    re.compile(r'<audio[^>]*>.*?</audio>', re.DOTALL),
    re.compile(r'<source[^>]*>', re.DOTALL),
    re.compile(r'<svg[^>]*>.*?</svg>', re.DOTALL),
    re.compile(r'<canvas[^>]*>.*?</canvas>', re.DOTALL),
    re.compile(r'background-image\s*:\s*url\([^)]+\)', re.DOTALL),
    re.compile(r'background\s*:\s*[^;]*url\([^)]+\)[^;]*;', re.DOTALL),
]


def extract_page_content(html):
    """从完整 Wikidot HTML 中提取 #page-content 内部 HTML，剔除图片"""
    # 用标签计数器处理嵌套 <div>
    start_tag = '<div id="page-content"'
    start = html.find(start_tag)
    if start == -1:
        # 后备
        m2 = re.search(r'<body[^>]*>(.*?)</body>', html, re.DOTALL)
        return m2.group(1).strip() if m2 else None

    # 找到开头的 > 匹配的结束位置
    gt = html.find('>', start)
    if gt == -1:
        return None
    content_start = gt + 1

    # 计数器：逐字符扫描，找到匹配的 </div>
    depth = 1
    i = content_start
    while i < len(html) and depth > 0:
        if html[i:i+5] == '</div' and (i+5 >= len(html) or html[i+5] in '> \t\n'):
            depth -= 1
            if depth == 0:
                content = html[content_start:i]
                break
            i += 5
        elif html[i:i+4] == '<div' and (i+4 >= len(html) or html[i+4] in '> \t\n'):
            depth += 1
            i += 4
        else:
            i += 1
    else:
        # 计数器失败，后备
        content = html[content_start:]

    if not content or not content.strip():
        return None

    # 移除干扰元素
    for pat in REMOVE_PATTERNS:
        content = pat.sub('', content)
    # 移除所有图片/视频/音频元素（离线库只保留文字）
    for pat in IMAGE_PATTERNS:
        content = pat.sub('', content)
    return content.strip()


class HTMLStripper(HTMLParser):
    """剥离 HTML 标签，保留纯文本"""

    def __init__(self):
        super().__init__()
        self.text = []
        self._skip = False

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style', 'noscript'):
            self._skip = True
        if tag == 'br':
            self.text.append('\n')

    def handle_endtag(self, tag):
        if tag in ('script', 'style', 'noscript'):
            self._skip = False
        if tag in ('p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'tr'):
            self.text.append('\n')

    def handle_data(self, data):
        if not self._skip:
            self.text.append(data)

    def get_text(self):
        return ''.join(self.text)


def strip_html(html_content):
    """将 HTML 转为纯文本"""
    stripper = HTMLStripper()
    stripper.feed(html_content)
    text = stripper.get_text()
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = html_unescape(text)
    return text.strip()


def tokenize_cjk(text):
    """为 FTS5 分词：在 CJK 字符间插入空格"""
    result = []
    for ch in text:
        cp = ord(ch)
        if (0x4E00 <= cp <= 0x9FFF or 0x3400 <= cp <= 0x4DBF or
            0xF900 <= cp <= 0xFAFF or 0x3000 <= cp <= 0x303F or
            0xFF00 <= cp <= 0xFFEF):
            result.append(f' {ch} ')
        else:
            result.append(ch)
    return ''.join(result)


# ── 主构建逻辑 ──

class OfflineDbBuilder:
    def __init__(self, catalog_path, output_path, include_types=None,
                 workers=4, rate=4, resume=True):
        self.catalog_path = catalog_path
        self.output_path = output_path
        self.include_types = include_types
        self.workers = workers
        self.resume = resume
        self.lock = threading.Lock()
        self.commit_lock = threading.Lock()
        self.stats = {'fetched': 0, 'failed': 0, 'skipped': 0,
                      'bytes_raw': 0, 'bytes_compressed': 0}
        self._pending_commits = 0
        self._page_cache = {}

        # 全局令牌桶限流（覆盖所有 worker）
        global _rate_limiter
        _rate_limiter = TokenBucket(rate=rate, burst=max(1, rate // 2))

    def init_database(self):
        """创建或打开输出数据库"""
        exists = os.path.exists(self.output_path)
        conn = sqlite3.connect(self.output_path, check_same_thread=False)
        conn.execute('PRAGMA journal_mode=WAL')
        conn.execute('PRAGMA synchronous=OFF')
        conn.execute('PRAGMA cache_size=-64000')
        conn.execute('PRAGMA mmap_size=268435456')
        conn.execute('PRAGMA temp_store=MEMORY')

        if not exists or not self.resume:
            conn.executescript('''
                CREATE TABLE IF NOT EXISTS pages (
                    link TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    scp_type INTEGER,
                    _index INTEGER,
                    html BLOB,
                    text_content BLOB,
                    tags TEXT DEFAULT '',
                    uncompressed_size INTEGER DEFAULT 0,
                    compressed_size INTEGER DEFAULT 0,
                    fetched_at INTEGER DEFAULT 0
                );
                CREATE VIRTUAL TABLE IF NOT EXISTS pages_fts USING fts5(
                    title, text_content, tokenize='unicode61'
                );
                CREATE TABLE IF NOT EXISTS resources (
                    path TEXT PRIMARY KEY,
                    content BLOB,
                    content_type TEXT DEFAULT 'text/plain',
                    updated_at INTEGER DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS build_meta (
                    key TEXT PRIMARY KEY, value TEXT
                );
            ''')
            conn.commit()

        # 确保 resources 表存在（增量构建时可能没有）
        conn.execute('''CREATE TABLE IF NOT EXISTS resources (
            path TEXT PRIMARY KEY,
            content BLOB,
            content_type TEXT DEFAULT 'text/plain',
            updated_at INTEGER DEFAULT 0
        )''')
        conn.commit()
        return conn

    def load_catalog(self, cat_conn):
        """从 scp.db 读取目录"""
        types_filter = ''
        params = []
        if self.include_types:
            placeholders = ','.join('?' * len(self.include_types))
            types_filter = f'WHERE scp_type IN ({placeholders})'
            params = self.include_types

        rows = cat_conn.execute(
            f'SELECT link, title, scp_type, _index FROM scps {types_filter} ORDER BY _id',
            params
        ).fetchall()

        for link, title, scp_type, idx in rows:
            clean_link = link.lstrip('/')
            self._page_cache[clean_link] = {
                'title': title,
                'scp_type': scp_type,
                '_index': idx,
            }
        print(f'目录加载完成: {len(self._page_cache)} 条目')

    def get_existing_links(self, conn):
        rows = conn.execute('SELECT link FROM pages').fetchall()
        return {r[0] for r in rows}

    def build_fts_index(self, conn):
        """从 pages 表重建 FTS5 索引"""
        print('重建 FTS5 全文索引...')
        conn.execute('DELETE FROM pages_fts')

        rows = conn.execute(
            'SELECT rowid, title, text_content FROM pages WHERE text_content IS NOT NULL'
        ).fetchall()

        batch = []
        processed = 0
        total = len(rows)
        for rowid, title, text_blob in rows:
            try:
                text = gzip.decompress(text_blob).decode('utf-8', errors='replace')
            except Exception:
                continue
            batch.append((rowid, tokenize_cjk(title), tokenize_cjk(text)))

            if len(batch) >= 500:
                conn.executemany(
                    'INSERT INTO pages_fts(rowid, title, text_content) VALUES (?, ?, ?)', batch)
                conn.commit()
                processed += len(batch)
                print(f'  FTS: {processed}/{total}', end='\r')
                batch.clear()

        if batch:
            conn.executemany(
                'INSERT INTO pages_fts(rowid, title, text_content) VALUES (?, ?, ?)', batch)
            conn.commit()
            processed += len(batch)

        print(f'\nFTS 索引重建完成: {len(rows)} 条')

    def process_page(self, link, meta, conn):
        """爬取并处理单个页面（无重试）"""
        if self.resume:
            existing = conn.execute(
                'SELECT 1 FROM pages WHERE link=? AND html IS NOT NULL', (link,)
            ).fetchone()
            if existing:
                with self.lock:
                    self.stats['skipped'] += 1
                return

        try:
            html = fetch_page(link)
            content = extract_page_content(html)

            if not content:
                raise ValueError('page-content 为空')

            raw_bytes = len(content.encode('utf-8'))
            compressed = gzip.compress(content.encode('utf-8'), compresslevel=6)
            plain = strip_html(content)
            text_compressed = gzip.compress(plain.encode('utf-8'), compresslevel=6)
            tags = extract_tags(html)

            with self.lock:
                conn.execute('''
                    INSERT OR REPLACE INTO pages
                    (link, title, scp_type, _index, html, text_content, tags,
                     uncompressed_size, compressed_size, fetched_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (link, meta['title'], meta['scp_type'], meta['_index'],
                      compressed, text_compressed, tags,
                      raw_bytes, len(compressed), int(time.time())))
                self._pending_commits += 1
                self.stats['fetched'] += 1
                self.stats['bytes_raw'] += raw_bytes
                self.stats['bytes_compressed'] += len(compressed)

            with self.commit_lock:
                if self._pending_commits >= 20:
                    conn.commit()
                    self._pending_commits = 0

        except Exception as e:
            with self.lock:
                self.stats['failed'] += 1

    def build(self):
        """执行完整构建流程"""
        start_time = time.time()

        print(f'打开目录: {self.catalog_path}')
        cat_conn = sqlite3.connect(self.catalog_path)
        self.load_catalog(cat_conn)
        cat_conn.close()

        conn = self.init_database()

        # 0. 存储 CSS/JS 资源模板
        self.store_resources(conn)

        existing = self.get_existing_links(conn)
        if self.resume and existing:
            print(f'已有 {len(existing)} 条已缓存，将跳过')

        all_links = list(self._page_cache.keys())
        pages_to_fetch = [l for l in all_links if l not in existing] if self.resume else all_links

        if not pages_to_fetch and self.resume:
            self.build_fts_index(conn)
            self.print_stats(start_time, conn)
            conn.close()
            return

        # ═══ 关键：URL 乱序 ═══
        # 不按 SCP 编号顺序爬，避免被识别为批量抓取
        random.shuffle(pages_to_fetch)
        total = len(pages_to_fetch)
        print(f'待爬取: {total} / {len(all_links)}（乱序排列）')

        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor(max_workers=self.workers) as executor:
            futures = {}
            for link in pages_to_fetch:
                future = executor.submit(self.process_page, link,
                                         self._page_cache[link], conn)
                futures[future] = link

            done = 0
            for future in concurrent.futures.as_completed(futures):
                done += 1
                if done % 50 == 0 or done == total:
                    s = self.stats
                    elapsed = time.time() - start_time
                    rate = done / elapsed if elapsed > 0 else 0
                    print(
                        f'  [{done}/{total}] '
                        f'✓{s["fetched"]} ✗{s["failed"]} ⏭{s["skipped"]} '
                        f'{rate:.1f}/s',
                        flush=True)

        # 刷剩余未提交
        with self.commit_lock:
            if self._pending_commits > 0:
                conn.commit()
                self._pending_commits = 0

        self.build_fts_index(conn)

        # 更新元数据
        for k, v in [
            ('build_version', '3'),
            ('has_images', 'false'),
            ('build_time', str(int(time.time()))),
            ('total_pages', str(len(all_links))),
            ('catalog_entries', str(len(self._page_cache))),
        ]:
            conn.execute('INSERT OR REPLACE INTO build_meta VALUES (?, ?)', (k, v))

        type_counts = {}
        for meta in self._page_cache.values():
            t = meta['scp_type']
            type_counts[t] = type_counts.get(t, 0) + 1
        conn.execute('INSERT OR REPLACE INTO build_meta VALUES (?, ?)',
                     ('type_counts', json.dumps(type_counts)))
        conn.commit()
        self.print_stats(start_time, conn)
        conn.close()

    def store_resources(self, conn):
        """将 CSS/JS 阅读模板存入 resources 表"""
        template_dir = os.path.join(os.path.dirname(__file__), 'templates')
        resources = [
            ('reader.css', 'text/css'),
            ('reader.js', 'application/javascript'),
        ]
        stored = 0
        for name, ctype in resources:
            path = os.path.join(template_dir, name)
            if not os.path.exists(path):
                print(f'  模板文件不存在，跳过: {path}')
                continue
            with open(path, 'rb') as f:
                data = f.read()
            conn.execute(
                'INSERT OR REPLACE INTO resources (path, content, content_type, updated_at) '
                'VALUES (?, ?, ?, ?)',
                (name, data, ctype, int(time.time()))
            )
            stored += 1
        conn.commit()
        print(f'  资源模板已存储: {stored} 个')

    def print_stats(self, start_time, conn):
        elapsed = time.time() - start_time
        s = self.stats
        db_size = os.path.getsize(self.output_path) if os.path.exists(self.output_path) else 0

        print(f'\n{"="*50}')
        print(f'构建完成!')
        print(f'  耗时:      {elapsed:.0f}秒 ({elapsed/60:.1f}分钟)')
        print(f'  已取:      {s["fetched"]}')
        print(f'  失败:      {s["failed"]}')
        print(f'  跳过:      {s["skipped"]}')
        if s["bytes_raw"] > 0:
            ratio = s["bytes_compressed"] / s["bytes_raw"] * 100
            print(f'  原始:  {s["bytes_raw"]/1024/1024:.1f}MB')
            print(f'  压缩:  {s["bytes_compressed"]/1024/1024:.1f}MB ({ratio:.1f}%)')
        print(f'  数据库: {db_size/1024/1024:.1f}MB')

        rows = conn.execute('''
            SELECT scp_type, COUNT(*) as cnt,
                   SUM(uncompressed_size) as raw,
                   SUM(compressed_size) as comp
            FROM pages GROUP BY scp_type ORDER BY cnt DESC
        ''').fetchall()
        if rows:
            print(f'\n  各类型:')
            for tp, cnt, raw, comp in rows:
                rm = (raw or 0) / 1024 / 1024
                cm = (comp or 0) / 1024 / 1024
                print(f'    type {tp:2d}: {cnt:5d} 条, {rm:.1f}MB → {cm:.1f}MB')


def extract_tags(html):
    tags = []
    m = re.search(r'<div[^>]*id="page-tags"[^>]*>(.*?)</div>', html, re.DOTALL)
    if m:
        tags = re.findall(r'<a[^>]*class="wiki-tag"[^>]*>([^<]+)</a>', m.group(1))
    return ','.join(t.strip() for t in tags)


def print_stats_only(catalog_path):
    conn = sqlite3.connect(catalog_path)
    rows = conn.execute('''
        SELECT scp_type, COUNT(*) FROM scps
        GROUP BY scp_type ORDER BY COUNT(*) DESC
    ''').fetchall()
    total = sum(r[1] for r in rows)
    print(f'SCP 目录统计 ({catalog_path}):')
    print(f'  总条目: {total}')
    for tp, cnt in rows:
        print(f'  type {tp:2d}: {cnt:5d} 条')
    conn.close()


# ── 入口 ──

def main():
    import argparse
    parser = argparse.ArgumentParser(description='构建 SCP 离线文档数据库')
    parser.add_argument('--catalog', default='assets/scp.db',
                        help='scp.db 路径 (默认: assets/scp.db)')
    parser.add_argument('--output', default='offline_content.db',
                        help='输出数据库路径 (默认: offline_content.db)')
    parser.add_argument('--types', default=None,
                        help='只构建指定类型 (逗号分隔，如 1,2,7,8)')
    parser.add_argument('--workers', type=int, default=4,
                        help='并发线程数 (默认: 4)')
    parser.add_argument('--rate', type=int, default=4,
                        help='全局每秒请求上限 (默认: 4)')
    parser.add_argument('--resume', action='store_true',
                        help='继续已有构建')
    parser.add_argument('--no-fetch', action='store_true',
                        help='只重建 FTS 索引')
    parser.add_argument('--stats-only', action='store_true',
                        help='只输出统计信息')
    args = parser.parse_args()

    if args.stats_only:
        print_stats_only(args.catalog)
        return

    include_types = None
    if args.types:
        include_types = [int(t.strip()) for t in args.types.split(',')]

    if not os.path.exists(args.catalog):
        print(f'错误: 未找到目录数据库 {args.catalog}')
        sys.exit(1)

    builder = OfflineDbBuilder(
        catalog_path=args.catalog,
        output_path=args.output,
        include_types=include_types,
        workers=args.workers,
        rate=args.rate,
        resume=args.resume,
    )

    if args.no_fetch:
        conn = builder.init_database()
        builder.build_fts_index(conn)
        conn.close()
    else:
        builder.build()


if __name__ == '__main__':
    main()
