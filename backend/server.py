#!/usr/bin/env python3
"""
SCP基金会 — Wikidot API 后端服务
使用 wikidot 库安全地获取 SCP 官网内容，自带频率限制

启动: python3 backend/server.py [--port 5000]
"""

import time
import json
import logging
from functools import wraps
from flask import Flask, jsonify, request
from wikidot import Client, Site

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
log = logging.getLogger(__name__)

app = Flask(__name__)

# ── 全局 Wikidot 客户端（复用连接） ──
_client = None
_site = None

SITE_UNIX = 'scp-wiki-cn'
MIN_INTERVAL = 1.5  # 每次请求最小间隔（秒）
_last_request = 0.0

def _rate_limit(func):
    """频率限制装饰器：确保两次请求之间至少间隔 MIN_INTERVAL 秒"""
    @wraps(func)
    def wrapper(*args, **kwargs):
        global _last_request
        now = time.time()
        elapsed = now - _last_request
        if elapsed < MIN_INTERVAL:
            wait = MIN_INTERVAL - elapsed
            log.info(f"Rate limit: waiting {wait:.1f}s")
            time.sleep(wait)
        _last_request = time.time()
        return func(*args, **kwargs)
    return wrapper

def _ensure_site():
    """确保 Wikidot 客户端和站点已初始化"""
    global _client, _site
    if _site is None:
        _client = Client()
        _site = Site.from_unix_name(_client, SITE_UNIX)
        log.info(f"Connected to site: {_site.title} ({_site.url})")
    return _site


# ═══════════════════════════════════════════
#  API 端点
# ═══════════════════════════════════════════

@app.route('/')
def index():
    return jsonify({
        'service': 'SCP Wikidot API',
        'site': SITE_UNIX,
        'endpoints': [
            'GET /page/<fullname>      — 获取页面详情（标题、标签、正文html）',
            'GET /source/<fullname>    — 获取页面维基源代码',
            'GET /search?q=...         — 搜索页面',
            'GET /recent-changes       — 最近更新列表（最新10条）',
        ]
    })

@app.route('/page/<path:fullname>')
@_rate_limit
def get_page(fullname):
    """获取页面详情：标题、标签、评分、维基源代码"""
    site = _ensure_site()
    try:
        results = site.pages.search(fullname=fullname, limit=1)
        if not results:
            return jsonify({'error': 'Page not found', 'fullname': fullname}), 404

        page = results[0]
        data = {
            'fullname': page.fullname,
            'name': page.name,
            'title': page.title,
            'tags': page.tags,
            'rating': page.rating,
            'votes_count': page.votes_count,
            'created_at': str(page.created_at),
            'updated_at': str(page.updated_at),
            'children_count': page.children_count,
            'comments_count': page.comments_count,
            'size': page.size,
            'source': page.source.wiki_text if page.source else '',
        }
        return jsonify(data)
    except Exception as e:
        log.error(f"Error fetching page {fullname}: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/source/<path:fullname>')
@_rate_limit
def get_source(fullname):
    """获取页面维基源代码（仅source）"""
    site = _ensure_site()
    try:
        results = site.pages.search(fullname=fullname, limit=1)
        if not results:
            return jsonify({'error': 'Page not found'}), 404
        page = results[0]
        src = page.source
        return jsonify({
            'fullname': fullname,
            'source': src.wiki_text if src else '',
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/search')
@_rate_limit
def search():
    """搜索页面"""
    site = _ensure_site()
    q = request.args.get('q', '')
    category = request.args.get('category', '')
    limit = int(request.args.get('limit', 20))

    try:
        kwargs = {'limit': limit}
        if q:
            kwargs['fullname'] = q
        if category:
            kwargs['category'] = category

        results = site.pages.search(**kwargs)
        pages = []
        for p in results:
            pages.append({
                'fullname': p.fullname,
                'title': p.title,
                'tags': p.tags,
                'rating': p.rating,
                'created_at': str(p.created_at),
            })
        return jsonify({'results': pages, 'count': len(pages)})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/recent-changes')
@_rate_limit
def recent_changes():
    """最近更新"""
    site = _ensure_site()
    limit = int(request.args.get('limit', 10))
    try:
        changes = site.get_recent_changes(limit=limit)
        items = []
        for c in changes:
            items.append({
                'fullname': c.fullname,
                'title': c.title,
                'status': c.status,
                'revision_number': c.revision_number,
                'updated_at': str(c.updated_at),
            })
        return jsonify({'results': items, 'count': len(items)})
    except Exception as e:
        log.warning(f"get_recent_changes failed (may need auth): {e}")
        return jsonify({'error': str(e), 'hint': 'Recent changes may require authentication'}), 401


@app.route('/tag/<path:fullname>')
@_rate_limit
def get_tags(fullname):
    """获取页面标签"""
    site = _ensure_site()
    try:
        results = site.pages.search(fullname=fullname, limit=1)
        if not results:
            return jsonify({'error': 'Page not found'}), 404
        return jsonify({'fullname': fullname, 'tags': results[0].tags})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/list-by-category/<category>')
@_rate_limit
def list_by_category(category):
    """按分类列出页面"""
    site = _ensure_site()
    limit = int(request.args.get('limit', 100))
    try:
        results = site.pages.search(category=category, limit=limit)
        pages = []
        for p in results:
            pages.append({
                'fullname': p.fullname,
                'title': p.title,
                'tags': p.tags,
                'rating': p.rating,
            })
        return jsonify({'results': pages, 'count': len(pages)})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='SCP Wikidot API Server')
    parser.add_argument('--port', type=int, default=5000, help='Listen port')
    parser.add_argument('--host', default='127.0.0.1', help='Bind address')
    args = parser.parse_args()

    log.info(f"Starting SCP API server on {args.host}:{args.port}")
    log.info(f"Rate limit: {MIN_INTERVAL}s between requests")
    app.run(host=args.host, port=args.port, debug=False)
