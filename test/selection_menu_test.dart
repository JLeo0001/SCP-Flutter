import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scp_app/features/detail/selection_menu.dart';

void main() {
  group('SelectionReport.tryParse', () {
    test('show 消息:按 scale 与视口偏移换算', () {
      final r = SelectionReport.tryParse(
          '{"t":"show","text":"Keter 等级","rect":{"x":100,"y":200,"w":50,"h":20},"scale":2,"ox":10,"oy":5}');
      expect(r, isNotNull);
      expect(r!.show, isTrue);
      expect(r.text, 'Keter 等级');
      expect(r.rect, const Rect.fromLTWH(180, 390, 100, 40));
    });

    test('无 visualViewport 参数时按 scale=1 处理', () {
      final r = SelectionReport.tryParse(
          '{"t":"show","text":"abc","rect":{"x":1,"y":2,"w":3,"h":4}}');
      expect(r!.rect, const Rect.fromLTWH(1, 2, 3, 4));
    });

    test('clear / 空白选区 / 脏数据', () {
      expect(SelectionReport.tryParse('{"t":"clear"}')!.show, isFalse);
      expect(SelectionReport.tryParse('not json'), isNull);
      expect(
        SelectionReport.tryParse(
                '{"t":"show","text":"   ","rect":{"x":0,"y":0,"w":0,"h":0}}')!
            .show,
        isFalse,
      );
    });
  });

  group('computeMenuOffset', () {
    test('默认放选区下方,水平居中', () {
      final off = computeMenuOffset(
        sel: const Rect.fromLTWH(110, 100, 60, 30),
        menu: const Size(280, 200),
        bounds: const Size(400, 800),
      );
      expect(off, const Offset(8, 138));
    });

    test('下方放不下 → 移到选区上方', () {
      final off = computeMenuOffset(
        sel: const Rect.fromLTWH(100, 700, 60, 30),
        menu: const Size(280, 200),
        bounds: const Size(400, 800),
      );
      expect(off, const Offset(8, 492)); // left 居中后越界被夹到 8;above=700-8-200
    });

    test('上下都放不下时贴底', () {
      final off = computeMenuOffset(
        sel: const Rect.fromLTWH(100, 396, 60, 8),
        menu: const Size(280, 480),
        bounds: const Size(400, 500),
      );
      expect(off.dy, 12);
    });
  });

  _moveTests();
}

void _moveTests() {
  group('SelectionReport.tryParse move(滚动跟随)', () {
    test('move 消息:只带矩形,move=true,text 为空', () {
      final r = SelectionReport.tryParse(
          '{"t":"move","rect":{"x":10,"y":20,"w":30,"h":40},"scale":2,"ox":5,"oy":5}');
      expect(r, isNotNull);
      expect(r!.show, isTrue);
      expect(r.move, isTrue);
      expect(r.text, '');
      expect(r.rect, const Rect.fromLTWH(10, 30, 60, 80));
    });

    test('show 消息 move=false;clear 消息 move=false', () {
      expect(
          SelectionReport.tryParse(
              '{"t":"show","text":"x","rect":{"x":1,"y":1,"w":1,"h":1}}')!
              .move,
          isFalse);
      expect(SelectionReport.tryParse('{"t":"clear"}')!.move, isFalse);
    });
  });

  group('SelectionMenu 布局(全屏撑开回归)', () {
    testWidgets('卡片保持 260px 宽、内容高,不被撑满全屏', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            SelectionMenu(
              selRect: const Rect.fromLTWH(100, 300, 100, 20),
              bg: Colors.white,
              fg: Colors.black,
              border: Colors.grey,
              dark: false,
              quick: const [
                SelectionAction('copy', '复制', Icons.copy),
                SelectionAction('fav', '收藏', Icons.bookmark_add),
              ],
              items: const [
                SelectionAction('t2s', '转简体', Icons.spellcheck),
              ],
              onAction: (_) {},
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      final box = tester.renderObject<RenderBox>(
          find.descendant(
              of: find.byType(SelectionMenu), matching: find.byType(Column)).first);
      expect(box.size.width, moreOrLessEquals(260, epsilon: 2),
          reason: '卡片宽度应为 260(±边框)而非全屏');
      expect(box.size.height, lessThan(150), reason: '折叠时卡片高度应只有图标行高');
    });
  });
}
