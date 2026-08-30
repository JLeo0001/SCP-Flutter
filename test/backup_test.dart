import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scp_app/core/ai/ai_models.dart';
import 'package:scp_app/core/models/favorite_model.dart';
import 'package:scp_app/core/services/backup_service.dart';
import 'package:scp_app/core/services/preference_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferenceService.init();
  });

  setUp(() async {
    await PreferenceService.clearFavorites();
    await PreferenceService.setAiSettingsJson('');
  });

  group('偏好导出/导入', () {
    test('exportAll→importMap 往返,类型保持', () async {
      PreferenceService.setLineHeight(1.8);
      PreferenceService.setKeepScreenOn(true);
      PreferenceService.setFontFamily(2);
      PreferenceService.saveNickname('测试用户');

      final map = PreferenceService.exportAll();
      // 模拟文件往返
      final back = jsonDecode(jsonEncode(map)) as Map<String, dynamic>;
      // 破坏现场
      PreferenceService.setLineHeight(2.5);
      PreferenceService.setKeepScreenOn(false);
      PreferenceService.setFontFamily(0);
      PreferenceService.saveNickname('');

      final n = await PreferenceService.importMap(back);
      expect(n, greaterThanOrEqualTo(4));
      expect(PreferenceService.getLineHeight(), 1.8);
      expect(PreferenceService.getLineHeight(), isA<double>());
      expect(PreferenceService.getKeepScreenOn(), isTrue);
      expect(PreferenceService.getFontFamily(), 2);
      expect(PreferenceService.getNickname(), '测试用户');
    });

    test('AI 配置与自由收藏可被排除在偏好导出外', () async {
      await PreferenceService.setAiSettingsJson('{"x":1}');
      await PreferenceService.addFavorite(
          const FavoriteEntry(id: 'f1', content: 'c', createdAt: 1));
      final map = PreferenceService.exportAll();
      expect(map.containsKey(PreferenceService.aiSettingsKey), isTrue);
      expect(map.containsKey(PreferenceService.favoriteKey), isTrue);
      // BackupService.export 的 prefs 分支应排除这两块
      final json = await BackupService.export(const BackupOptions(
        prefs: true,
        ai: false,
        favorites: false,
        likesRead: false,
        records: false,
        positions: false,
        drafts: false,
      ));
      final j = jsonDecode(json) as Map<String, dynamic>;
      expect((j['prefs'] as Map).containsKey('ai_settings'), isFalse);
      expect((j['prefs'] as Map).containsKey('favorite_entries'), isFalse);
    });
  });

  group('自由收藏恢复', () {
    test('merge 按 id 去重合并', () async {
      await PreferenceService.addFavorite(
          const FavoriteEntry(id: 'f1', content: '已有', createdAt: 1));
      final n = await PreferenceService.importFavorites([
        {'id': 'f1', 'content': '重复', 'createdAt': 2},
        {'id': 'f2', 'content': '新条目', 'createdAt': 3},
      ], merge: true);
      expect(n, 1);
      final list = PreferenceService.getFavorites();
      expect(list, hasLength(2));
      expect(list.firstWhere((e) => e.id == 'f1').content, '已有');
    });

    test('replace 整表替换', () async {
      await PreferenceService.addFavorite(
          const FavoriteEntry(id: 'f1', content: '旧', createdAt: 1));
      final n = await PreferenceService.importFavorites([
        {'id': 'f9', 'content': '新表', 'createdAt': 5},
      ], merge: false);
      expect(n, 1);
      final list = PreferenceService.getFavorites();
      expect(list, hasLength(1));
      expect(list.first.id, 'f9');
    });
  });

  group('BackupService 解析与恢复', () {
    const cats = BackupOptions(
      prefs: true,
      ai: true,
      favorites: true,
      likesRead: false,
      records: false,
      positions: false,
      drafts: false,
    );

    test('tryParse:合法/异应用/更高版本/脏数据', () {
      final good = BackupService.tryParse(
          jsonEncode({'app': 'scp_flutter', 'schema': 1, 'createdAt': 5}));
      expect(good, isNotNull);
      expect(good!.schema, 1);
      expect(BackupService.tryParse(jsonEncode({'app': 'other', 'schema': 1})),
          isNull);
      expect(
          BackupService.tryParse(jsonEncode({
            'app': 'scp_flutter',
            'schema': 99,
          })),
          isNull);
      expect(BackupService.tryParse('not json'), isNull);
    });

    test('导出→清空→恢复 偏好+AI+收藏 全链路', () async {
      PreferenceService.setLineHeight(2.2);
      PreferenceService.saveNickname('备份测试');
      await PreferenceService.setAiSettingsJson(
          jsonEncode({'masterEnabled': true, 'providers': []}));
      await PreferenceService.addFavorite(
          const FavoriteEntry(id: 'fa', content: '收藏A', createdAt: 10));
      await PreferenceService.addFavorite(
          const FavoriteEntry(id: 'fb', content: '收藏B', createdAt: 20));

      final json = await BackupService.export(cats);

      // 清空现场
      PreferenceService.setLineHeight(1.0);
      PreferenceService.saveNickname('');
      await PreferenceService.setAiSettingsJson('');
      await PreferenceService.clearFavorites();

      final file = BackupService.tryParse(json)!;
      expect(file.has('prefs'), isTrue);
      expect(file.count('favorites'), 2);
      final r = await BackupService.restore(file, cats: cats, merge: true);
      expect(r.counts['prefs'], greaterThanOrEqualTo(2));
      expect(r.counts['favorites'], 2);
      expect(r.counts['ai'], 1);

      expect(PreferenceService.getLineHeight(), 2.2);
      expect(PreferenceService.getNickname(), '备份测试');
      expect(PreferenceService.getAiSettingsJson(), isNotEmpty);
      expect(AiSettingsStore.loadSync().ctxToolMigrated, isTrue);
      final favs = PreferenceService.getFavorites();
      expect(favs.map((e) => e.id), containsAll(['fa', 'fb']));
    });

    test('恢复空类目文件,结果为空统计', () async {
      final file = BackupService.tryParse(jsonEncode({
        'app': 'scp_flutter',
        'schema': 1,
        'createdAt': 1,
      }))!;
      final r = await BackupService.restore(file, cats: cats, merge: true);
      expect(r.empty, isTrue);
    });
  });
}
