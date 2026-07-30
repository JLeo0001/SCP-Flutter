import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

/// 离线内容数据库 — 单文件 offline_content.db
///
/// 包含所有页面的 gzip 压缩 HTML + 纯文本 + FTS5 全文索引
///
/// **重要**: 离线库只包含文字内容，所有图片/视频/音频元素
/// 在构建时已剥离，不含任何媒体文件引用。
///
/// 加载方式：
/// 1. 用户通过「下载离线库」功能下载并自动加载
/// 2. 用户通过系统文件选择器（SAF）选择 .db 文件
class OfflineContentDb {
  static Database? _db;
  static String? _dbPath;
  static bool _loaded = false;

  /// 数据库加载状态
  static bool get isLoaded => _loaded && _db != null;
  static String? get dbPath => _dbPath;
  static int? _totalPages;
  static Map<int, int>? _typeCounts;
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('OfflineContentDb: 文件不存在 $filePath');
        return false;
      }

      // 验证 SQLite 头部
      final raf = await file.open(mode: FileMode.read);
      final header = await raf.read(16);
      await raf.close();
      final sqliteHeader = Uint8List.fromList([
        0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
        0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00,
      ]);
      if (!_listEquals(header, sqliteHeader)) {
        print('OfflineContentDb: 不是有效的 SQLite 数据库');
        return false;
      }

      await close();

      _db = await openDatabase(
        filePath,
        readOnly: true,
      );

      // 验证表结构
      final tables = await _db!.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('pages', 'pages_fts')"
      );
      if (tables.length < 2) {
        print('OfflineContentDb: 缺少必需的表 pages/pages_fts');
        await _db!.close();
        _db = null;
        return false;
      }

      _dbPath = filePath;
      _loaded = true;

      // 读取元数据
      await _loadMeta();

      print('OfflineContentDb: 加载成功 $_dbPath ($_totalPages 页)');
      return true;
    } catch (e) {
      print('OfflineContentDb: 加载失败: $e');
      _db = null;
      _loaded = false;
      return false;
    }
  }

  /// 自动扫描默认路径（仅启动时调用，无文件则静默跳过）
  static Future<bool> load() async {
    // 不再扫描硬编码路径，只通过 loadFromPath / download 加载
    return false;
  }

  /// 从指定路径加载离线数据库
  static Future<bool> loadFromPath(String filePath) async {

  /// 关闭数据库
  static Future<void> close() async {
    await _db?.close();
    _db = null;
    _loaded = false;
    _totalPages = null;
    _typeCounts = null;
  }

  /// 读取元数据
  static Future<void> _loadMeta() async {
    if (_db == null) return;
    try {
      final rows = await _db!.rawQuery('SELECT COUNT(*) as c FROM pages');
      _totalPages = (rows.first['c'] ?? 0) as int;

      final typeRows = await _db!.rawQuery(
        'SELECT scp_type, COUNT(*) as cnt FROM pages WHERE scp_type IS NOT NULL GROUP BY scp_type'
      );
      _typeCounts = {};
      for (final row in typeRows) {
        _typeCounts![row['scp_type'] as int] = row['cnt'] as int;
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════
  //  页面读取
  // ═══════════════════════════════════════════

  /// 获取离线页面内容。返回解压后的 #page-content HTML，未找到返回 null
  static Future<String?> getPageHtml(String link) async {
    if (_db == null) return null;
    final cleanLink = link.startsWith('/') ? link.substring(1) : link;

    try {
      final rows = await _db!.rawQuery(
        'SELECT html FROM pages WHERE link = ?',
        [cleanLink]
      );
      if (rows.isEmpty) return null;

      final blob = rows.first['html'] as Uint8List?;
      if (blob == null || blob.isEmpty) return null;

      return gzipDecode(blob);
    } catch (e) {
      print('OfflineContentDb.getPageHtml error: $e');
      return null;
    }
  }

  /// 获取页面基本信息
  static Future<Map<String, dynamic>?> getPageInfo(String link) async {
    if (_db == null) return null;
    final cleanLink = link.startsWith('/') ? link.substring(1) : link;

    try {
      final rows = await _db!.rawQuery(
        'SELECT link, title, scp_type, _index, tags, uncompressed_size '
        'FROM pages WHERE link = ?',
        [cleanLink]
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════
  //  全文搜索
  // ═══════════════════════════════════════════

  /// FTS5 全文搜索
  ///
  /// 返回 [{link, title, snippet, scp_type, _index}]
  /// snippet 已去除 CJK 分词插入的空格
  static Future<List<Map<String, dynamic>>> fullTextSearch(String query, {int limit = 50}) async {
    if (_db == null || query.trim().isEmpty) return [];

    try {
      // 对查询进行 CJK 分词（与建索引保持一致）
      final tokenized = tokenizeCjk(query.trim());

      // FTS5 搜索，使用 snippet 生成上下文片段
      final rows = await _db!.rawQuery('''
        SELECT p.link, p.title, p.scp_type, p._index,
               snippet(pages_fts, 1, '<b>', '</b>', '…', 40) as snippet
        FROM pages_fts
        JOIN pages p ON p.rowid = pages_fts.rowid
        WHERE pages_fts MATCH ?
        ORDER BY rank
        LIMIT ?
      ''', [tokenized, limit]);

      // 处理结果：去除 snippet 中的 CJK 分词空格
      return rows.map((row) {
        final s = (row['snippet'] as String? ?? '');
        return {
          'link': row['link'],
          'title': (row['title'] as String?)?.replaceAll(' ', '') ?? '',
          'snippet': _cleanSnippet(s),
          'scp_type': row['scp_type'],
          '_index': row['_index'],
        };
      }).toList();
    } catch (e) {
      print('OfflineContentDb.fullTextSearch error: $e');
      // FTS5 搜索失败时回退到 LIKE 搜索
      return _fallbackSearch(query, limit: limit);
    }
  }

  /// LIKE 后备搜索（用于 FTS5 语法错误等场景）
  static Future<List<Map<String, dynamic>>> _fallbackSearch(String query, {int limit = 50}) async {
    if (_db == null) return [];
    try {
      // 先用 title 匹配
      final rows = await _db!.rawQuery('''
        SELECT link, title, scp_type, _index
        FROM pages
        WHERE title LIKE ? ESCAPE '\\'
        LIMIT ?
      ''', ['%${_escapeLike(query)}%', limit]);

      return rows.map((row) => {
        'link': row['link'],
        'title': row['title'],
        'snippet': '…标题匹配…',
        'scp_type': row['scp_type'],
        '_index': row['_index'],
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 批量获取页面标题（用于搜索建议）
  static Future<List<Map<String, dynamic>>> searchTitles(String keyword, {int limit = 20}) async {
    if (_db == null) return [];
    try {
      final rows = await _db!.rawQuery('''
        SELECT link, title, scp_type, _index
        FROM pages
        WHERE title LIKE ? ESCAPE '\\'
        ORDER BY _index ASC
        LIMIT ?
      ''', ['%${_escapeLike(keyword)}%', limit]);
      return rows;
    } catch (_) {
      return [];
    }
  }

  // ═══════════════════════════════════════════
  //  资源读取（CSS/JS 模板）
  // ═══════════════════════════════════════════

  /// 从离线库读取 CSS/JS 资源，未找到返回 null
  ///
  /// [path] 如 'reader.css', 'reader.js'
  static Future<String?> getResource(String path) async {
    if (_db == null) return null;
    try {
      final rows = await _db!.rawQuery(
        'SELECT content FROM resources WHERE path = ?', [path]
      );
      if (rows.isEmpty) return null;
      final blob = rows.first['content'] as Uint8List?;
      if (blob == null) return null;
      return utf8.decode(blob);
    } catch (_) {
      return null;
    }
  }

  /// 获取所有资源路径列表
  static Future<List<String>> listResources() async {
    if (_db == null) return [];
    try {
      final rows = await _db!.rawQuery('SELECT path FROM resources');
      return rows.map((r) => r['path'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  // ═══════════════════════════════════════════
  //  统计信息
  // ═══════════════════════════════════════════

  static int? get totalPages => _totalPages;
  static Map<int, int>? get typeCounts => _typeCounts;

  /// 数据库文件大小
  static Future<int?> get dbFileSize async {
    if (_dbPath == null) return null;
    try {
      final file = File(_dbPath!);
      return await file.length();
    } catch (_) {
      return null;
    }
  }

  /// 检查页面是否在离线库中
  static Future<bool> hasPage(String link) async {
    if (_db == null) return false;
    final cleanLink = link.startsWith('/') ? link.substring(1) : link;
    try {
      final rows = await _db!.rawQuery(
        'SELECT 1 FROM pages WHERE link = ?', [cleanLink]
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════
  //  HTTP 下载 & 导入
  // ═══════════════════════════════════════════

  /// 从 GitHub Releases 下载离线数据库
  ///
  /// [onProgress]: (receivedBytes, totalBytes) → void
  /// 返回下载到的文件路径，或 null（失败）
  static Future<String?> download({
    required String url,
    required String destPath,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final file = File(destPath);
      await file.parent.create(recursive: true);

      final request = http.Request('GET', Uri.parse(url));
      final streamed = await http.Client().send(request);
      final total = streamed.contentLength ?? -1;
      final bytes = <int>[];
      int received = 0;

      await for (final chunk in streamed.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }

      await file.writeAsBytes(bytes);

      // 验证文件
      final ok = await loadFromPath(destPath);
      return ok ? destPath : null;
    } catch (e) {
      print('OfflineContentDb.download error: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════
  //  工具函数
  // ═══════════════════════════════════════════

  /// gzip 解压为 UTF-8 字符串
  static String gzipDecode(Uint8List data) {
    final decompressed = gzip.decode(data);
    return utf8.decode(decompressed);
  }

  /// CJK 分词：在中文/日文/韩文字符间插入空格（与 Python 脚本保持一致）
  static String tokenizeCjk(String text) {
    final buf = StringBuffer();
    for (final ch in text.codeUnits) {
      if ((ch >= 0x4E00 && ch <= 0x9FFF) ||   // CJK Unified
          (ch >= 0x3400 && ch <= 0x4DBF) ||   // CJK Extension A
          (ch >= 0xF900 && ch <= 0xFAFF) ||   // CJK Compatibility
          (ch >= 0x3000 && ch <= 0x303F) ||   // CJK Symbols
          (ch >= 0xFF00 && ch <= 0xFFEF)) {   // Fullwidth Forms
        buf.write(' ');
        buf.writeCharCode(ch);
        buf.write(' ');
      } else {
        buf.writeCharCode(ch);
      }
    }
    return buf.toString().trim();
  }

  /// 清理 FTS5 snippet 中的 CJK 分词空格
  static String _cleanSnippet(String snippet) {
    return snippet.replaceAll(RegExp(r'(?<!\b)<b>|<b>(?!\b)'), '<b>')
        .replaceAll(RegExp(r'(?<!\b)</b>|</b>(?!\b)'), '</b>')
        .replaceAll(RegExp(r'(?<=[^\s]) (?=[^\s<])'), '')
        .trim();
  }

  /// SQL LIKE 转义
  static String _escapeLike(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }

  static bool _listEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
