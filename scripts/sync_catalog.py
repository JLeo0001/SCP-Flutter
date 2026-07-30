#!/usr/bin/env python3
"""全量同步SCP目录 — 从主页爬取所有分类入口，递归刮子链接"""
import urllib.request, sqlite3, re, time, sys, os

DB = os.environ.get('DB_PATH', 'assets/scp.db')
HOME = 'https://scp-wiki-cn.wikidot.com'
HEADERS = {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36'}

SKIP = {f'/{p}' for p in [
    'scp-series','scp-series-2','scp-series-3','scp-series-4',
    'scp-series-5','scp-series-6','scp-series-7','scp-series-8',
    'scp-series-9','scp-series-10',
    'scp-series-cn','scp-series-cn-2','scp-series-cn-3','scp-series-cn-4','scp-series-cn-5',
    'joke-scps','joke-scps-cn','explained-scps','explained-scps-cn',
    'foundation-tales','foundation-tales-cn','canon-hub','canon-hub-cn',
    'series-archive','series-archive-cn',
    'scp-ex','scp-ex-cn','scp-international',
    'audio-adaptations',
    'log-of-anomalous-items','log-of-anomalous-items-cn','log-of-extranormal-events',
    'log-of-extranormal-events-cn','log-of-unexplained-locations',
    'log-of-unexplained-locations-cn','log-of-non-anomalous-items','user-curated-lists',
    'incident-reports-eye-witness-interviews-and-personal-logs',
    'short-stories','creepy-pasta',
    'info-pages','links','sandbox',
    'top-rated-pages','most-recently-created','most-recently-created-cn',
    'most-recently-created-translated','most-recently-edited','lowest-rated-pages',
    'members-pages','members-pages-cn','wiki-syntax','lost-scp-series',
    'guide-hub','guide-for-newbies','how-to-write-an-scp',
    'faq','tag-guide','tag-search','site-rules',
    'anomalous-items-cn-1','anomalous-items-cn-2','anomalous-items-cn-3',
    'anomalous-items-cn-4','anomalous-items-cn-5','anomalous-items-cn-6',
    'anomalous-items-cn-7','component:theme','component:scp-int-hub',
]}


def skip(link):
    if link.startswith('/fragment:'): return True
    if link.startswith('/forum'): return True
    if link.startswith('/scp-series'): return True
    if link.startswith('/_') or link.startswith('/local'): return True
    if link.startswith('/system:'): return True
    if link.startswith('/admin'): return True
    if link.startswith('/nav:'): return True
    return link in SKIP

def infer(link, parent_type=None):
    if link.startswith('/scp-cn-'): return 2
    if link.startswith('/scp-'):
        # 检查是否带特殊后缀
        suffix_match = re.search(r'/scp-\d+-(j|ex|arc|bus|th|pt|ko|ru|es|fr|pl|de|it|zh|jp|splash)$', link)
        if suffix_match:
            suf = suffix_match.group(1)
            if suf == 'j': return 3
            if suf == 'ex': return 5
            if suf in ('th', 'pt', 'ko', 'ru', 'es', 'fr', 'pl', 'de', 'it', 'zh', 'jp'):
                return 23  # international
            if suf in ('arc', 'splash'):
                return 7  # tales
            if suf == 'bus':
                return 3  # joke
        return 1  # 标准 SCP
    if link.startswith('/tale:'): return 7
    if link.startswith('/wanderers:'): return 21
    if link.startswith('/fragment:'): return None
    if link.startswith('/forum'): return None
    if '/joke' in link.lower() or link.endswith('-j'): return 3
    if '/explained' in link.lower() or link.endswith('-ex'): return 5
    # 图书馆分类 hub 页
    if link == '/goi-formats': return 17
    if link == '/scp-artwork-hub': return 18
    if link == '/contest-archive': return 19
    if link == '/contest-archive-cn': return 20
    if link == '/wanderers:start': return 21
    if link == '/wanderers:the-library-cn': return 22
    if link == '/user-curated-lists': return 16
    # 背景资料参考页 → type 24 (saveInfoPage)
    if link in (
        '/about-the-scp-foundation', '/groups-of-interest', '/object-classes',
        '/personnel-and-character-dossier', '/security-clearance-levels',
        '/secure-facilities-locations', '/task-forces', '/departments',
        '/groups-of-interest-cn', '/secure-facilities-locations-cn', '/task-forces-cn',
    ): return 24
    # 竞赛类型跟随父页面
    if parent_type in (19, 20):
        return parent_type
    return 7

def _extract_scp_index(link, scp_type):
    """从链接提取SCP编号作为_index，仅用于纯数字编号的类型1和2
    
    要求 /scp- 后紧跟数字直到路径结束（排除 /scp-7bus、/scp-999-ex 等）
    """
    if scp_type == 1:
        m = re.match(r'/scp-(\d+)$', link)
        if m: return int(m.group(1))
    elif scp_type == 2:
        m = re.match(r'/scp-cn-(\d+)$', link)
        if m: return int(m.group(1))
    return None

def fetch(path):
    url = f'{HOME}/{path.lstrip("/")}'
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=20) as resp:
        return resp.read().decode('utf-8', errors='replace')

