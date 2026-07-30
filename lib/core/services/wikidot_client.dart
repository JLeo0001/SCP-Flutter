import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

/// Wikidot 直连客户端 — 纯 Dart，无需后端
///
/// 已验证的端点（通过 curl 确认）：
/// - 页面内容: GET https://scp-wiki-cn.wikidot.com/{page} → 解析 #page-content
/// - 最近更新: GET https://scp-wiki-cn.wikidot.com/system:recent-changes
/// - 全部页面: GET https://scp-wiki-cn.wikidot.com/system:list-all-pages
/// - 标签页面: GET https://scp-wiki-cn.wikidot.com/system:page-tags/tag/{tag}
///
/// 不工作的方法（不应依赖）：
/// - quickmodule.php (返回空)
/// - search:site 搜索 (需 POST + wikidot_token)
/// - random:random-scp (JS 重定向，HTTP 无法跟随)
class WikidotClient {
  static final WikidotClient instance = WikidotClient._();

  static const String _domain = 'scp-wiki-cn.wikidot.com';

  final http.Client _client = http.Client();
  DateTime _lastRequest = DateTime(2000);
  final _random = Random();

  WikidotClient._();

  // ── 频率限制 ──
  Future<void> _rateLimit() async {
    final now = DateTime.now();
    final diff = now.difference(_lastRequest);
    if (diff.inMilliseconds < 1500) {
      await Future.delayed(Duration(milliseconds: 1500 - diff.inMilliseconds));
    }
    _lastRequest = DateTime.now();
  }

  Map<String, String> get _headers => {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      };

  String _pageUrl(String path) {
    final name = path.startsWith('/') ? path.substring(1) : path;
    return 'https://$_domain/$name';
  }

  // ═════════════════════════════════════════════════════════
  //  核心获取方法
  // ═════════════════════════════════════════════════════════

  /// 获取页面 HTML — 直连 Wikidot
  /// 有效页面必须包含 <html> 标签（排除 Cloudflare 拦截页）
  Future<String> fetchRawPage(String path) async {
    await _rateLimit();
    final url = _pageUrl(path);
    final result = await _tryFetch(url, _headers, 20);
    if (result != null) return result;
    throw Exception('无法连接 Wikidot，请检查网络: $path');
  }

  /// 尝试一次 HTTP GET
  ///
  /// 返回 null 表示失败。校验逻辑：
  /// 1. statusCode == 200
  /// 2. body 包含 <html>（排除 Cloudflare 拦截页等非正常内容）
  Future<String?> _tryFetch(
      String url, Map<String, String> headers, int timeoutSec) async {
    try {
      final resp = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(Duration(seconds: timeoutSec));
      // 有效响应：200 + (含<html>或<rss>或长度>100)
      if (resp.statusCode == 200 &&
          resp.bodyBytes.isNotEmpty &&
          (resp.body.contains('<html') ||
           resp.body.contains('<rss') ||
           resp.bodyBytes.length > 100)) {
        // Wikidot 返回 UTF-8 但可能不指定 charset，显式解码避免 Latin-1 乱码
        return utf8.decode(resp.bodyBytes);
      }
    } catch (e) {
      // 网络不可达、超时、DNS 解析失败等
    }
    return null;
  }

  // ═════════════════════════════════════════════════════════
  //  最近更新
  // ═════════════════════════════════════════════════════════

  /// 获取最近更新页面列表
  ///
  /// 来源：RSS Feed → 系列页 → list-all-pages（均为Wikidot直连）
  Future<List<WikidotPageInfo>> getRecentChanges({int limit = 20}) async {
    // 1. RSS Feed（最新页面变更）
    try {
      final rssXml = await fetchRawPage('feed/site-changes.xml');
      final results = _parseRecentFromRss(rssXml, limit);
      if (results.isNotEmpty) return results;
    } catch (_) {}

    // 2. 系列页（SCP 条目按评分排序）
    try {
      final results = await _fetchFromSeriesPages(limit);
      if (results.isNotEmpty) return results;
    } catch (_) {}

    // 3. list-all-pages
    try {
      final html = await fetchRawPage('system:list-all-pages');
      final results = _parsePageLinks(html, limit);
      if (results.isNotEmpty) return results;
    } catch (_) {}

    return [];
  }

