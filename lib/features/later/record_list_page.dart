import 'package:flutter/material.dart';
import '../../core/services/database_helper.dart';
import '../../core/models/scp_record_model.dart';
import '../../core/constants.dart';
import '../detail/detail_page.dart';

/// 记录列表页 — 支持长按多选批量删除
class RecordListPage extends StatefulWidget {
  final int viewListType;

  const RecordListPage({super.key, required this.viewListType});

  @override
  State<RecordListPage> createState() => _RecordListPageState();
}

class _RecordListPageState extends State<RecordListPage> {
  DateTime _lastLoad = DateTime(2000);
  List<ScpRecordModel> _records = [];
  bool _loading = true;
  bool _selectMode = false;
  final Set<String> _selectedLinks = {};

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    try {
      final records = await DatabaseHelper.getRecords(widget.viewListType);
      if (mounted) {
        setState(() {
          _records = records;
          _loading = false;
          _lastLoad = DateTime.now();
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _lastLoad = DateTime.now(); });
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

  Future<void> _batchDelete() async {
    if (_selectedLinks.isEmpty) return;
    final label = widget.viewListType == SCPConstants.laterType ? '待读' : '历史';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('批量删除'),
        content: Text('确定从$label列表中删除选中的 ${_selectedLinks.length} 项？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    for (final link in _selectedLinks) {
      await DatabaseHelper.removeRecord(link);
    }
    setState(() { _selectMode = false; _selectedLinks.clear(); });
    _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    // TabBarView不重建，切回时刷新
    if (DateTime.now().difference(_lastLoad).inSeconds > 2 && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadRecords());
    }
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.viewListType == SCPConstants.laterType
                  ? Icons.bookmark_border
                  : Icons.history,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              widget.viewListType == SCPConstants.laterType
                  ? '暂无待读内容'
                  : '暂无阅读记录',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    // 多选模式下的浮动操作栏
    final batchBar = _selectMode ? Container(
      color: cs.primaryContainer.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('已选 ${_selectedLinks.length} 项',
              style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface)),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedLinks.addAll(_records.map((r) => r.link));
              });
            },
            child: const Text('全选', style: TextStyle(fontSize: 13)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                final allLinks = _records.map((r) => r.link).toSet();
                _selectedLinks = allLinks.difference(_selectedLinks);
              });
            },
            child: const Text('反选', style: TextStyle(fontSize: 13)),
          ),
          TextButton.icon(
            onPressed: _batchDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除'),
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
            onRefresh: _loadRecords,
            child: ListView.builder(
              itemCount: _records.length,
              itemBuilder: (context, i) {
                final record = _records[i];
                final selected = _selectedLinks.contains(record.link);
                return Dismissible(
                  key: Key(record.link),
                  direction: _selectMode ? DismissDirection.none : DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await DatabaseHelper.removeRecord(record.link);
                    _loadRecords();
                  },
                  child: ListTile(
                    selected: selected,
                    leading: _selectMode
                        ? Checkbox(
                            value: selected,
                            onChanged: (_) => _toggleSelect(record.link),
                          )
                        : CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            child: Icon(
                              widget.viewListType == SCPConstants.laterType
                                  ? Icons.bookmark_outline
                                  : Icons.history,
                              size: 18,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                    title: Text(record.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(record.showTime,
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).disabledColor)),
                    trailing: _selectMode ? null : const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      if (_selectMode) {
                        _toggleSelect(record.link);
                      } else {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => DetailPage(
                                    link: record.link, title: record.title)));
                      }
                    },
                    onLongPress: () {
                      if (!_selectMode) {
                        setState(() {
                          _selectMode = true;
                          _selectedLinks.add(record.link);
                        });
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
