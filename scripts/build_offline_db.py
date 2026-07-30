#!/usr/bin/env python3
"""
构建离线文档数据库 offline_content.db

从 scp.db 目录读取全部条目，逐个爬取 Wikidot 页面内容，
提取 #page-content HTML，gzip 压缩后存入 SQLite + FTS5 全文索引。

用法:
  python3 build_offline_db.py [--catalog assets/scp.db] [--output offline_content.db]
      [--types 1,2,7,8] [--workers 3] [--delay 1.0] [--resume]

选项:
  --catalog PATH   scp.db 路径 (默认: assets/scp.db)
  --output PATH    输出数据库路径 (默认: offline_content.db)
  --types LIST     只构建指定类型 (逗号分隔，如 1,2,7,8，默认全部)
  --workers N      并发工作线程数 (默认: 3)
  --delay SEC      请求间隔秒数 (默认: 1.0)
  --resume         继续已有构建 (跳过已存在的页面)
  --no-fetch       只重建 FTS 索引，不重新爬取
  --stats-only     只输出统计信息，不操作
"""

import sqlite3, gzip, re, time, sys, os, json, hashlib, threading
from html.parser import HTMLParser
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from html import unescape as html_unescape

# ── 配置 ──
HOME = 'https://scp-wiki-cn.wikidot.com'
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.5',
}

# Wikidot 页面中需要移除的干扰元素选择器（简化版：正则匹配标签）
REMOVE_PATTERNS = [
    re.compile(r'<div class="scp-rating-block[^>]*>.*?</div>', re.DOTALL),
    re.compile(r'<div class="page-rate-widget[^>]*>.*?</div>', re.DOTALL),
    re.compile(r'<div class="licensebox[^>]*>.*?</div>', re.DOTALL),
    re.compile(r'<div class="footer-wiki-nav[^>]*>.*?</div>', re.DOTALL),
    re.compile(r'<div class="options[^>]*>.*?</div>', re.DOTALL),
    re.compile(r'<a class="action-btn[^>]*>.*?</a>', re.DOTALL),
]

# 图片相关标签 — 全部删除，不保留引用
IMAGE_PATTERNS = [
    re.compile(r'<img[^>]*>', re.DOTALL),                    # <img ...>
    re.compile(r'<picture[^>]*>.*?</picture>', re.DOTALL),    # <picture>...</picture>
    re.compile(r'<figure[^>]*>.*?</figure>', re.DOTALL),      # <figure>...</figure>
    re.compile(r'<figcaption[^>]*>.*?</figcaption>', re.DOTALL),
    re.compile(r'<video[^>]*>.*?</video>', re.DOTALL),        # 视频也排除
    re.compile(r'<audio[^>]*>.*?</audio>', re.DOTALL),        # 音频也排除
    re.compile(r'<source[^>]*>', re.DOTALL),                  # <source> 标签
    re.compile(r'<svg[^>]*>.*?</svg>', re.DOTALL),            # SVG 矢量图
    re.compile(r'<canvas[^>]*>.*?</canvas>', re.DOTALL),      # Canvas 画布
    # 内联 background-image 样式（部分 Wikidot 页面用 div 模拟图片）
    re.compile(r'background-image\s*:\s*url\([^)]+\)', re.DOTALL),
    re.compile(r'background\s*:\s*[^;]*url\([^)]+\)[^;]*;', re.DOTALL),
]

# ── 工具函数 ──

def extract_page_content(html):
    """从完整 Wikidot HTML 中提取 #page-content 内部 HTML，剔除图片"""
    m = re.search(r'<div[^>]*id="page-content"[^>]*>(.*?)</div>\s*<!--\s*/\s*#page-content\s*-->',
                  html, re.DOTALL)
    if m:
        content = m.group(1)
    else:
        # 后备：取 <body> 内容
        m2 = re.search(r'<body[^>]*>(.*?)</body>', html, re.DOTALL)
        if m2:
            content = m2.group(1)
        else:
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
    """将 HTML 转为纯文本（保留段落结构）"""
    stripper = HTMLStripper()
    stripper.feed(html_content)
    text = stripper.get_text()
    # 合并多余空白
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


def fetch_page(path, timeout=20):
    """从 Wikidot 获取页面 HTML"""
    url = f'{HOME}/{path.lstrip("/")}'
    req = Request(url, headers=HEADERS)
    with urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    return raw.decode('utf-8', errors='replace')


