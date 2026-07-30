import 'package:flutter/material.dart';
import '../../core/services/database_helper.dart';
import '../detail/detail_page.dart';

/// 编号直达 — 仿计算器键盘，Material Design 3 自适应
class DirectPage extends StatefulWidget {
  const DirectPage({super.key});

  @override
  State<DirectPage> createState() => _DirectPageState();
}

class _DirectPageState extends State<DirectPage> {
  String _number = '';
  bool _cn = false;
  bool _joke = false;

  String get _display {
    final buf = StringBuffer('SCP-');
    if (_cn) buf.write('CN-');
    buf.write(_number.isEmpty ? '???'.toUpperCase() : _number);
    if (_joke) buf.write('-J');
    return buf.toString();
  }

  void _press(String key) {
    if (_number.length >= 6) return;
    setState(() => _number += key);
  }

  void _backspace() {
    if (_number.isNotEmpty) {
      setState(() => _number = _number.substring(0, _number.length - 1));
    }
  }

  void _toggleCn() => setState(() => _cn = !_cn);
  void _toggleJoke() => setState(() => _joke = !_joke);

  Future<void> _go() async {
    if (_number.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入编号')));
      return;
    }

    final link = 'scp-${_cn ? 'cn-' : ''}$_number${_joke ? '-j' : ''}';

    // 本地数据库查找
    try {
      final titleSearch = _cn ? 'SCP-CN-$_number' : 'SCP-$_number';
      final results = await DatabaseHelper.searchScpByTitle(titleSearch);
      if (results.isNotEmpty && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailPage(link: results.first.link, title: results.first.title),
          ),
        );
        return;
      }
    } catch (_) {}

    // 从 Wikidot 直接访问
    if (mounted) {
      final title = 'SCP${_cn ? '-CN' : ''}-$_number${_joke ? '-J' : ''}';
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetailPage(link: link, title: title)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('编号直达')),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            // 显示区
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _display,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const Spacer(flex: 1),
            // 键盘区
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildKeypad(cs, theme),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad(ColorScheme cs, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行：CN / J / ←
        Row(
          children: [
            _toggleBtn(cs, 'CN', _cn, _toggleCn),
            const SizedBox(width: 12),
            _toggleBtn(cs, 'J', _joke, _toggleJoke),
            const SizedBox(width: 12),
            _actionBtn(cs, Icons.backspace_outlined, _backspace),
          ],
        ),
        const SizedBox(height: 12),
        // 数字 1-9
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: row.map((n) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: n == row.first ? 0 : 6,
                      right: n == row.last ? 0 : 6,
                    ),
                    child: _numBtn(cs, n),
                  ),
                );
              }).toList(),
            ),
          ),
        // 最后一行：0 + GO
        Row(
          children: [
            Expanded(
              flex: 1,
              child: _numBtn(cs, '0'),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _goBtn(cs),
            ),
          ],
        ),
      ],
    );
  }

  Widget _numBtn(ColorScheme cs, String digit) {
    return SizedBox(
      height: 64,
      child: FilledButton(
        onPressed: () => _press(digit),
        style: FilledButton.styleFrom(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Text(digit, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _toggleBtn(ColorScheme cs, String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: SizedBox(
        height: 64,
        child: active
            ? FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              )
            : OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
                  side: BorderSide(color: cs.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
              ),
      ),
    );
  }

  Widget _actionBtn(ColorScheme cs, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: SizedBox(
        height: 64,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.onSurfaceVariant,
            side: BorderSide(color: cs.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Icon(icon, size: 24),
        ),
      ),
    );
  }

  Widget _goBtn(ColorScheme cs) {
    return SizedBox(
      height: 64,
      child: FilledButton(
        onPressed: _go,
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.arrow_forward, size: 22),
            const SizedBox(width: 8),
            Text('GO', style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cs.onPrimary,
              letterSpacing: 2,
            )),
          ],
        ),
      ),
    );
  }
}
