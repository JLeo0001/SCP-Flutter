import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

/// 暗色模式下「作者硬编码浅色块」的回归测试。
///
/// 背景：SCP-5000(https://scp-wiki-cn.wikidot.com/alive) 的故事概述卡是
/// `<div style="border:solid 1px #999999; background:#f0eeee">` 这种**纯内联浅色背景、
/// 且元素自己没有 color** 的块。旧版 darkFixJs 只会"把深色文字提亮"，从不改 background，
/// 于是块保持浅灰白底、文字却继承 body 的浅色字 → 浅底压浅字（对比度 1.28:1，近乎看不见）。
///
/// 这些断言不依赖浏览器，而是校验注入脚本的判据 + 调色板数值，防止再次退化。
void main() {
  final src = File('lib/features/detail/detail_page.dart').readAsStringSync();

  group('浅色块反转（darkFixJs）', () {
    test('按"实际生效主题"注入，而非只看系统 isDark', () {
      expect(src, contains('String darkFixJs = pal.isDarkTheme'));
    });

    test('第一遍会把自绘浅色背景压成主题 blockBg（不区分 class / 内联 style）', () {
      expect(src, contains("setProperty('background-color','\$blockBg','important')"));
    });

    test('判据基于计算样式而非 class 名，故对所有文档的浅色块通用', () {
      // 取背景来自 getComputedStyle；没有 class 白名单参与判断
      final js = src.substring(
        src.indexOf('String darkFixJs'),
        src.indexOf("''' : '';"),
      );
      expect(js, contains("getComputedStyle(el)"));
      expect(js, contains("backgroundColor"));
      // 关键：不再有"背景深浅 == body 深浅就跳过"的旧短路
      expect(js, isNot(contains('isDarkBg(bg)===isDarkBg(bodyBg)')));
    });

    test('阅读器自身浮层(_progress/_ruler/_lightbox/_fnpop)不被压暗', () {
      expect(src, contains("if(el.id&&el.id.indexOf('_')===0)return;"));
    });

    test('pre/code 豁免；作者低饱和灰黑字才反色，饱和强调色保留', () {
      final js = src.substring(
        src.indexOf('String darkFixJs'),
        src.indexOf("''' : '';"),
      );
      expect(js, contains("closest('pre')"));
      expect(js, contains("closest('code')"));
      // 用 descriptor 区分"作者自己写的 color"与"继承来的 color"
      expect(js, contains("Object.getOwnPropertyDescriptor(el.style,'color')"));
      // 饱和度门槛：高饱和(red/blue 等语义色)不覆盖
      expect(js, contains('sat'));
    });

    test('链接按脚下背景定深浅', () {
      final js = src.substring(
        src.indexOf('String darkFixJs'),
        src.indexOf("''' : '';"),
      );
      expect(js, contains("querySelectorAll('a')"));
      expect(js, contains("'#1565c0'"));
    });
  });

  group('CSS 兜底（JS 执行前的瞬时防闪）', () {
    test('把该页这类带 style 的浅灰容器用属性选择器压到 blockBg', () {
      expect(src, contains('[style*="background:#f0eeee"]'));
    });
  });

  group('调色板数值（对比度不达标即失败）', () {
    double relLuma(String hex) {
      final h = hex.replaceAll('#', '');
      double ch(int i) {
        final v = int.parse(h.substring(i, i + 2), radix: 16) / 255.0;
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
      }
      return 0.2126 * ch(0) + 0.7152 * ch(2) + 0.0722 * ch(4);
    }

    double contrast(String a, String b) {
      final l1 = relLuma(a), l2 = relLuma(b);
      final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
      return (hi + 0.05) / (lo + 0.05);
    }

    test('修复前确实不可读：浅色正文 / 作者浅灰底 < 2:1', () {
      expect(contrast('#d4d4d8', '#f0eeee'), lessThan(2.0));
    });

    test('修复后可读：深色主题 浅色正文 / blockBg >= 7:1', () {
      expect(contrast('#d4d4d8', '#22223a'), greaterThanOrEqualTo(7.0));
    });

    test('修复后可读：纯黑主题 浅色正文 / blockBg >= 8:1', () {
      expect(contrast('#d4d4d8', '#1a1a1a'), greaterThanOrEqualTo(8.0));
    });

    test('护眼主题浅底配深色正文 >= 5:1', () {
      expect(contrast('#5b4636', '#ede4c8'), greaterThanOrEqualTo(5.0));
    });
  });
}