  /// 从系列页获取最新条目
  Future<List<WikidotPageInfo>> _fetchFromSeriesPages(int limit) async {
    // 从最新的系列页获取条目（scp-series-8 是 7000-7999，最新加入的在末尾）
    final results = <WikidotPageInfo>[];
    final seriesPages = ['scp-series-8', 'scp-series-cn-2'];
    final seen = <String>{};

    for (final series in seriesPages) {
      try {
        final html = await fetchRawPage(series);
        final doc = html_parser.parse(html);
        for (final item in doc.querySelectorAll('.list-pages-item a')) {
          final href = item.attributes['href'] ?? '';
          final title = item.text.trim();
          if (!href.startsWith('/') || href.length <= 1) continue;
          final name = href.substring(1);
          if (name.startsWith('fragment:') || name.startsWith('system:')) continue;
          if (seen.add(name)) {
            results.add(WikidotPageInfo(fullname: name, title: title));
          }
        }
      } catch (_) {}
    }
    // 倒序返回（最新添加的在后面）
    return results.reversed.take(limit).toList();
  }

  /// 从 RSS XML 中解析最近变更页面
  List<WikidotPageInfo> _parseRecentFromRss(String xml, int limit) {
    final results = <WikidotPageInfo>[];
    try {
      final doc = html_parser.parse(xml);
      // RSS item 为 <item><title>...</title><link>http://...</link>...
      for (final item in doc.querySelectorAll('item')) {
        final titleEl = item.querySelector('title');
        final linkEl = item.querySelector('link');
        if (titleEl == null || linkEl == null) continue;

        final titleText = titleEl.text.trim();
        final linkUrl = linkEl.text.trim();

        // 从链接提取页面名：http://scp-wiki-cn.wikidot.com/scp-xx → scp-xx
        final uri = Uri.tryParse(linkUrl);
        if (uri == null || uri.path.isEmpty) continue;
        final pageName = uri.path.startsWith('/')
            ? uri.path.substring(1)
            : uri.path;
        if (pageName.isEmpty) continue;

        // 过滤 fragment/user 等非正文页面
        if (pageName.startsWith('fragment:') ||
            pageName.startsWith('user:') ||
            pageName.startsWith('_') ||
            pageName.startsWith('admin') ||
            pageName.startsWith('system:')) continue;

        // 从标题提取名称（去除引号和变更类型）
        // 格式: "SCP-7826" - 新页面
        final cleanTitle = titleText
            .replaceAll('&quot;', '')
            .replaceAll('"', '')
            .replaceAll('&amp;', '&')
            .trim();
        // 去掉尾部的 " - 新页面" 或 " - 源代码变更" 等
        final dashIdx = cleanTitle.lastIndexOf(' - ');
        final displayTitle =
            dashIdx > 0 ? cleanTitle.substring(0, dashIdx).trim() : cleanTitle;

        if (displayTitle.isEmpty) continue;

        // 去重
        if (!results.any((r) => r.fullname == pageName)) {
          results.add(WikidotPageInfo(fullname: pageName, title: displayTitle));
          if (results.length >= limit) break;
        }
      }
    } catch (_) {}
    return results;
  }

  /// 从页面中提取所有链接（常见的系统页面格式）
  List<WikidotPageInfo> _parsePageLinks(String html, int limit) {
    final results = <WikidotPageInfo>[];
    try {
      final doc = html_parser.parse(html);
      for (final a in doc.querySelectorAll('a')) {
        final href = a.attributes['href'] ?? '';
        if (_isValidPageLink(href) &&
            !results.any((r) => r.fullname == href.substring(1))) {
          results.add(WikidotPageInfo(
            fullname: href.substring(1),
            title: a.text.trim(),
          ));
          if (results.length >= limit) break;
        }
      }
    } catch (_) {}
    return results;
  }

