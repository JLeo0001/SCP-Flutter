import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scp_app/core/models/favorite_model.dart';
import 'package:scp_app/core/services/preference_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferenceService.init();
  });

  setUp(() async {
    await PreferenceService.clearFavorites();
  });

  FavoriteEntry entry(String id, String content, {int at = 0}) =>
      FavoriteEntry(
        id: id,
        content: content,
        source: 'SCP-173',
        link: 'https://scp-wiki-cn.wikidot.com/scp-173',
        createdAt: at,
      );

  group('FavoriteEntry JSON', () {
    test('往返序列化保留全部字段', () {
      final e = entry('f1', '项目等级：Keter', at: 1700000000000);
      final back = FavoriteEntry.listFromJsonString(
          FavoriteEntry.listToJsonString([e]));
      expect(back, hasLength(1));
      expect(back.first.id, 'f1');
      expect(back.first.content, '项目等级：Keter');
      expect(back.first.source, 'SCP-173');
      expect(back.first.link, 'https://scp-wiki-cn.wikidot.com/scp-173');
      expect(back.first.createdAt, 1700000000000);
    });

    test('空 source/link 序列化后回读为空串', () {
      final e = const FavoriteEntry(id: 'f2', content: 'abc', createdAt: 1);
      final back = FavoriteEntry.listFromJsonString(
          FavoriteEntry.listToJsonString([e]));
      expect(back.first.source, '');
      expect(back.first.link, '');
    });

    test('脏 JSON / 非列表 / 含坏条目时容错', () {
      expect(FavoriteEntry.listFromJsonString('not json'), isEmpty);
      expect(FavoriteEntry.listFromJsonString('{"id":"x"}'), isEmpty);
      expect(FavoriteEntry.listFromJsonString(''), isEmpty);
      final back = FavoriteEntry.listFromJsonString(
          '[{"id":"ok","content":"t","createdAt":5},"junk",7]');
      expect(back, hasLength(1));
      expect(back.first.id, 'ok');
    });

    test('preview 取首行并截断', () {
      expect(const FavoriteEntry(id: 'a', content: '  第一行\n第二行  ', createdAt: 0).preview,
          '第一行');
      expect(FavoriteEntry(id: 'a', content: 'x' * 70, createdAt: 0).preview.length,
          61); // 60 字 + 省略号
      expect(const FavoriteEntry(id: 'a', content: '   ', createdAt: 0).preview, '');
    });

    test('timeLabel 相对时间', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(entry('a', 'c', at: now).timeLabel, '刚刚');
      expect(entry('a', 'c', at: now - 5 * 60 * 1000).timeLabel, '5分钟前');
      expect(entry('a', 'c', at: now - 3 * 3600 * 1000).timeLabel, '3小时前');
    });
  });

  group('自由收藏存取 (PreferenceService)', () {
    test('初始为空', () {
      expect(PreferenceService.getFavorites(), isEmpty);
    });

    test('addFavorite 新条目插到最前', () async {
      await PreferenceService.addFavorite(entry('f1', '第一条'));
      await PreferenceService.addFavorite(entry('f2', '第二条'));
      final list = PreferenceService.getFavorites();
      expect(list.map((e) => e.id).toList(), ['f2', 'f1']);
    });

    test('与最近一条内容相同视为重复点击,不新增', () async {
      final ok = await PreferenceService.addFavorite(entry('f1', '  相同内容  '));
      expect(ok, isTrue);
      final dup = await PreferenceService.addFavorite(entry('f2', '相同内容'));
      expect(dup, isFalse);
      expect(PreferenceService.getFavorites(), hasLength(1));
      // 与旧条目(非最近一条)重复不拦截
      final again = await PreferenceService.addFavorite(entry('f3', '第一条x'));
      await PreferenceService.addFavorite(entry('f4', '新内容'));
      final dup2 = await PreferenceService.addFavorite(entry('f5', '第一条x'));
      expect(again, isTrue);
      expect(dup2, isTrue);
      expect(PreferenceService.getFavorites().length, greaterThanOrEqualTo(3));
    });

    test('removeFavorite 按 id 删除', () async {
      await PreferenceService.addFavorite(entry('f1', 'a'));
      await PreferenceService.addFavorite(entry('f2', 'b'));
      await PreferenceService.removeFavorite('f1');
      expect(PreferenceService.getFavorites().map((e) => e.id), ['f2']);
    });

    test('insertFavoriteAt 撤销删除按原位置放回', () async {
      await PreferenceService.addFavorite(entry('f1', 'a'));
      await PreferenceService.addFavorite(entry('f2', 'b'));
      await PreferenceService.addFavorite(entry('f3', 'c'));
      // 列表为 [f3, f2, f1],删 f2(索引 1)后撤销
      await PreferenceService.removeFavorite('f2');
      await PreferenceService.insertFavoriteAt(
          1, const FavoriteEntry(id: 'f2', content: 'b', createdAt: 0));
      expect(PreferenceService.getFavorites().map((e) => e.id).toList(),
          ['f3', 'f2', 'f1']);
      // 越界索引夹取
      await PreferenceService.insertFavoriteAt(
          99, const FavoriteEntry(id: 'f4', content: 'd', createdAt: 0));
      expect(PreferenceService.getFavorites().last.id, 'f4');
    });

    test('updateFavoriteContent 只改目标条目', () async {
      await PreferenceService.addFavorite(entry('f1', '旧内容'));
      await PreferenceService.addFavorite(entry('f2', '别的'));
      await PreferenceService.updateFavoriteContent('f1', '新内容');
      final list = PreferenceService.getFavorites();
      expect(list.firstWhere((e) => e.id == 'f1').content, '新内容');
      expect(list.firstWhere((e) => e.id == 'f2').content, '别的');
    });

    test('clearFavorites 清空', () async {
      await PreferenceService.addFavorite(entry('f1', 'a'));
      await PreferenceService.clearFavorites();
      expect(PreferenceService.getFavorites(), isEmpty);
    });
  });
}
