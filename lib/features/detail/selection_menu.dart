import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════
///  应用内框选菜单 —— WebView 选区上报 + Windows 11 风格悬浮菜单
/// ═══════════════════════════════════════════════════════════

/// WebView `Selection` 通道消息解析
class SelectionReport {
  final bool show;
  final String text;

  /// 选区在 WebView 视图内的逻辑坐标(已按缩放/视口偏移换算)
  final Rect rect;

  const SelectionReport({required this.show, required this.text, required this.rect});

  /// 解析 JS 上报的 JSON;t=show{text,rect,scale,ox,oy} / t=clear
  static SelectionReport? tryParse(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      if (j['t'] != 'show') return const SelectionReport(show: false, text: '', rect: Rect.zero);
      final text = (j['text'] as String?) ?? '';
      if (text.trim().isEmpty) return const SelectionReport(show: false, text: '', rect: Rect.zero);
      final r = j['rect'];
      if (r is! Map) return null;
      double d(dynamic v) => (v is num) ? v.toDouble() : 0;
      final scale = (d(j['scale']) <= 0) ? 1.0 : d(j['scale']);
      final ox = d(j['ox']);
      final oy = d(j['oy']);
      final rect = Rect.fromLTWH(
        (d(r['x']) - ox) * scale,
        (d(r['y']) - oy) * scale,
        d(r['w']) * scale,
        d(r['h']) * scale,
      );
      return SelectionReport(show: true, text: text, rect: rect);
    } catch (_) {
      return null;
    }
  }
}

/// 菜单放置:水平居中于选区并夹取;优先放选区下方,空间不足放上方
Offset computeMenuOffset({
  required Rect sel,
  required Size menu,
  required Size bounds,
  double margin = 8,
  double gap = 8,
}) {
  final maxLeft = math.max(margin, bounds.width - menu.width - margin);
  var left = sel.center.dx - menu.width / 2;
  left = left.clamp(margin, maxLeft);
  var top = sel.bottom + gap;
  if (top + menu.height > bounds.height - margin) {
    final above = sel.top - gap - menu.height;
    top = above >= margin ? above : math.max(margin, bounds.height - menu.height - margin);
  }
  return Offset(left, top);
}

/// 菜单动作
class SelectionAction {
  final String id;
  final String label;
  final IconData icon;
  const SelectionAction(this.id, this.label, this.icon);
}

/// Windows 11 风格框选菜单:亚克力模糊底、大圆角、顶部图标快捷行 + 图标+文字列表
class SelectionMenu extends StatelessWidget {
  final Rect selRect;
  final Color bg;
  final Color fg;
  final Color border;
  final bool dark;
  final List<SelectionAction> quick; // 顶部图标行
  final List<SelectionAction> items; // 带标签列表
  final ValueChanged<SelectionAction> onAction;

  const SelectionMenu({
    super.key,
    required this.selRect,
    required this.bg,
    required this.fg,
    required this.border,
    required this.dark,
    required this.quick,
    required this.items,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _WinMenuDelegate(selRect),
        child: Container(
          width: 280,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border.withValues(alpha: dark ? 0.7 : 0.9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.55 : 0.22),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  decoration: BoxDecoration(
                    color: bg.withValues(alpha: dark ? 0.86 : 0.90),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          for (final a in quick) _quickBtn(a),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _sep(),
                      for (final a in items) _listItem(a),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sep() => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        color: fg.withValues(alpha: 0.08),
      );

  Widget _quickBtn(SelectionAction a) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onAction(a),
        child: Container(
          height: 40,
          width: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: fg.withValues(alpha: 0.05),
          ),
          child: Icon(a.icon, size: 19, color: fg),
        ),
      ),
    );
  }

  Widget _listItem(SelectionAction a) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onAction(a),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(a.icon, size: 18, color: fg.withValues(alpha: 0.85)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  a.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 按选区位置定位菜单(优先下方,不足则上方)
class _WinMenuDelegate extends SingleChildLayoutDelegate {
  final Rect selRect;
  const _WinMenuDelegate(this.selRect);

  @override
  Size getSize(BoxConstraints constraints) => constraints.biggest;

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return computeMenuOffset(sel: selRect, menu: childSize, bounds: size);
  }

  @override
  bool shouldRelayout(_WinMenuDelegate old) => old.selRect != selRect;
}
