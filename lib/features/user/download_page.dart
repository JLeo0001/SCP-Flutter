import 'package:flutter/material.dart';
import '../../core/backend/backend_service.dart';
import '../../core/services/database_helper.dart';
import '../../core/services/category_map.dart' show typeNames;

/// 下载/数据管理页
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final _backend = BackendService.instance;
  bool _syncing = false;
  String _syncResult = '';
  int _totalEntries = 0;
  int _typeCount = 0;
  List<Map<String, dynamic>> _stats = [];
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final total = await DatabaseHelper.getTotalEntryCount();
      final types = await DatabaseHelper.getDistinctTypeCount();
      final stats = await DatabaseHelper.getCatalogStats();
      if (mounted) {
        setState(() {
          _totalEntries = total;
          _typeCount = types;
          _stats = stats;
          _loadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _syncCatalog() async {
    setState(() { _syncing = true; _syncResult = ''; });

    try {
      final added = await _backend.syncFullCatalog();
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncResult = added > 0
              ? '✅ 同步完成，新增 $added 条'
              : '✅ 已是最新，无需更新';
        });
        _loadStats(); // 同步后刷新统计
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncResult = '❌ 同步失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文档缓存/本地数据')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 目录更新 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.storage, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('SCP目录数据库',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    '从 Wikidot 官网同步最新 SCP 目录，更新标题和新增条目。\n'
                    '建议每隔一段时间手动更新一次。',
                    style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  if (_loadingStats)
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else ...[
                    Text(
                      '当前: $_totalEntries 条目 / $_typeCount 分类',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 4),
                    // 展开显示各分类计数
                    ..._stats.map((s) {
                      final typeId = s['scp_type'] as int;
                      final count = s['count'] as int;
                      final name = typeNames[typeId] ?? '类型$typeId';
                      return Text(
                        '  $name: $count',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400, height: 1.4),
                      );
                    }),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _syncing ? null : _syncCatalog,
                    icon: _syncing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync),
                    label: Text(_syncing ? '同步中...' : '手动更新目录'),
                  ),
                  if (_syncResult.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_syncResult, style: TextStyle(fontSize: 13, color: _syncResult.startsWith('✅') ? Colors.green : Colors.red)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 离线文档 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.download, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('离线文档',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    '离线文档后，无需联网即可加载文档内容，且支持全文搜索功能。\n\n'
                    '1. 点击左侧按钮选择线路下载数据库文件\n'
                    '2. 下载完成后，点击右侧按钮选择下载的数据库文件\n'
                    '3. APP会自动加载数据库文件\n\n'
                    '注：数据库文件总大小约超过500M',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('下载功能开发中')),
                            );
                          },
                          icon: const Icon(Icons.download),
                          label: const Text('下载数据库'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('文件选择功能开发中')),
                            );
                          },
                          icon: const Icon(Icons.folder_open),
                          label: const Text('选择文件'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 数据备份 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.backup, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('个性化数据备份',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    '备份收藏夹、历史记录、等级积分等数据',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.backup),
                          label: const Text('备份'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.restore),
                          label: const Text('恢复'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
