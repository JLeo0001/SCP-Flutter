import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/services/backup_service.dart';

/// 数据备份与恢复页
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _prefs = true;
  bool _ai = true;
  bool _favorites = true;
  bool _likesRead = true;
  bool _records = true;
  bool _positions = true;
  bool _drafts = true;
  bool _merge = true;
  bool _busy = false;

  BackupOptions get _opts => BackupOptions(
        prefs: _prefs,
        ai: _ai,
        favorites: _favorites,
        likesRead: _likesRead,
        records: _records,
        positions: _positions,
        drafts: _drafts,
      );

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _ts() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${p(n.month)}${p(n.day)}_${p(n.hour)}${p(n.minute)}';
  }

  Future<void> _export() async {
    if (!_opts.any) {
      _snack('请至少选择一项备份内容');
      return;
    }
    setState(() => _busy = true);
    try {
      final json = await BackupService.export(_opts);
      final bytes = Uint8List.fromList(utf8.encode(json));
      final path = await FilePicker.platform.saveFile(
        fileName: 'SCP备份_${_ts()}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path == null) return; // 用户取消
      _snack('已导出备份文件');
    } catch (e) {
      _snack('导出失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;
    final BackupFile file;
    try {
      final f = BackupService.tryParse(utf8.decode(bytes));
      if (f == null) {
        _snack('不是有效的 SCP 阅读备份文件');
        return;
      }
      file = f;
    } catch (_) {
      _snack('文件读取失败');
      return;
    }
    if (!mounted) return;
    final cats = await _restoreSheet(file);
    if (cats == null || !cats.any) return;
    setState(() => _busy = true);
    try {
      final r = await BackupService.restore(file, cats: cats, merge: _merge);
      _snack(r.empty ? '没有可恢复的内容' : '恢复完成:${r.summary}');
    } catch (e) {
      _snack('恢复失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 恢复确认:勾选要恢复的类目(默认全选文件里有的),返回 null 表示取消
  Future<BackupOptions?> _restoreSheet(BackupFile file) {
    final sel = {
      'prefs': file.has('prefs'),
      'ai': file.has('aiSettings'),
      'favorites': file.has('favorites'),
      'likesRead': file.has('likes'),
      'records': file.has('records'),
      'positions': file.has('positions'),
      'drafts': file.has('drafts'),
    };
    String label(String key, String title) {
      final n = switch (key) {
        'prefs' => file.count('prefs'),
        'ai' => file.count('aiSettings'),
        'favorites' => file.count('favorites'),
        'likesRead' => file.count('likes'),
        'records' => file.count('records'),
        'positions' => file.count('positions'),
        _ => file.count('drafts'),
      };
      return '$title($n)';
    }

    return showModalBottomSheet<BackupOptions>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('从备份恢复',
                      style: Theme.of(ctx).textTheme.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    '备份时间:${DateTime.fromMillisecondsSinceEpoch(file.createdAt)}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
                ...sel.keys.map((k) => CheckboxListTile(
                      dense: true,
                      value: sel[k],
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(label(k, _catName(k))),
                      onChanged: (v) => setSheet(() => sel[k] = v ?? false),
                    )),
                SwitchListTile(
                  dense: true,
                  value: _merge,
                  title: const Text('合并现有数据'),
                  subtitle: const Text('关=替换:备份内容覆盖现有同类数据'),
                  onChanged: (v) => setSheet(() => _merge = v),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final none = sel.values.every((v) => !v);
                        Navigator.pop(
                          ctx,
                          none
                              ? null
                              : BackupOptions(
                                  prefs: sel['prefs']!,
                                  ai: sel['ai']!,
                                  favorites: sel['favorites']!,
                                  likesRead: sel['likesRead']!,
                                  records: sel['records']!,
                                  positions: sel['positions']!,
                                  drafts: sel['drafts']!,
                                ),
                        );
                      },
                      child: const Text('开始恢复'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _catName(String k) => switch (k) {
        'prefs' => '偏好与阅读设置',
        'ai' => 'AI 配置(含密钥)',
        'favorites' => '自由收藏',
        'likesRead' => '点赞与已读',
        'records' => '历史/待读列表',
        'positions' => '阅读位置',
        _ => '草稿',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('备份内容',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 4),
          Card(
            child: Column(children: [
              _check('偏好与阅读设置', _prefs, (v) => _prefs = v,
                  sub: '字体/主题/阅读设置/用户信息等'),
              _check('AI 配置(含供应商密钥)', _ai, (v) => _ai = v,
                  sub: '密钥明文存于备份文件,请妥善保管'),
              _check('自由收藏', _favorites, (v) => _favorites = v),
              _check('点赞与已读', _likesRead, (v) => _likesRead = v),
              _check('历史/待读列表', _records, (v) => _records = v),
              _check('阅读位置', _positions, (v) => _positions = v),
              _check('草稿', _drafts, (v) => _drafts = v),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Text(
              '离线文档缓存体积较大,不包含在备份内。',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('导出备份到文件'),
          ),
          const SizedBox(height: 24),
          Text('恢复',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 4),
          Card(
            child: SwitchListTile(
              value: _merge,
              title: const Text('恢复时合并现有数据'),
              subtitle: const Text('关=替换:备份内容覆盖现有同类数据'),
              onChanged: (v) => setState(() => _merge = v),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('从备份文件恢复'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _check(String title, bool value, ValueChanged<bool> onChanged,
      {String? sub}) {
    return CheckboxListTile(
      dense: true,
      value: value,
      onChanged: (v) => setState(() => onChanged(v ?? false)),
      title: Text(title, style: const TextStyle(fontSize: 14.5)),
      subtitle: sub == null
          ? null
          : Text(sub, style: const TextStyle(fontSize: 12)),
    );
  }
}
