import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/favorite_model.dart';
import '../../core/services/preference_service.dart';

/// 自由收藏页 — 每条收藏独立成框,框内文字可选取
class FavoriteListPage extends StatefulWidget {
  const FavoriteListPage({super.key});

  @override
  State<FavoriteListPage> createState() => _FavoriteListPageState();
}

class _FavoriteListPageState extends State<FavoriteListPage> {
  List<FavoriteEntry> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _items = PreferenceService.getFavorites();
      _loading = false;
    });
  }

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _copyAll(FavoriteEntry e) async {
    await Clipboard.setData(ClipboardData(text: e.content));
    _snack('已复制整段');
  }

  void _removeAt(int index) {
    final entry = _items[index];
    setState(() => _items.removeAt(index));
    PreferenceService.removeFavorite(entry.id);
    _snack('已删除收藏',
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            PreferenceService.insertFavoriteAt(index, entry);
            _reload();
          },
        ));
  }

  Future<void> _confirmClear() async {
    if (_items.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空自由收藏'),
        content: Text('确定删除全部 ${_items.length} 条收藏？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await PreferenceService.clearFavorites();
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: _loading
            ? const Text('自由收藏')
            : Text(_items.isEmpty ? '自由收藏' : '自由收藏 ${_items.length}'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bookmark_border, size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('还没有收藏', style: TextStyle(color: Colors.grey.shade500)),
                      const SizedBox(height: 8),
                      Text(
                        '阅读时框选文字,点菜单里的收藏图标即可加入',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: _items.length,
                    itemBuilder: (context, i) => _buildCard(_items[i], i, cs),
                  ),
                ),
    );
  }

  Widget _buildCard(FavoriteEntry e, int index, ColorScheme cs) {
    return Dismissible(
      key: ValueKey('fav_${e.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _removeAt(index),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 框内内容可选取
              SelectionArea(
                child: Text(
                  e.content,
                  style: const TextStyle(fontSize: 15, height: 1.6),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      e.source.isEmpty ? e.timeLabel : '${e.timeLabel} · ${e.source}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  _cardAction(
                    icon: Icons.copy_outlined,
                    tooltip: '复制整段',
                    onTap: () => _copyAll(e),
                  ),
                  _cardAction(
                    icon: Icons.delete_outline,
                    tooltip: '删除',
                    onTap: () => _removeAt(index),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: cs.onSurface.withValues(alpha: 0.55)),
        ),
      ),
    );
  }
}
