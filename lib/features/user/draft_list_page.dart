import 'package:flutter/material.dart';
import '../../core/services/database_helper.dart';
import '../../core/models/draft_model.dart';
import 'draft_edit_page.dart';

/// 草稿列表页 — 增强版
class DraftListPage extends StatefulWidget {
  const DraftListPage({super.key});

  @override
  State<DraftListPage> createState() => _DraftListPageState();
}

enum _SortMode { updatedDesc, updatedAsc, titleAsc, titleDesc }

class _DraftListPageState extends State<DraftListPage> {
  List<DraftModel> _drafts = [];
  List<DraftModel> _filtered = [];
  bool _loading = true;
  bool _searching = false;
  final _searchController = TextEditingController();
  _SortMode _sortMode = _SortMode.updatedDesc;
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDrafts() async {
    try {
      final drafts = await DatabaseHelper.getAllDrafts();
      if (mounted) {
        setState(() {
          _drafts = drafts;
          _filtered = _applySort(_applySearch(drafts));
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DraftModel> _applySearch(List<DraftModel> list) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((d) =>
      d.title.toLowerCase().contains(q) ||
      d.content.toLowerCase().contains(q)
    ).toList();
  }

  List<DraftModel> _applySort(List<DraftModel> list) {
    final sorted = List<DraftModel>.from(list);
    switch (_sortMode) {
      case _SortMode.updatedDesc:
        sorted.sort((a, b) => b.lastModifyTime.compareTo(a.lastModifyTime));
      case _SortMode.updatedAsc:
        sorted.sort((a, b) => a.lastModifyTime.compareTo(b.lastModifyTime));
      case _SortMode.titleAsc:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _SortMode.titleDesc:
        sorted.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
    }
    return sorted;
  }

  void _onSearch(String _) {
    setState(() {
      _filtered = _applySort(_applySearch(_drafts));
    });
  }

  void _deleteDraft(int draftId) {
    DatabaseHelper.deleteDraft(draftId);
    setState(() {
      _drafts.removeWhere((d) => d.draftId == draftId);
      _filtered = _applySort(_applySearch(_drafts));
    });
  }

  void _batchDelete() {
    if (_selectedIds.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除选中的 ${_selectedIds.length} 篇草稿？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              for (final id in _selectedIds) {
                await DatabaseHelper.deleteDraft(id);
              }
              if (mounted) {
                setState(() {
                  _selectMode = false;
                  _selectedIds.clear();
                });
                _loadDrafts();
              }
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('排序方式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            _sortOption(ctx, '最近修改', _SortMode.updatedDesc, Icons.access_time),
            _sortOption(ctx, '最早修改', _SortMode.updatedAsc, Icons.access_time),
            _sortOption(ctx, '标题 A-Z', _SortMode.titleAsc, Icons.sort_by_alpha),
            _sortOption(ctx, '标题 Z-A', _SortMode.titleDesc, Icons.sort_by_alpha),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sortOption(BuildContext ctx, String label, _SortMode mode, IconData icon) {
    final active = _sortMode == mode;
    return ListTile(
      leading: Icon(icon, color: active ? Theme.of(ctx).colorScheme.primary : null),
      title: Text(label, style: TextStyle(
        fontWeight: active ? FontWeight.w600 : null,
        color: active ? Theme.of(ctx).colorScheme.primary : null,
      )),
      trailing: active ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary) : null,
      onTap: () {
        setState(() => _sortMode = mode);
        _onSearch('');
        Navigator.pop(ctx);
      },
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索草稿…',
                  border: InputBorder.none,
                ),
                onChanged: _onSearch,
              )
            : Text(_selectMode ? '已选 ${_selectedIds.length} 项' : '草稿箱'),
        actions: [
          if (_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: '批量删除',
              onPressed: _batchDelete,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消选择',
              onPressed: () => setState(() {
                _selectMode = false;
                _selectedIds.clear();
              }),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: () => setState(() => _searching = !_searching),
            ),
            IconButton(
              icon: const Icon(Icons.sort),
              tooltip: '排序',
              onPressed: _showSortMenu,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新建草稿',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DraftEditPage(onSaved: _loadDrafts),
                  ),
                );
              },
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _searchController.text.isNotEmpty
                            ? Icons.search_off
                            : Icons.edit_note,
                        size: 56,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchController.text.isNotEmpty
                            ? '未找到匹配的草稿'
                            : '还没有草稿',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchController.text.isNotEmpty
                            ? '试试其他关键词'
                            : '点击右下角 + 新建一篇',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade400),
                      ),
                      if (_searchController.text.isEmpty) ...[
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    DraftEditPage(onSaved: _loadDrafts),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('新建草稿'),
                        ),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDrafts,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final draft = _filtered[i];
                      final selected = _selectedIds.contains(draft.draftId);
                      return Dismissible(
                        key: Key('draft_${draft.draftId}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          _deleteDraft(draft.draftId);
                          _snack('草稿已删除');
                        },
                        child: ListTile(
                          selected: selected,
                          leading: CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            child: Icon(
                              draft.content.isEmpty
                                  ? Icons.description_outlined
                                  : Icons.article_outlined,
                              size: 20,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            draft.title.isNotEmpty ? draft.title : '无标题',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: draft.title.isEmpty
                                  ? FontWeight.normal
                                  : FontWeight.w500,
                              color: draft.title.isEmpty
                                  ? cs.onSurface.withValues(alpha: 0.5)
                                  : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (draft.contentPreview.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    draft.contentPreview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              Row(
                                children: [
                                  Text(
                                    draft.relativeTime,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  if (draft.charCount > 0) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '${draft.charCount}字',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurface.withValues(alpha: 0.3),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_selectMode)
                                Checkbox(
                                  value: selected,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedIds.add(draft.draftId);
                                      } else {
                                        _selectedIds.remove(draft.draftId);
                                      }
                                      if (_selectedIds.isEmpty) {
                                        _selectMode = false;
                                      }
                                    });
                                  },
                                )
                              else
                                const Icon(Icons.chevron_right, size: 18),
                            ],
                          ),
                          onTap: () {
                            if (_selectMode) {
                              setState(() {
                                if (selected) {
                                  _selectedIds.remove(draft.draftId);
                                  if (_selectedIds.isEmpty) _selectMode = false;
                                } else {
                                  _selectedIds.add(draft.draftId);
                                }
                              });
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DraftEditPage(
                                    draft: draft,
                                    onSaved: _loadDrafts,
                                  ),
                                ),
                              );
                            }
                          },
                          onLongPress: () {
                            if (!_selectMode) {
                              setState(() {
                                _selectMode = true;
                                _selectedIds.add(draft.draftId);
                              });
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
