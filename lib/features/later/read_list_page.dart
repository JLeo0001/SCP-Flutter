import 'package:flutter/material.dart';
import '../../core/services/database_helper.dart';
import '../../core/models/scp_like_model.dart';
import '../detail/detail_page.dart';

/// 已读列表页 — 支持长按多选批量取消已读
class ReadListPage extends StatefulWidget {
  const ReadListPage({super.key});

  @override
  State<ReadListPage> createState() => _ReadListPageState();
}

class _ReadListPageState extends State<ReadListPage> {
  List<ScpLikeModel> _items = [];
  bool _loading = true;
  bool _selectMode = false;
  final Set<String> _selectedLinks = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (DateTime.now().difference(_lastLoad).inSeconds > 2 && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('还没有已读文章', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    final batchBar = _selectMode ? Container(
      color: cs.primaryContainer.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('已选 ${_selectedLinks.length} 项',
              style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface)),
          const Spacer(),
          TextButton.icon(
            onPressed: _batchUnread,
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('取消已读'),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
          ),
          TextButton(
            onPressed: () => setState(() { _selectMode = false; _selectedLinks.clear(); }),
            child: const Text('取消'),
          ),
        ],
      ),
    ) : const SizedBox.shrink();

    return Column(
      children: [
        batchBar,
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final item = _items[i];
                final selected = _selectedLinks.contains(item.link);
                return Dismissible(
                  key: Key(item.link),
                  direction: _selectMode ? DismissDirection.none : DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: Colors.orange,
                    child: const Icon(Icons.undo, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await DatabaseHelper.setUnread(item.link);
                    _load();
                  },
                  child: ListTile(
                    selected: selected,
                    leading: _selectMode
                        ? Checkbox(
                            value: selected,
                            onChanged: (_) => _toggleSelect(item.link),
                          )
                        : CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            child: Icon(Icons.check_circle_outline, size: 18,
                                color: cs.onPrimaryContainer),
                          ),
                    title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: _selectMode ? null : const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      if (_selectMode) {
                        _toggleSelect(item.link);
                      } else {
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => DetailPage(link: item.link, title: item.title)));
                      }
                    },
                    onLongPress: () {
                      if (!_selectMode) {
                        setState(() { _selectMode = true; _selectedLinks.add(item.link); });
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _toggleSelect(String link) {
    setState(() {
      if (_selectedLinks.contains(link)) {
        _selectedLinks.remove(link);
        if (_selectedLinks.isEmpty) _selectMode = false;
      } else {
        _selectedLinks.add(link);
      }
    });
  }

  Future<void> _batchUnread() async {
    if (_selectedLinks.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量取消已读'),
        content: Text('确定将选中的 ${_selectedLinks.length} 篇标记为未读？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    for (final link in _selectedLinks) {
      await DatabaseHelper.setUnread(link);
    }
    setState(() { _selectMode = false; _selectedLinks.clear(); });
    _load();
  }

  DateTime _lastLoad = DateTime(2000);
  Future<void> _load() async {
    try {
      final items = await DatabaseHelper.getAllRead();
      if (mounted) setState(() { _items = items; _loading = false; _lastLoad = DateTime.now(); });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }
}
