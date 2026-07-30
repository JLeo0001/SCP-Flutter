import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/scp_item_model.dart';
import '../models/scp_detail.dart';
import '../models/scp_record_model.dart';
import '../models/scp_like_model.dart';
import '../models/draft_model.dart';

/// 存储结构优化 — 随用随抓，按需缓存
///
/// ┌─────────────────────────────────────────────────────────┐
/// │  scp.db (预置资产, 只读)                                │
/// │  └─ scps 表 — SCP 目录元数据 (title, link, type等)     │
/// │     仅在 APK 中内置，首次启动自动从 assets 复制           │
/// ├─────────────────────────────────────────────────────────┤
/// │  scp_data.db (运行态, 读写)                              │
/// │  ├─ page_cache — 页面HTML缓存 (link → HTML+tags+time)  │
/// │  ├─ likes     — 收藏/已读                              │
/// │  ├─ records   — 阅读历史/待读列表                      │
/// │  └─ drafts    — 草稿                                   │
/// │     首次使用时自动建表，所有数据随用随生成                │
/// └─────────────────────────────────────────────────────────┘
///
class DatabaseHelper {
  // ── 单例连接池 ──
  static Database? _catalogDb;  // scp.db (只读目录)
  static Database? _dataDb;     // scp_data.db (缓存+用户数据)

  // ═══════════════════════════════════════════════════════════
  //  1. 目录数据库 — scp.db（预置资产，只读）
  // ═══════════════════════════════════════════════════════════

  /// 从 assets 复制预置数据库到本地
  /// assets/scp.db → {dbPath}/scp.db
  static Future<Database> getCatalogDb() async {
    if (_catalogDb != null) return _catalogDb!;

    final dbPath = await getDatabasesPath();
    final dbFile = File(p.join(dbPath, 'scp.db'));

    // 检查是否需要更新：比较 assets 和本地文件大小
    bool needsCopy = !dbFile.existsSync();
    if (!needsCopy) {
      try {
        final assetData = await rootBundle.load('assets/scp.db');
        if (assetData.lengthInBytes != dbFile.lengthSync()) {
          needsCopy = true;
        }
      } catch (_) {}
    }

    if (needsCopy) {
      try {
        final data = await rootBundle.load('assets/scp.db');
        await dbFile.parent.create(recursive: true);
        await dbFile.writeAsBytes(data.buffer.asUint8List());
      } catch (e) {
        print('Catalog DB copy error: $e');
      }
    }

    _catalogDb = await openDatabase(dbFile.path);
    return _catalogDb!;
  }

  /// 按类型获取条目列表
  static Future<List<ScpItemModel>> getScpListByType(int type) async {
    final db = await getCatalogDb();
    final maps = await db.query('scps', where: 'scp_type = ?', whereArgs: [type], orderBy: '_index ASC');
    return maps.map((m) => ScpItemModel.fromMap(m)).toList();
  }

  static Future<List<ScpItemModel>> getScpListByTypeAndExtra(int type, String extra) async {
    final db = await getCatalogDb();
    final maps = await db.query('scps', where: 'scp_type = ? AND sub_scp_type = ?', whereArgs: [type, extra], orderBy: '_index ASC');
    return maps.map((m) => ScpItemModel.fromMap(m)).toList();
  }

  static Future<List<ScpItemModel>> getInternationalByCountry(String country) async {
    final db = await getCatalogDb();
    final maps = await db.query('scps', where: 'scp_type = 23 AND sub_scp_type LIKE ?', whereArgs: [country], orderBy: '_index ASC');
    return maps.map((m) => ScpItemModel.fromMap(m)).toList();
  }

  static Future<ScpItemModel?> getScpByLink(String link) async {
    final db = await getCatalogDb();
    final searchLink = link.startsWith('/') ? link : '/$link';
    final maps = await db.query('scps', where: 'link = ?', whereArgs: [searchLink], limit: 1);
    return maps.isEmpty ? null : ScpItemModel.fromMap(maps.first);
  }

  static Future<List<ScpItemModel>> searchScpByTitle(String keyword) async {
    final db = await getCatalogDb();
    final maps = await db.query('scps', where: 'title LIKE ?', whereArgs: ['%$keyword%']);
    return maps.map((m) => ScpItemModel.fromMap(m)).toList();
  }

  static Future<List<ScpItemModel>> getRandomScp({int count = 1}) async {
    final db = await getCatalogDb();
    final maps = await db.rawQuery('SELECT * FROM scps ORDER BY random() LIMIT ?', [count]);
    return maps.map((m) => ScpItemModel.fromMap(m)).toList();
  }