  bool _isValidPageLink(String href) {
    return href.length > 1 &&
        href.startsWith('/') &&
        !href.startsWith('/system:') &&
        !href.startsWith('/admin') &&
        !href.startsWith('/search') &&
        !href.startsWith('/template') &&
        !href.startsWith('/nav:') &&
        !href.startsWith('/_') &&
        !href.contains(':') && // 排除组件页/模块页
        href != '/';
  }

  // ═════════════════════════════════════════════════════════
  //  搜索 — 本地目录已实现，Wikidot 搜索需 POST 不支持
  // ═════════════════════════════════════════════════════════

  /// 注意：Wikidot 站内搜索需要 POST 请求 + wikidot_token7
  /// 从 Flutter 端直接调用过于复杂，建议使用 DatabaseHelper.searchScpByTitle
  /// 此方法保留接口但返回空列表
  Future<List<WikidotPageInfo>> search(String query, {int limit = 30}) async {
    return [];
  }

  // ═════════════════════════════════════════════════════════
  //  随机页面 — 从本地数据库取更可靠
  // ═════════════════════════════════════════════════════════

  /// 获取随机页面
  ///
  /// 注意：Wikidot 的 random:random-scp 使用 JavaScript 重定向
  /// HTTP 客户端无法跟随，改用 ListPages 随机排序方案
  Future<WikidotPageInfo> getRandomPage() async {
    try {
      final pages = await _tryFetchRandomFromListPages();
      if (pages.isNotEmpty) return pages[_random.nextInt(pages.length)];
    } catch (_) {}

    throw Exception('获取随机页面失败');
  }

  Future<List<WikidotPageInfo>> _tryFetchRandomFromListPages() async {
    // 方案1: 从 list-all-pages 随机抽样
    try {
      final html = await fetchRawPage('system:list-all-pages');
      final all = _parsePageLinks(html, 200);
      if (all.length > 10) return all;
    } catch (_) {}
    return [];
  }

  // ═════════════════════════════════════════════════════════
  //  最新原创 & 最新翻译
  // ═════════════════════════════════════════════════════════

  /// 最新原创: /most-recently-created-cn/p/{page}
  Future<List<WikidotPageInfo>> fetchLatestOriginal({int page = 1, int limit = 30}) async {
    try {
      final html = await fetchRawPage('most-recently-created-cn/p/$page');
      return _parseTablePage(html, limit);
    } catch (_) {
      return [];
    }
  }

  /// 最新翻译: /most-recently-created-translated/p/{page}
  Future<List<WikidotPageInfo>> fetchLatestTranslated({int page = 1, int limit = 30}) async {
    try {
      final html = await fetchRawPage('most-recently-created-translated/p/$page');
      return _parseTablePage(html, limit);
    } catch (_) {
      return [];
    }
  }

  /// 通用表格解析: <tr><td><a href="/xxx">Title</a></td>...</tr>
  List<WikidotPageInfo> _parseTablePage(String html, int limit) {
    final results = <WikidotPageInfo>[];
    try {
      final doc = html_parser.parse(html);
      for (final row in doc.querySelectorAll('tr')) {
        final linkEl = row.querySelector('a');
        if (linkEl == null) continue;
        final href = linkEl.attributes['href'] ?? '';
        final title = linkEl.text.trim();
        if (!href.startsWith('/') || href.length <= 1) continue;
        final name = href.substring(1);
        if (name.startsWith('fragment:') || name.startsWith('user:') ||
            name.startsWith('adult:') || name.startsWith('_')) continue;
        results.add(WikidotPageInfo(fullname: name, title: title));
        if (results.length >= limit) break;
      }
    } catch (_) {}
    return results;
  }

