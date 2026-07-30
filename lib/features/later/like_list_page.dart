import 'package:flutter/material.dart';
import '../../core/services/database_helper.dart';
import '../../core/models/scp_like_model.dart';
import '../detail/detail_page.dart';

/// 收藏列表页 — 支持长按多选批量取消收藏
class LikeListPage extends StatefulWidget {
  const LikeListPage({super.key});

  @override
  State<LikeListPage> createState() => _LikeListPageState();
}

class _LikeListPageState extends State<LikeListPage> {
  List<ScpLikeModel> _likes = [];
  bool _loading = true;
  bool _selectMode = false;
  final Set<String> _selectedLinks = {};

  @override
  void initState() {
    super.initState();
    _loadLikes();
  }

  Future<void> _loadLikes() async {
    try {
      final likes = await DatabaseHelper.getAllLikes();
      if (mounted) {
        setState(() {
          _likes = likes;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _batchUnlike() async {
    if (_selectedLinks.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量取消收藏'),
        content: Text('确定取消收藏选中的 ${_selectedLinks.length} 项？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    for (final link in _selectedLinks) {
      await DatabaseHelper.setLike(link, '', false);
    }
    setState(() { _selectMode = false; _selectedLinks.clear(); });
    _loadLikes();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_likes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '暂无收藏',
              style: TextStyle(color: Colors.grey.shade500),
            ),
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
            onPressed: _batchUnlike,
            icon: const Icon(Icons.favorite_border, size: 18),
            label: const Text('取消收藏'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
            onRefresh: _loadLikes,
            child: ListView.builder(
              itemCount: _likes.length,
              itemBuilder: (context, i) {
                final like = _likes[i];
                final selected = _selectedLinks.contains(like.link);
                return Dismissible(
                  key: Key(like.link),
                  direction: _selectMode ? DismissDirection.none : DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await DatabaseHelper.setLike(like.link, like.title, false);
                    _loadLikes();
                  },
                  child: ListTile(
                    selected: selected,
                    leading: _selectMode
                        ? Checkbox(
                            value: selected,
                            onChanged: (_) => _toggleSelect(like.link),
                          )
                        : CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            child: Icon(Icons.favorite, size: 18,
                                color: cs.onPrimaryContainer),
                          ),
                    title: Text(like.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: _selectMode ? null : const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      if (_selectMode) {
                        _toggleSelect(like.link);
                      } else {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => DetailPage(
                                    link: like.link, title: like.title)));
                      }
                    },
                    onLongPress: () {
                      if (!_selectMode) {
                        setState(() { _selectMode = true; _selectedLinks.add(like.link); });
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
}