# ── 主构建逻辑 ──

class OfflineDbBuilder:
    def __init__(self, catalog_path, output_path, include_types=None,
                 workers=3, delay=1.0, resume=True):
        self.catalog_path = catalog_path
        self.output_path = output_path
        self.include_types = include_types  # None = all
        self.workers = workers
        self.delay = delay
        self.resume = resume
        self.lock = threading.Lock()
        self.stats = {'fetched': 0, 'failed': 0, 'skipped': 0, 'bytes_raw': 0, 'bytes_compressed': 0}
        self._page_cache = {}  # link -> (title, scp_type, _index) from catalog

    def init_database(self):
        """创建或打开输出数据库"""
        exists = os.path.exists(self.output_path)
        conn = sqlite3.connect(self.output_path)
        conn.execute('PRAGMA journal_mode=WAL')
        conn.execute('PRAGMA synchronous=OFF')
        conn.execute('PRAGMA cache_size=-8000')  # 8MB cache

        if not exists or not self.resume:
            # 全新创建
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
                    title,
                    text_content,
                    tokenize='unicode61'
                );

                CREATE TABLE IF NOT EXISTS build_meta (
                    key TEXT PRIMARY KEY,
                    value TEXT
                );
            ''')
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
        """获取已构建的页面链接"""
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
            tokenized_title = tokenize_cjk(title)
            tokenized_text = tokenize_cjk(text)
            batch.append((rowid, tokenized_title, tokenized_text))

            if len(batch) >= 500:
                conn.executemany(
                    'INSERT INTO pages_fts(rowid, title, text_content) VALUES (?, ?, ?)',
                    batch
                )
                conn.commit()
                processed += len(batch)
                print(f'  FTS: {processed}/{total}', end='\r')
                batch.clear()

        if batch:
            conn.executemany(
                'INSERT INTO pages_fts(rowid, title, text_content) VALUES (?, ?, ?)',
                batch
            )
            conn.commit()
            processed += len(batch)

        print(f'\nFTS 索引重建完成: {len(rows)} 条')

    def process_page(self, link, meta, conn, max_retries=2):
        """爬取并处理单个页面（失败自动重试 max_retries 次）"""
        if self.resume:
            existing = conn.execute(
                'SELECT 1 FROM pages WHERE link=? AND html IS NOT NULL',
                (link,)
            ).fetchone()
            if existing:
                with self.lock:
                    self.stats['skipped'] += 1
                return

        for attempt in range(max_retries + 1):
            try:
                if attempt > 0:
                    # 重试等待：指数退避 3s, 9s
                    wait = 3 * (3 ** (attempt - 1))
                    time.sleep(wait)

                time.sleep(self.delay)
                html = fetch_page(link)
                content = extract_page_content(html)

                if not content:
                    raise ValueError('page-content 为空')

                raw_bytes = len(content.encode('utf-8'))
                compressed = gzip.compress(content.encode('utf-8'), compresslevel=6)

                # 纯文本版本（不含标签）
                plain = strip_html(content)
                text_compressed = gzip.compress(plain.encode('utf-8'), compresslevel=6)

                tags = extract_tags(html)

                with self.lock:
                    conn.execute('''
                        INSERT OR REPLACE INTO pages
                        (link, title, scp_type, _index, html, text_content, tags,
                         uncompressed_size, compressed_size, fetched_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ''', (
                        link, meta['title'], meta['scp_type'], meta['_index'],
                        compressed, text_compressed, tags,
                        raw_bytes, len(compressed), int(time.time())
                    ))
                    conn.commit()
                    self.stats['fetched'] += 1
                    self.stats['bytes_raw'] += raw_bytes
                    self.stats['bytes_compressed'] += len(compressed)
                return  # 成功

            except Exception as e:
                if attempt < max_retries:
                    continue  # 重试
                with self.lock:
                    self.stats['failed'] += 1

    def build(self):
        """执行完整构建流程"""
        start_time = time.time()

        # 1. 连接 catalog
        print(f'打开目录: {self.catalog_path}')
        cat_conn = sqlite3.connect(self.catalog_path)
        self.load_catalog(cat_conn)
        cat_conn.close()

        # 2. 初始化输出数据库
        conn = self.init_database()
        existing = self.get_existing_links(conn)
        if self.resume and existing:
            print(f'已有 {len(existing)} 条已缓存，将跳过')

        all_links = list(self._page_cache.keys())
        pages_to_fetch = [l for l in all_links if l not in existing] if self.resume else all_links

        print(f'待爬取: {len(pages_to_fetch)} / {len(all_links)}')

        if not pages_to_fetch and self.resume:
            self.build_fts_index(conn)
            self.print_stats(start_time, conn)
            conn.close()
            return

        # 3. 多线程爬取
        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor(max_workers=self.workers) as executor:
            futures = {}
            for link in pages_to_fetch:
                meta = self._page_cache[link]
                future = executor.submit(self.process_page, link, meta, conn)
                futures[future] = link

            done = 0
            total = len(futures)
            for future in concurrent.futures.as_completed(futures):
                done += 1
                if done % 50 == 0 or done == total:
                    s = self.stats
                    elapsed = time.time() - start_time
                    rate = done / elapsed if elapsed > 0 else 0
                    print(
                        f'  [{done}/{total}] '
                        f'已取{s["fetched"]} 失败{s["failed"]} 跳过{s["skipped"]} '
                        f'{rate:.1f}/s',
                        flush=True
                    )

        # 4. 构建 FTS 索引
        self.build_fts_index(conn)

        # 5. 更新元数据
        conn.execute(
            'INSERT OR REPLACE INTO build_meta VALUES (?, ?)',
            ('build_version', '2')
        )
        conn.execute(
            'INSERT OR REPLACE INTO build_meta VALUES (?, ?)',
            ('has_images', 'false')  # 离线库不含图片
        )
        conn.execute(
            'INSERT OR REPLACE INTO build_meta VALUES (?, ?)',
            ('build_time', str(int(time.time())))
        )
        conn.execute(
            'INSERT OR REPLACE INTO build_meta VALUES (?, ?)',
            ('total_pages', str(len(all_links)))
        )
        conn.execute(
            'INSERT OR REPLACE INTO build_meta VALUES (?, ?)',
            ('catalog_entries', str(len(self._page_cache)))
        )

        # 按类型统计
        type_counts = {}
        for meta in self._page_cache.values():
            t = meta['scp_type']
            type_counts[t] = type_counts.get(t, 0) + 1
        conn.execute(
            'INSERT OR REPLACE INTO build_meta VALUES (?, ?)',
            ('type_counts', json.dumps(type_counts))
        )

        conn.commit()
        self.print_stats(start_time, conn)
        conn.close()

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
            print(f'  原始大小:  {s["bytes_raw"]/1024/1024:.1f}MB')
            print(f'  压缩后:    {s["bytes_compressed"]/1024/1024:.1f}MB ({ratio:.1f}%)')
        print(f'  数据库大小: {db_size/1024/1024:.1f}MB')

        # 输出内容统计
        rows = conn.execute('''
            SELECT scp_type, COUNT(*) as cnt,
                   SUM(uncompressed_size) as raw,
                   SUM(compressed_size) as comp
            FROM pages GROUP BY scp_type ORDER BY cnt DESC
        ''').fetchall()
        if rows:
            print(f'\n  各类型统计:')
            for tp, cnt, raw, comp in rows:
                raw_mb = (raw or 0) / 1024 / 1024
                comp_mb = (comp or 0) / 1024 / 1024
                ratio = comp_mb / raw_mb * 100 if raw_mb > 0 else 0
                print(f'    type {tp:2d}: {cnt:5d} 条, {raw_mb:.1f}MB → {comp_mb:.1f}MB ({ratio:.1f}%)')


def extract_tags(html):
    """提取页面标签"""
    tags = []
    m = re.search(r'<div[^>]*id="page-tags"[^>]*>(.*?)</div>', html, re.DOTALL)
    if m:
        tags = re.findall(r'<a[^>]*class="wiki-tag"[^>]*>([^<]+)</a>', m.group(1))
    return ','.join(t.strip() for t in tags)


def print_stats_only(catalog_path):
    """只输出统计信息"""
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
    parser.add_argument('--workers', type=int, default=3,
                        help='并发线程数 (默认: 3)')
    parser.add_argument('--delay', type=float, default=1.0,
                        help='请求间隔秒数 (默认: 1.0)')
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
        delay=args.delay,
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
