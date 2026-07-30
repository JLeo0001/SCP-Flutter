import 'package:html/parser.dart' as html;
import '../services/wikidot_client.dart';
import 'backend_types.dart';

/// 爬虫引擎 — 在 WikidotClient 之上提供高级批量能力
class BackendScraper {
  final WikidotClient _client = WikidotClient.instance;

  // ── 页面内容 ──

  Future<PageData> fetchPage(String link) async {
    final name = link.startsWith('/') ? link.substring(1) : link;
    final raw = await _client.fetchRawPage(name);
    final title = _client.extractTitle(raw);
    final content = _client.extractContent(raw);
    final tags = _client.extractTags(raw);
    return PageData(link: name, title: title, content: content, tags: tags, html: raw);
  }

  // ── 系列目录（批量爬取系列页，构建完整 SCP 编号列表）──

  static const _seriesPages = [
    'scp-series', 'scp-series-2', 'scp-series-3', 'scp-series-4',
    'scp-series-5', 'scp-series-6', 'scp-series-7', 'scp-series-8',
    'scp-series-9', 'scp-series-10',
  ];

  static const _cnSeriesPages = [
    'scp-series-cn', 'scp-series-cn-2', 'scp-series-cn-3', 'scp-series-cn-4',
    'scp-series-cn-5',
  ];

  /// 爬取系列页，返回所有 SCP 条目引用
  Future<List<PageRef>> fetchSeriesCatalog() async {
    final results = <PageRef>[];
    final seen = <String>{};

    for (final series in [..._seriesPages, ..._cnSeriesPages]) {
      try {
        final raw = await _client.fetchRawPage(series);
        final doc = html.parse(raw);
        for (final item in doc.querySelectorAll('.list-pages-item a')) {
          final href = item.attributes['href'] ?? '';
          final title = item.text.trim();
          if (!href.startsWith('/') || href.length <= 1) continue;
          final name = href.substring(1);
          if (seen.add(name)) {
            results.add(PageRef(link: name, title: title));
          }
        }
      } catch (_) {}
    }
    return results;
  }

  // ── 标签 ──

  Future<List<PageRef>> fetchPagesByTag(String tag, {int limit = 50}) async {
    final pages = await _client.getPagesByTag(tag, limit: limit);
    return pages.map((p) => PageRef(link: p.fullname, title: p.title)).toList();
  }

  /// 从页面集合中收集所有标签
  Future<Set<String>> collectTagsFromPages(List<String> links) async {
    final tags = <String>{};
    for (final link in links) {
      try {
        final raw = await _client.fetchRawPage(link);
        tags.addAll(_client.extractTags(raw));
      } catch (_) {}
    }
    return tags;
  }

  // ── 最新原创 & 翻译 ──

  Future<List<PageRef>> fetchLatestOriginal({int limit = 20}) async {
    final pages = await _client.fetchLatestOriginal(limit: limit);
    return pages.map((p) => PageRef(link: p.fullname, title: p.title)).toList();
  }

  Future<List<PageRef>> fetchLatestTranslated({int limit = 20}) async {
    final pages = await _client.fetchLatestTranslated(limit: limit);
    return pages.map((p) => PageRef(link: p.fullname, title: p.title)).toList();
  }

  // ── 高分排行 ──

  Future<List<PageRef>> fetchTopRated({String category = 'scp', int limit = 30}) async {
    final pages = await _client.fetchTopRated(category: category, limit: limit);
    return pages.map((p) => PageRef(link: p.fullname, title: p.title, rating: double.tryParse(p.rating ?? ''))).toList();
  }

  // ── 最近更新 ──

  Future<List<PageRef>> fetchRecentChanges({int limit = 30}) async {
    final pages = await _client.getRecentChanges(limit: limit);
    return pages.map((p) => PageRef(link: p.fullname, title: p.title)).toList();
  }
}
