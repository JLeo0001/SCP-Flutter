import 'dart:convert';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../ai/ai_models.dart';
import 'database_helper.dart';
import 'preference_service.dart';

/// 备份内容选择(导出与恢复共用同一组开关)
class BackupOptions {
  final bool prefs; // 偏好与阅读设置(不含 AI/收藏)
  final bool ai; // AI 配置(含供应商密钥)
  final bool favorites; // 自由收藏
  final bool likesRead; // 点赞与已读
  final bool records; // 阅读历史/待读列表
  final bool positions; // 阅读位置
  final bool drafts; // 草稿

  const BackupOptions({
    this.prefs = true,
    this.ai = true,
    this.favorites = true,
    this.likesRead = true,
    this.records = true,
    this.positions = true,
    this.drafts = true,
  });

  bool get any =>
      prefs || ai || favorites || likesRead || records || positions || drafts;
}

/// 解析后的备份文件
class BackupFile {
  final Map<String, dynamic> raw;
  final int schema;
  final int createdAt;

  const BackupFile(this.raw, this.schema, this.createdAt);

  bool has(String key) => raw[key] != null;

  int count(String key) {
    final v = raw[key];
    if (v is List) return v.length;
    if (v is Map) return v.length;
    return 0;
  }
}

/// 恢复结果:每个类目的实际写入条数
class RestoreResult {
  final Map<String, int> counts = {};

  void add(String key, int n) {
    if (n > 0) counts[key] = n;
  }

  bool get empty => counts.isEmpty;

  String get summary {
    const names = {
      'prefs': '偏好',
      'ai': 'AI配置',
      'favorites': '收藏',
      'likes': '点赞/已读',
      'records': '历史/待读',
      'positions': '阅读位置',
      'drafts': '草稿',
    };
    return [
      for (final e in counts.entries)
        '${names[e.key] ?? e.key} ${e.value}',
    ].join(' · ');
  }
}

/// 个性化数据备份/恢复:偏好 + AI 配置 + 收藏 + 点赞已读 + 历史待读 + 阅读位置 + 草稿
///
/// 文件为带缩进的 JSON;离线文档缓存体积大,不在备份范围。
class BackupService {
  static const int schemaVersion = 1;
  static const String appTag = 'scp_flutter';

  /// 收集备份 JSON(已带缩进排版)
  static Future<String> export(BackupOptions o) async {
    final data = <String, dynamic>{
      'app': appTag,
      'schema': schemaVersion,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (o.prefs) {
      data['prefs'] = {
        for (final e in PreferenceService.exportAll().entries)
          if (e.key != PreferenceService.aiSettingsKey &&
              e.key != PreferenceService.favoriteKey)
            e.key: e.value,
      };
    }
    if (o.ai) data['aiSettings'] = PreferenceService.getAiSettingsJson();
    if (o.favorites) {
      data['favorites'] = [
        for (final f in PreferenceService.getFavorites()) f.toJson(),
      ];
    }
    final needDb = o.likesRead || o.records || o.positions || o.drafts;
    final db = needDb ? await DatabaseHelper.getDataDb() : null;
    if (db != null && o.likesRead) {
      data['likes'] = await db.query('likes');
    }
    if (db != null && o.records) {
      data['records'] = await db.query('records');
    }
    if (db != null && o.positions) {
      data['positions'] = await db.query('reading_positions');
    }
    if (db != null && o.drafts) {
      data['drafts'] = await db.query('drafts');
    }
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 解析备份文件;非本应用/更高 schema 返回 null
  static BackupFile? tryParse(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      if (j['app'] != appTag) return null;
      final schema = (j['schema'] as num?)?.toInt() ?? 0;
      if (schema > schemaVersion) return null;
      return BackupFile(j, schema, (j['createdAt'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }

  /// 恢复;[merge] 为 true 时列表类数据按主键去重合并,false 时整表替换
  static Future<RestoreResult> restore(
    BackupFile file, {
    required BackupOptions cats,
    required bool merge,
  }) async {
    final r = RestoreResult();
    final raw = file.raw;

    if (cats.prefs && raw['prefs'] is Map<String, dynamic>) {
      final n = await PreferenceService.importMap(raw['prefs']);
      r.add('prefs', n);
    }
    if (cats.ai && raw['aiSettings'] is String) {
      final s = raw['aiSettings'] as String;
      if (s.isNotEmpty) {
        await PreferenceService.setAiSettingsJson(s);
        AiSettingsStore.reload(); // 刷新进程内缓存,设置/阅读页立即生效
        r.add('ai', 1);
      }
    }
    if (cats.favorites && raw['favorites'] is List) {
      final n = await PreferenceService
          .importFavorites(raw['favorites'] as List, merge: merge);
      r.add('favorites', n);
    }

    final needDb =
        cats.likesRead || cats.records || cats.positions || cats.drafts;
    final db = needDb ? await DatabaseHelper.getDataDb() : null;
    if (db != null && cats.likesRead && raw['likes'] is List) {
      var n = 0;
      for (final row in raw['likes'] as List) {
        if (row is! Map<String, dynamic>) continue;
        final link = row['link'];
        if (link is! String || link.isEmpty) continue;
        await db.insert('likes', row, conflictAlgorithm: ConflictAlgorithm.replace);
        n++;
      }
      r.add('likes', n);
    }
    if (db != null && cats.records && raw['records'] is List) {
      var n = 0;
      for (final row in raw['records'] as List) {
        if (row is! Map<String, dynamic>) continue;
        final link = row['link'];
        if (link is! String || link.isEmpty) continue;
        await db.insert('records', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
        n++;
      }
      r.add('records', n);
    }
    if (db != null && cats.positions && raw['positions'] is List) {
      var n = 0;
      for (final row in raw['positions'] as List) {
        if (row is! Map<String, dynamic>) continue;
        final link = row['link'];
        if (link is! String || link.isEmpty) continue;
        await db.insert('reading_positions', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
        n++;
      }
      r.add('positions', n);
    }
    if (db != null && cats.drafts && raw['drafts'] is List) {
      final rows = [
        for (final row in raw['drafts'] as List)
          if (row is Map<String, dynamic>) row,
      ];
      if (!merge) await db.delete('drafts');
      var n = 0;
      if (merge) {
        // 无主键语义:按 (标题, 内容) 去重
        final exist = await db.query('drafts');
        final seen = {
          for (final d in exist)
            '${d['title'] ?? ''}\u241f${d['content'] ?? ''}',
        };
        for (final row in rows) {
          final key =
              '${row['title'] ?? ''}\u241f${row['content'] ?? ''}';
          if (seen.contains(key)) continue;
          seen.add(key);
          await db.insert('drafts', {
            'title': row['title'],
            'content': row['content'],
            'updated_at': row['updated_at'],
          });
          n++;
        }
      } else {
        for (final row in rows) {
          await db.insert('drafts', row,
              conflictAlgorithm: ConflictAlgorithm.replace);
          n++;
        }
      }
      r.add('drafts', n);
    }
    return r;
  }
}
