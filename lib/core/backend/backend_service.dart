import 'dart:math';
import '../services/database_helper.dart';
import 'scraper.dart';
import 'backend_types.dart';

/// 嵌入式后端服务 — 统一数据访问层
class BackendService {
  static final BackendService instance = BackendService._();
  final BackendScraper _scraper = BackendScraper();
  final _random = Random();
  bool _initialized = false;

  int _syncedCount = 0;
  bool _isSyncing = false;
  DateTime? _lastSync;

  BackendService._();

  /// 初始化：触发后台同步
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _quickSync();
  }

  // ═══════════════════════════════════════════
  //  目录同步
  // ═══════════════════════════════════════════

  /// 快速同步：从最近变更中增量更新目录
  Future<int> _quickSync() async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    try {
      final pages = await _scraper.fetchRecentChanges(limit: 100);
      int added = 0;
      for (final p in pages) {
        final success = await _upsertScpEntry(p);
        if (success) added++;
      }
      _syncedCount += added;
      _lastSync = DateTime.now();
      return added;
    } catch (_) {
      return 0;
    } finally {
      _isSyncing = false;
    }
  }

  /// 完整同步：从系列页面爬取全部 SCP 目录
  Future<int> syncFullCatalog() async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    try {
      // 1. 从系列页爬取完整列表
      final catalog = await _scraper.fetchSeriesCatalog();
      int added = 0;
      for (final page in catalog) {
        int type = 1; // SAVE_SERIES
        if (page.link.startsWith('scp-cn-')) type = 2;
        else if (page.link.contains('-j')) type = 3;
        else if (page.link.startsWith('tale:')) type = 7;
        else if (page.link.startsWith('wanderers:')) type = 10;
        else if (page.link.startsWith('goi:')) type = 17;

        final success = await _upsertScpEntry(
          page, scpType: type,
        );
        if (success) added++;
      }

      // 2. 再从最近更新补一些
      try {
        final recent = await _scraper.fetchRecentChanges(limit: 100);
        for (final p in recent) {
          await _upsertScpEntry(p);
        }
      } catch (_) {}

      _syncedCount += added;
      _lastSync = DateTime.now();
      return added;
    } catch (_) {
      return 0;
    } finally {
      _isSyncing = false;
    }
  }

  /// 更新或插入一条目录条目
  Future<bool> _upsertScpEntry(PageRef page, {int? scpType}) async {
    try {
      final link = page.link.startsWith('/') ? page.link.substring(1) : page.link;
      if (link.isEmpty || link.startsWith('fragment:') || link.startsWith('_') || link.startsWith('forum/')) return false;

      if (scpType == null) {
        if (link.startsWith('scp-cn-')) scpType = 2;
        else if (link.contains('-j')) scpType = 3;
        else if (link.startsWith('tale:')) scpType = 7;
        else if (link.startsWith('wanderers:')) scpType = 10;
        else if (link.startsWith('goi:')) scpType = 17;
        else scpType = 1;
      }

      await DatabaseHelper.upsertCatalogEntry(link, page.title, scpType: scpType);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════
  //  页面内容
  // ═══════════════════════════════════════════

  Future<PageData> getPage(String link) async {
    final name = link.startsWith('/') ? link.substring(1) : link;
    try {
      final cached = await DatabaseHelper.getCachedPage(name);
      if (cached != null && cached.detail != null && cached.detail!.isNotEmpty) {
        return PageData(
          link: name, title: '', content: cached.detail!,
          tags: (cached.tags ?? '').split(',').where((t) => t.isNotEmpty).toList(),
          html: cached.detail!,
        );
      }
    } catch (_) {}
    final page = await _scraper.fetchPage(name);
    try {
      await DatabaseHelper.cachePage(name, page.content, page.tags.join(','));
    } catch (_) {}
    return page;
  }

  // ═══════════════════════════════════════════
  //  最近更新（仅 Wikidot 直连，绝不读本地数据库）
  // ═══════════════════════════════════════════

  Future<List<PageRef>> getRecentChanges({int limit = 30}) async {
    return _scraper.fetchRecentChanges(limit: limit);
  }

  // ═══════════════════════════════════════════
  //  高分排行（仅Wikidot直连）
  // ═══════════════════════════════════════════

  Future<List<PageRef>> getTopRated({String category = 'scp', int limit = 30}) async {
    return _scraper.fetchTopRated(category: category, limit: limit);
  }

  Future<List<PageRef>> getLatestScp({int limit = 20}) async {
    return _scraper.fetchLatestOriginal(limit: limit);
  }

  Future<List<PageRef>> getLatestTranslated({int limit = 20}) async {
    return _scraper.fetchLatestTranslated(limit: limit);
  }

  Future<List<PageRef>> getByCategory(String prefix, {int limit = 20}) async {
    final pages = await _scraper.fetchRecentChanges(limit: limit * 2);
    return pages.where((p) => p.link.startsWith(prefix)).take(limit).toList();
  }

  // ═══════════════════════════════════════════
  //  随机
  // ═══════════════════════════════════════════

  Future<PageRef> getRandom() async {
    try {
      final items = await DatabaseHelper.getRandomScp(count: 10);
      if (items.isNotEmpty) {
        final picked = items[_random.nextInt(items.length)];
        return PageRef(link: picked.link, title: picked.title);
      }
    } catch (_) {}
    final catalog = await _scraper.fetchSeriesCatalog();
    if (catalog.isNotEmpty) return catalog[_random.nextInt(catalog.length)];
    throw Exception('无可用数据');
  }

  // ═══════════════════════════════════════════
  //  搜索 & 标签
  // ═══════════════════════════════════════════

  Future<List<PageRef>> search(String keyword, {int limit = 30}) async {
    try {
      final items = await DatabaseHelper.searchScpByTitle(keyword);
      return items.take(limit).map((s) => PageRef(link: s.link, title: s.title)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<PageRef>> getPagesByTag(String tag) async {
    try {
      return await _scraper.fetchPagesByTag(tag);
    } catch (_) {
      return [];
    }
  }

  Future<List<BackendTag>> getAllTags() async {
    return [];
  }

  // ═══════════════════════════════════════════
  //  状态
  // ═══════════════════════════════════════════

  bool get isSyncing => _isSyncing;
  int get syncedCount => _syncedCount;
  DateTime? get lastSync => _lastSync;
}
