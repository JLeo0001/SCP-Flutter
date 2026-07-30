#!/usr/bin/env python3
"""从Wikidot系列页提取SCP完整标题（含描述），更新数据库"""
import urllib.request, sqlite3, re, time, sys, os, html as html_mod

DB = os.environ.get('DB_PATH', 'assets/scp.db')
HOME = 'https://scp-wiki-cn.wikidot.com'
HEADERS = {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36'}
DELAY = 1.0

SERIES = [
    # SCP系列
    'scp-series', 'scp-series-2', 'scp-series-3', 'scp-series-4',
    'scp-series-5', 'scp-series-6', 'scp-series-7', 'scp-series-8',
    'scp-series-9', 'scp-series-10',
    # SCP-CN系列
    'scp-series-cn', 'scp-series-cn-2', 'scp-series-cn-3',
    'scp-series-cn-4', 'scp-series-cn-5',
]

def fetch(path):
    url = f'{HOME}/{path.lstrip("/")}'
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=20) as resp:
        return resp.read().decode('utf-8', errors='replace')

def strip_html(text):
    """去除HTML标签，解码HTML实体"""
    text = re.sub(r'<[^>]+>', '', text)
    text = html_mod.unescape(text)
    return text.strip()

def parse_series(html):
    """解析系列页HTML，提取 {link: full_title} 映射
    
    Wikidot 系列页格式：
    <li><a href="/scp-173">SCP-173</a> - 最初之作</li>
    """
    results = {}
    # 匹配 <li><a href="/...">TITLE</a> - DESCRIPTION</li>
    pattern = r'<li><a\s+href="(/[^"]+)"[^>]*>([^<]+)</a>\s*-\s*(.*?)</li>'
    for m in re.finditer(pattern, html):
        link = m.group(1)
        scp_num = m.group(2).strip()
        desc = strip_html(m.group(3))
        if not desc: continue
        full = f'{scp_num} - {desc}'
        results[link] = full
    return results

def main():
    conn = sqlite3.connect(DB)
    c = conn.cursor()
    
    # 先看看当前标题情况
    c.execute("SELECT link, title FROM scps WHERE scp_type IN (1,2)")
    existing = {row[0]: row[1] for row in c.fetchall()}
    print(f"SCP条目总数: {len(existing)}")

    total_found = 0
    total_updated = 0

    for series in SERIES:
        try:
            html = fetch(series)
            titles = parse_series(html)
            if not titles:
                print(f"  {series:30s} → 未解析到条目")
                time.sleep(DELAY)
                continue

            updated = 0
            for link, full_title in titles.items():
                if link in existing and existing[link] != full_title:
                    c.execute("UPDATE scps SET title=? WHERE link=?", (full_title, link))
                    updated += 1
                    existing[link] = full_title

            total_found += len(titles)
            total_updated += updated
            print(f"  {series:30s} → {len(titles):4d}条, 更新{updated}")
            time.sleep(DELAY)
        except Exception as e:
            print(f"  {series:30s} → 失败: {e}")
            time.sleep(DELAY * 2)

    conn.commit()
    conn.close()
    print(f"\n完成! 共解析{total_found}条, 更新{total_updated}条")
    return 0

if __name__ == '__main__':
    sys.exit(main())