def extract(html, broad=False):
    """提取页面中所有内部链接"""
    links = {}
    if broad:
        pattern = r'<a\s+href="(/(?!system:|admin|nav:|_|local|fragment:|forum)[^"#]+)"[^>]*>([^<]+)</a>'
    else:
        pattern = r'<a\s+href="(/(?:scp|tale|wanderers|goi|canon|fragment|log|extranormal|'
    pattern += r'user-curated|anomalous|info|component|short|incident|creepy|'
    pattern += r'chinese|joke|explained|contest|picture|scpcn|halloween|summer|winter|'
    pattern += r'spring|prime|smash|good|amnestic|memento|gallery|iteration|game|'
    pattern += r'sci-fi|upvote|remix|romcon|goblin|coldpost|doomsday|re-imagine|'
    pattern += r'draft|history|d-class|classic|public-domain|collaboration|'
    pattern += r'antimemetics|artist|creepypasta|silence|cocktail|'
    pattern += r'new-blood|location|fantasy|april|department|goif|'
    pattern += r'ghost|star|golden-age|teeth|love|spc|critter|grant|'
    pattern += r'bird|group|guide|newbee|security|faq|task|foundation|'
    pattern += r'series|library|random|sand|lost|links|'
    pattern += r'about|personnel|object|secure|facility|location|dossier|class|'
    pattern += r's-b|t-b|w-v|y-b|g-b|k-b|lte|mzl|edc|kte|prmt|'
    pattern += r'zibuyu|yixue|kanshin|ambrose|koigare|news|collected|'
    pattern += r'reg-profile|proposition|propuesta|wniosek|zlecenie|uebernahme|'
    pattern += r'zetetic|proposal|incident|depart|audio|members|'
    pattern += r'n-a|audio|top-rated|most-recent|lowest|members|wiki)[^"#]*)"[^>]*>([^<]+)</a>'
    for m in re.finditer(pattern, html):
        h = m.group(1); t = m.group(2).strip()
        if not t or skip(h): continue
        if h not in links: links[h] = t
    return links

def main():
    print(f"DB: {DB}")
    conn = sqlite3.connect(DB)
    c = conn.cursor()

    # 修复已有SCP条目的_index（确保编号一致）
    fixed = 0
    for tp in (1, 2):
        c.execute("SELECT link FROM scps WHERE scp_type=?", (tp,))
        for row in c.fetchall():
            new_idx = _extract_scp_index(row[0], tp)
            if new_idx is not None:
                c.execute("UPDATE scps SET _index=? WHERE link=? AND _index<>?", (new_idx, row[0], new_idx))
                if c.rowcount > 0: fixed += 1
    if fixed:
        conn.commit()
        print(f"修复 _index: {fixed}")

    c.execute("SELECT link FROM scps")
    done = {r[0] for r in c.fetchall()}
    print(f"现有: {len(done)}")
    added = 0

    # 1. 主页 → 发现分类入口
    print("\n-- 主页 --")
    try:
        home_html = fetch('/')
        home_links = extract(home_html)
        hubs = {}
        for h, t in home_links.items():
            if skip(h): continue
            tp = infer(h)
            if tp is None: continue
            hubs[h] = (t, tp)
        print(f"  入口: {len(hubs)}")
    except Exception as e:
        print(f"  失败: {e}")
        hubs = {}

    # 2. 刮每个入口的子链接
    crawled = set()
    for path, (title, st) in hubs.items():
        if path in crawled: continue
        crawled.add(path)

        # hub页本身
        if path not in done:
            c.execute("SELECT COALESCE(MAX(_id),0) FROM scps"); mid=c.fetchone()[0]+1
            c.execute("SELECT COALESCE(MAX(_index),0) FROM scps WHERE scp_type=?",(st,)); mdx=c.fetchone()[0]+1
            c.execute("INSERT INTO scps (_id,_index,link,title,scp_type) VALUES (?,?,?,?,?)",
                      (mid,mdx,path,title,st))
            done.add(path); added+=1

        try:
            html = fetch(path)
            # 竞赛归档页用宽泛匹配
            use_broad = '/contest' in path
            links = extract(html, broad=use_broad)
            ad = 0
            for lk, ti in links.items():
                if lk in done: continue
                tp = infer(lk, st)
                if tp is None: continue
                # SCP系列(类型1/2)从链接提取编号作为_index，避免乱序
                mdx = _extract_scp_index(lk, tp)
                if mdx is None:
                    c.execute("SELECT COALESCE(MAX(_index),0) FROM scps WHERE scp_type=?",(tp,))
                    mdx=c.fetchone()[0]+1
                c.execute("SELECT COALESCE(MAX(_id),0) FROM scps"); mid=c.fetchone()[0]+1
                c.execute("INSERT INTO scps (_id,_index,link,title,scp_type) VALUES (?,?,?,?,?)",
                          (mid,mdx,lk,ti,tp))
                done.add(lk); ad+=1
            conn.commit(); added+=ad
            print(f"  {path:45s} t={st:2d} {len(links):4d}链 +{ad}")
            time.sleep(1.5)
        except Exception as e:
            print(f"  {path:45s} 失败: {e}")

    c.execute("SELECT COUNT(*), COUNT(DISTINCT link) FROM scps")
    t, u = c.fetchone()
    conn.close()
    print(f"\n完成! {t}条, 唯一{u}")
    return 0

if __name__ == '__main__':
    sys.exit(main())