  /// 获取所有条目（按 _id 倒序，最新同步的在前面）
  static Future<List<ScpItemModel>> getAllEntries({int limit = 50}) async {
    final db = await getCatalogDb();
    final maps = await db.query('scps', orderBy: '_id DESC', limit: limit);
    return maps.map((m) => ScpItemModel.fromMap(m)).toList();
  }

  // ═══════════════════════════════════════════════════════════
  //  2. 数据数据库 — scp_data.db（运行时按需生成，读写）
  // ═══════════════════════════════════════════════════════════

  static Future<Database> getDataDb() async {
    if (_dataDb != null) return _dataDb!;
    final dbPath = await getDatabasesPath();
    _dataDb = await openDatabase(
      p.join(dbPath, 'scp_data.db'),
      version: 2,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS page_cache (
            link TEXT PRIMARY KEY,
            html TEXT,
            tags TEXT,
            fetched_at INTEGER NOT NULL DEFAULT (cast(strftime('%s','now') as int))
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS likes (
            link TEXT PRIMARY KEY, title TEXT,
            liked INTEGER DEFAULT 0, has_read INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS records (
            link TEXT PRIMARY KEY, title TEXT,
            list_type INTEGER, view_time INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS drafts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT, content TEXT, updated_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS reading_positions (
            link TEXT PRIMARY KEY,
            scroll_y REAL DEFAULT 0,
            updated_at INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS reading_positions (
              link TEXT PRIMARY KEY,
              scroll_y REAL DEFAULT 0,
              updated_at INTEGER
            )
          ''');
        }
      },
    );
    return _dataDb!;
  }

  // ── 页面缓存 ──

  /// 获取缓存的页面HTML（随用随取，没有则返回null）
  static Future<ScpDetail?> getCachedPage(String link) async {
    final db = await getDataDb();
    final maps = await db.query('page_cache', where: 'link = ?', whereArgs: [link], limit: 1);
    if (maps.isEmpty) return null;
    final m = maps.first;
    return ScpDetail(
      link: m['link'] as String,
      detail: m['html'] as String?,
      tags: m['tags'] as String? ?? '',
      notFound: 0,
    );
  }

  /// 缓存页面HTML（随用随存，下次免网）
  static Future<void> cachePage(String link, String html, String tags) async {
    final db = await getDataDb();
    await db.insert('page_cache', {
      'link': link, 'html': html, 'tags': tags,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── 收藏/已读 ──

  static Future<bool> isLiked(String link) async {
    final db = await getDataDb();
    final maps = await db.query('likes', where: 'link = ? AND liked = 1', whereArgs: [link], limit: 1);
    return maps.isNotEmpty;
  }

  static Future<bool> hasRead(String link) async {
    final db = await getDataDb();
    final maps = await db.query('likes', where: 'link = ? AND has_read = 1', whereArgs: [link], limit: 1);
    return maps.isNotEmpty;
  }

  static Future<void> setLike(String link, String title, bool liked) async {
    final db = await getDataDb();
    await db.insert('likes', {'link': link, 'title': title, 'liked': liked ? 1 : 0}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> setHasRead(String link, String title) async {
    final db = await getDataDb();
    await db.insert('likes', {'link': link, 'title': title, 'has_read': 1}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> getReadCount() async {
    final db = await getDataDb();
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM likes WHERE has_read = 1');
    return (r.first['c'] ?? 0) as int;
  }

  /// 获取所有已读条目
  static Future<List<ScpLikeModel>> getAllRead() async {
    final db = await getDataDb();
    final maps = await db.query('likes', where: 'has_read = 1', orderBy: 'rowid DESC');
    return maps.map((m) => ScpLikeModel.fromMap({
      'link': m['link'], 'title': m['title'], 'like': m['liked'], 'hasRead': m['has_read'], 'boxId': 0,
    })).toList();
  }

  /// 取消已读
  static Future<void> setUnread(String link) async {
    final db = await getDataDb();
    await db.insert('likes', {'link': link, 'has_read': 0}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> getLikeCount() async {
    final db = await getDataDb();
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM likes WHERE liked = 1');
    return (r.first['c'] ?? 0) as int;
  }

  static Future<List<ScpLikeModel>> getAllLikes() async {
    final db = await getDataDb();
    final maps = await db.query('likes', where: 'liked = 1');
    return maps.map((m) => ScpLikeModel.fromMap({
      'link': m['link'], 'title': m['title'], 'like': m['liked'], 'hasRead': m['has_read'], 'boxId': 0,
    })).toList();
  }

  // ── 阅读记录 ──

  static Future<List<ScpRecordModel>> getRecords(int listType) async {
    final db = await getDataDb();
    final maps = await db.query('records', where: 'list_type = ?', whereArgs: [listType], orderBy: 'view_time DESC');
    return maps.map((m) => ScpRecordModel(
      link: (m['link'] ?? '') as String,
      title: (m['title'] ?? '') as String,
      viewListType: (m['list_type'] ?? -1) as int,
      viewTime: (m['view_time'] ?? 0) as int,
    )).toList();
  }

  static Future<void> addRecord(String link, String title, int listType) async {
    final db = await getDataDb();
    await db.insert('records', {
      'link': link, 'title': title, 'list_type': listType, 'view_time': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> removeRecord(String link) async {
    final db = await getDataDb();
    await db.delete('records', where: 'link = ?', whereArgs: [link]);
  }

  // ── 阅读位置 ──

  /// 保存阅读滚动位置
  static Future<void> saveReadingPosition(String link, double scrollY) async {
    final db = await getDataDb();
    await db.insert('reading_positions', {
      'link': link,
      'scroll_y': scrollY,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 获取上次阅读位置，null 表示无记录
  static Future<double?> getReadingPosition(String link) async {
    final db = await getDataDb();
    final maps = await db.query('reading_positions',
        where: 'link = ?', whereArgs: [link], limit: 1);
    if (maps.isEmpty) return null;
    return (maps.first['scroll_y'] as num?)?.toDouble();
  }

  // ── 草稿 ──

  static Future<List<DraftModel>> getAllDrafts() async {
    final db = await getDataDb();
    final maps = await db.query('drafts', orderBy: 'updated_at DESC');
    return maps.map((m) => DraftModel(
      draftId: (m['id'] ?? 0) as int,
      lastModifyTime: (m['updated_at'] ?? 0) as int,
      title: (m['title'] ?? '') as String,
      content: (m['content'] ?? '') as String,
    )).toList();
  }

  static Future<void> saveDraft(DraftModel draft) async {
    final db = await getDataDb();
    await db.insert('drafts', {
      if (draft.draftId > 0) 'id': draft.draftId,
      'title': draft.title, 'content': draft.content,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteDraft(int id) async {
    final db = await getDataDb();
    await db.delete('drafts', where: 'id = ?', whereArgs: [id]);
  }

  /// 按关键词搜索草稿（标题或内容匹配）
  static Future<List<DraftModel>> searchDrafts(String keyword) async {
    final db = await getDataDb();
    final maps = await db.query('drafts',
        where: 'title LIKE ? OR content LIKE ?',
        whereArgs: ['%$keyword%', '%$keyword%'],
        orderBy: 'updated_at DESC');
    return maps.map((m) => DraftModel.fromMap(m)).toList();
  }

  // ── 目录更新 ──

  /// 从 Wikidot 发现的页面写入本地目录（增量更新）
  static Future<void> upsertCatalogEntry(String fullname, String title, {int scpType = 1}) async {
    final db = await getCatalogDb();
    final existing = await db.query('scps', where: 'link = ?', whereArgs: ['/$fullname'], limit: 1);
    if (existing.isEmpty) {
      // 计算 _index 值（该类型最大值 + 1）
      final maxIdx = await db.rawQuery('SELECT MAX(_index) as m FROM scps WHERE scp_type = ?', [scpType]);
      final nextIdx = ((maxIdx.first['m'] ?? 0) as int) + 1;
      await db.insert('scps', {
        'link': '/$fullname',
        'title': title,
        'scp_type': scpType,
        '_index': nextIdx,
        '_id': nextIdx,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// 获取目录统计：按 scp_type 分组计数
  /// 返回 [(scp_type, count, typeName), ...]
  static Future<List<Map<String, dynamic>>> getCatalogStats() async {
    final db = await getCatalogDb();
    return await db.rawQuery('SELECT scp_type, COUNT(*) as count FROM scps GROUP BY scp_type ORDER BY scp_type');
  }

  /// 获取目录总条目数
  static Future<int> getTotalEntryCount() async {
    final db = await getCatalogDb();
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM scps');
    return (r.first['c'] ?? 0) as int;
  }

  /// 获取目录中不同 scp_type 数量（即分类数）
  static Future<int> getDistinctTypeCount() async {
    final db = await getCatalogDb();
    final r = await db.rawQuery('SELECT COUNT(DISTINCT scp_type) as c FROM scps');
    return (r.first['c'] ?? 0) as int;
  }

  /// 获取目录中最大 _id（用于判断是否需要更新）
  static Future<void> close() async {
    await _catalogDb?.close();
    await _dataDb?.close();
    _catalogDb = null;
    _dataDb = null;
  }
}