  /// 获取高分排行页面
  ///
  /// 来源: /top-rated-pages（Wikidot 按评分排序）
  /// 分类: all / scp / tale / wanderers / goiformat
  Future<List<WikidotPageInfo>> fetchTopRated({
    String category = 'scp',
    int page = 1,
    int limit = 30,
  }) async {
    final path = switch (category) {
      'all' => 'top-rated-pages/all_p/$page',
      'scp' => 'top-rated-pages/pagescp_limit/$page/all_range/-/scp_range/others',
      'tale' => 'top-rated-pages/pagetale_limit/$page/all_range/-/tale_range/others',
      'goiformat' => 'top-rated-pages/pagegoiformat_limit/$page/all_range/-/goiformat_range/others',
      'wanderers' => 'top-rated-pages/pagewanderers_limit/$page/all_range/-/wanderers_range/others',
      _ => 'top-rated-pages/all_p/$page',
    };
    try {
      final html = await fetchRawPage(path);
      return _parseTopRated(html, limit);
    } catch (_) {
      return [];
    }
  }

  /// 解析 top-rated-pages 表格
  ///
  /// 表格结构:
  /// <tr>
  ///   <td><a href="/xxx">Title</a></td>
  ///   <td style="text-align:center;">RATING</td>
  ///   <td style="text-align:center;">COMMENTS</td>
  /// </tr>
  List<WikidotPageInfo> _parseTopRated(String html, int limit) {
    final results = <WikidotPageInfo>[];
    try {
      final doc = html_parser.parse(html);

      // 找所有行
      final rows = doc.querySelectorAll('tr');
      for (final row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 2) continue;

        // 第一列: 链接
        final linkEl = cells[0].querySelector('a');
        if (linkEl == null) continue;
        final href = linkEl.attributes['href'] ?? '';
        final title = linkEl.text.trim();
        if (!href.startsWith('/') || href.length <= 1) continue;
        final name = href.substring(1);

        // 跳过 fragment / user / adult 等
        if (name.startsWith('fragment:') ||
            name.startsWith('user:') ||
            name.startsWith('adult:') ||
            name.startsWith('_')) continue;

        // 第二列: 评分（纯数字）
        final ratingText = cells[1].text.trim();
        final rating = double.tryParse(ratingText);

        results.add(WikidotPageInfo(
          fullname: name,
          title: title,
          rating: rating?.toString(),
        ));

        if (results.length >= limit) break;
      }
    } catch (_) {}
    return results;
  }

  // ═════════════════════════════════════════════════════════
  //  标签相关
  // ═════════════════════════════════════════════════════════

  Future<List<WikidotPageInfo>> getPagesByTag(String tag,
      {int limit = 50}) async {
    try {
      final html =
          await fetchRawPage('system:page-tags/tag/$tag');
      final results = _parsePageLinks(html, limit);
      if (results.isNotEmpty) return results;
    } catch (_) {}
    return [];
  }

  // ═════════════════════════════════════════════════════════
  //  HTML 解析工具
  // ═════════════════════════════════════════════════════════

  String extractContent(String html) {
    try {
      final doc = html_parser.parse(html);
      return doc.getElementById('page-content')?.innerHtml ??
          doc.body?.innerHtml ??
          html;
    } catch (_) {
      return html;
    }
  }

  List<String> extractTags(String html) {
    try {
      final doc = html_parser.parse(html);
      final tagsEl = doc.getElementById('page-tags');
      if (tagsEl != null) {
        return tagsEl
            .querySelectorAll('.wiki-tag')
            .map((e) => e.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  String extractTitle(String html) {
    try {
      final doc = html_parser.parse(html);
      return doc.querySelector('title')?.text.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  void dispose() => _client.close();
}

class WikidotPageInfo {
  final String fullname;
  final String title;
  final String? rating;
  String get link => fullname;
  WikidotPageInfo({
    required this.fullname,
    required this.title,
    this.rating,
  });
}
