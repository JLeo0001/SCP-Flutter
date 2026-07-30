import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/backend/backend_service.dart';
import '../../core/services/database_helper.dart';
import '../../core/services/offline_content_db.dart';
import '../../core/services/preference_service.dart';
import '../../core/services/category_map.dart' show typeNames;

/// 下载/数据管理页 — 离线内容库管理
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

  bool _offlineLoaded = false;
  int? _offlinePages;
  int? _offlineSize;
  String _offlineMsg = '';
  double _downloadProgress = 0;
  bool _isDownloading = false;

  String get _releaseUrl =>
      'https://github.com/JLeo0001/SCP-Flutter/releases/latest/download/offline_content.db';

  @override
  void initState() {
    super.initState();
    _loadStats();
    _checkOffline();
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

  Future<void> _checkOffline() async {
    final loaded = OfflineContentDb.isLoaded;
    final pages = OfflineContentDb.totalPages;
    final size = await OfflineContentDb.dbFileSize;
    if (mounted) {
      setState(() {
        _offlineLoaded = loaded;
        _offlinePages = pages;
        _offlineSize = size;
      });
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
        _loadStats();
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

  Future<void> _downloadOfflineDb() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载离线数据库'),
        content: const Text(
          '将从 GitHub Releases 下载预构建的离线文档数据库。\n\n'
          '文件大小: ~1GB（含所有SCP条目、故事的完整内容）\n'
          '下载后可在无网络环境下阅读和全文搜索。\n\n'
          '继续下载？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开始下载')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _offlineMsg = '准备下载...';
    });

    final useProxy = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载线路选择'),
        content: const Text('直连较慢时可尝试代理加速'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('直连')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('使用代理')),
        ],
      ),
    );

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final destPath = '${docDir.path}/offline_content.db';

      String url = _releaseUrl;
      if (useProxy == true) {
        url = 'https://ghproxy.homeboyc.cn/$_releaseUrl';
      }

      final path = await OfflineContentDb.download(
        url: url,
        destPath: destPath,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = total > 0 ? received / total : 0;
              _offlineMsg = '下载中 ${_formatSize(received)} / ${_formatSize(total)}';
            });
          }
        },
      );

      if (path != null && mounted) {
        final size = await OfflineContentDb.dbFileSize;
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _offlineMsg = '✅ 下载并加载成功！';
            _offlineLoaded = true;
            _offlinePages = OfflineContentDb.totalPages;
            _offlineSize = size;
          });
        }
      } else if (mounted) {
        setState(() {
          _isDownloading = false;
          _offlineMsg = '❌ 下载失败，请重试或尝试其他线路';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _offlineMsg = '❌ 下载失败: $e';
        });
      }
    }
  }

  Future<void> _importOfflineDb() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: '选择 offline_content.db 离线数据库',
      );

      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.single.path;
      if (filePath == null || !await File(filePath).exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法读取所选文件')),
          );
        }
        return;
      }

      setState(() => _offlineMsg = '正在导入...');

      final docDir = await getApplicationDocumentsDirectory();
      final destPath = '${docDir.path}/offline_content.db';

      final destFile = File(destPath);
      if (await destFile.exists()) {
        await destFile.delete();
      }
      await File(filePath).copy(destPath);

      final loaded = await _backend.loadOfflineDb(destPath);
      if (loaded && mounted) {
        final size = await OfflineContentDb.dbFileSize;
        if (mounted) {
          setState(() {
            _offlineLoaded = true;
            _offlinePages = OfflineContentDb.totalPages;
            _offlineSize = size;
            _offlineMsg = '✅ 已加载: $filePath';
          });
        }
      } else if (mounted) {
        setState(() => _offlineMsg = '❌ 文件格式不正确');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _offlineMsg = '❌ 导入失败: $e');
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('文档缓存/离线数据库')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ═══ 离线内容库 ═══
          Card(
            color: _offlineLoaded ? cs.primaryContainer.withValues(alpha: 0.3) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(_offlineLoaded ? Icons.cloud_done : Icons.cloud_download,
                        size: 20, color: _offlineLoaded ? Colors.green : cs.primary),
                    const SizedBox(width: 8),
                    Text('离线文档数据库',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                            color: _offlineLoaded ? Colors.green.shade700 : null)),
                    if (_offlineLoaded)
                      Container(margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                        child: Text('已加载', style: TextStyle(fontSize: 10, color: Colors.green.shade800))),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    '离线数据库包含所有SCP条目、故事的完整HTML内容，\n'
                    'gzip压缩存储，支持 FTS5 全文搜索。\n'
                    '加载后阅读和搜索完全无需网络。',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  if (_offlineLoaded) ...[
                    const SizedBox(height: 12),
                    Text('页面总数: $_offlinePages 页', style: const TextStyle(fontSize: 12)),
                    if (_offlineSize != null)
                      Text('文件大小: ${_formatSize(_offlineSize!)}', style: const TextStyle(fontSize: 12)),
                    if (OfflineContentDb.typeCounts != null)
                      ...OfflineContentDb.typeCounts!.entries.map((e) =>
                        Text('  ${typeNames[e.key] ?? "类型${e.key}"}: ${e.value} 页',
                            style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)))),
                  ],
                  const SizedBox(height: 16),
                  // ═══ 优先离线开关 ═══
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('联网时优先使用离线数据', style: TextStyle(fontSize: 14)),
                    subtitle: Text('开启后阅读文档优先加载离线内容，省流量加速',
                        style: TextStyle(fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.5))),
                    value: PreferenceService.getPreferOffline(),
                    onChanged: (v) {
                      PreferenceService.setPreferOffline(v);
                      setState(() {});
                    },
                  ),
                  if (_isDownloading)
                    Column(children: [
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 8),
                      Text(_offlineMsg, style: const TextStyle(fontSize: 13)),
                    ])
                  else ...[
                    Row(children: [
                      Expanded(child: FilledButton.icon(
                        onPressed: _downloadOfflineDb,
                        icon: const Icon(Icons.download, size: 18),
                        label: Text(_offlineLoaded ? '更新离线库' : '下载离线库'),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: OutlinedButton.icon(
                        onPressed: _importOfflineDb,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('选择文件'),
                      )),
                    ]),
                    if (_offlineMsg.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_offlineMsg, style: TextStyle(fontSize: 12,
                          color: _offlineMsg.startsWith('✅') ? Colors.green
                              : _offlineMsg.startsWith('❌') ? Colors.red : cs.onSurface)),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ═══ 目录更新 ═══
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.storage, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                const Text('SCP目录数据库', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              const Text('从 Wikidot 官网同步最新 SCP 目录。',
                  style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4)),
              const SizedBox(height: 6),
              if (_loadingStats)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
              else ...[
                Text('当前: $_totalEntries 条目 / $_typeCount 分类',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                ..._stats.map((s) => Text('  ${typeNames[s["scp_type"] as int] ?? "类型${s["scp_type"]}"}: ${s["count"]}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400, height: 1.4))),
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
                Text(_syncResult, style: TextStyle(fontSize: 13,
                    color: _syncResult.startsWith('✅') ? Colors.green : Colors.red)),
              ],
            ],
          ))),
          const SizedBox(height: 16),

          // ═══ 数据备份 ═══
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.backup, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                const Text('个性化数据备份', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              const Text('备份收藏夹、历史记录、阅读位置等数据', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: null,
                    icon: const Icon(Icons.backup), label: const Text('备份'))),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton.icon(onPressed: null,
                    icon: const Icon(Icons.restore), label: const Text('恢复'))),
              ]),
            ],
          ))),
        ],
      ),
    );
  }
}
