import 'package:flutter/material.dart';
import '../../core/services/preference_service.dart';

/// 设置页 - 对应 SettingsActivity.kt
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _hideFinished = false;

  @override
  void initState() {
    super.initState();
    _hideFinished = PreferenceService.getHideFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('隐藏已读文档'),
            subtitle: const Text('在列表中隐藏已标记为已读的文档'),
            value: _hideFinished,
            onChanged: (v) {
              setState(() => _hideFinished = v);
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('字体大小'),
            subtitle: Text(
                '当前: ${PreferenceService.getDetailTextSize()}'),
            onTap: () {
              // 字体大小设置
            },
          ),
          ListTile(
            title: const Text('简体/繁体'),
            subtitle: Text(
              PreferenceService.getHanzType() == 0 ? '简体' : '繁体',
            ),
            onTap: () {
              final newType =
                  PreferenceService.getHanzType() == 0 ? 1 : 0;
              PreferenceService.setHanzType(newType);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
