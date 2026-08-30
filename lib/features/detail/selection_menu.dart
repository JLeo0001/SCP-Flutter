import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════
///  应用内框选菜单 —— WebView 选区上报 + 紧凑浮动菜单(Win11 风格)
///  默认只显示一行图标小药丸,悬浮在选区旁;点展开才显示完整功能列表
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

/// 紧凑浮动框选菜单:一行图标 + 可展开列表,带弹出动画(缩放+淡入)
class SelectionMenu extends StatefulWidget {
  final Rect selRect;
  final Color bg;
  final Color fg;
  final Color border;
  final bool dark;
  final List<SelectionAction> quick; // 常驻图标行
  final List<SelectionAction> items; // 展开后的带标签列表
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
  State<SelectionMenu> createState() => _SelectionMenuState();
}

class _SelectionMenuState extends State<SelectionMenu> with SingleTickerProviderStateMixin {
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _pop.forward();
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  /// 选区中点在屏幕上半 → 菜单在下方,从选区一侧生长
  bool get _growFromTop {
    final h = MediaQuery.of(context).size.height;
    return widget.selRect.center.dy < h / 2;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _WinMenuDelegate(widget.selRect),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _pop, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: CurvedAnimation(parent: _pop, curve: Curves.easeOutBack),
            alignment: _growFromTop ? Alignment.topCenter : Alignment.bottomCenter,
            child: _card(),
          ),
        ),
      ),
    );
  }

  Widget _card() {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: widget.border.withValues(alpha: widget.dark ? 0.7 : 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.dark ? 0.5 : 0.2),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              color: widget.bg.withValues(alpha: widget.dark ? 0.88 : 0.92),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: Row(
                      children: [
                        for (final a in widget.quick) _quickBtn(a),
                        const Spacer(),
                        _expandBtn(),
                      ],
                    ),
                  ),
                  ClipRect(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeInOutCubic,
                      alignment: Alignment.topCenter,
                      child: !_expanded
                          ? const SizedBox(width: double.infinity)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _sep(),
                                for (final a in widget.items) _listItem(a),
                                const SizedBox(height: 3),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sep() => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        color: widget.fg.withValues(alpha: 0.08),
      );

  Widget _quickBtn(SelectionAction a) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => widget.onAction(a),
        child: Tooltip(
          message: a.label,
          child: Container(
            height: 38,
            width: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: widget.fg.withValues(alpha: 0.05),
            ),
            child: Icon(a.icon, size: 18, color: widget.fg),
          ),
        ),
      ),
    );
  }

  Widget _expandBtn() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _expanded = !_expanded),
      child: SizedBox(
        height: 38,
        width: 34,
        child: AnimatedRotation(
          turns: _expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 160),
          child: Icon(Icons.keyboard_arrow_down, size: 20, color: widget.fg.withValues(alpha: 0.7)),
        ),
      ),
    );
  }

  Widget _listItem(SelectionAction a) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => widget.onAction(a),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            children: [
              Icon(a.icon, size: 17, color: widget.fg.withValues(alpha: 0.85)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  a.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: widget.fg),
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
