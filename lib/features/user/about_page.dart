import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 关于页
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    } catch (_) {
      if (mounted) setState(() => _version = '1.0.0');
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          // App图标 + 名称 + 版本
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icons/scp.png',
                    width: 80, height: 80,
                    errorBuilder: (_, __, ___) => Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.security, size: 40, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('SCP基金会',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('v$_version', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // 说明
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'SCP基金会中分网站的移动端阅读工具，所有内容来自SCP基金会中国分部网站并遵守CC-BY-SA 3.0协议。',
                style: TextStyle(fontSize: 14, height: 1.6, color: cs.onSurface),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 链接
          _buildLink(context, cs, 'SCP中分官网', Icons.language, () => _openUrl('http://scp-wiki-cn.wikidot.com')),
          _buildLink(context, cs, '用户交流群', Icons.chat, () => _openUrl('https://qun.qq.com/universal-share/share?ac=1&authKey=oD%2F4cCEEogldzUpFsUyZ9RQ3MvwaPbVutVybB6Gy9G30C3voy%2FCtMRrPVBNCWRF%2F&busi_data=eyJncm91cENvZGUiOiI2ODgwNTcyODAiLCJ0b2tlbiI6Ik5SWFI0TWtSdzNTUW10d2RHNjJEcTZzVGEyWFgwenNyTDF4VnF5eUlvLzAwdkFETVdzWmdHaW5YcTl3cng4WmgiLCJ1aW4iOiIxNzA2NjgwODY1In0%3D&data=_QmzJvTQ0yGLonooNICz_Yn258EndIbaveL_V40VS7orJa0cI_bvS3qOMbq6sny95bGsS7yNTwKhOoXNw9oSjw&svctype=4&tempid=h5_group_info')),
          _buildLink(context, cs, '开源仓库', Icons.code, () => _openUrl('https://github.com/JLeo0001/SCP-Flutter')),
          const Divider(height: 24),
          // 致谢
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('致谢', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.6))),
          ),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openUrl('https://github.com/zhufree/SCP-Android'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.auto_stories, size: 20, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('zhufree/SCP-Android', style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface)),
                          const SizedBox(height: 2),
                          Text('感谢原Android版作者的贡献与启发',
                              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: cs.onSurface.withValues(alpha: 0.3)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 版权
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('版权说明',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
                  const SizedBox(height: 8),
                  Text(
                    'APP内容来源自SCP基金会：http://scp-wiki-cn.wikidot.com/\n\n'
                    '除非特别注明，文章内容采用CC-BY-SA 3.0协议\n'
                    'https://creativecommons.org/licenses/by-sa/3.0/deed.zh\n\n'
                    '欲了解更多信息，查看授权指南：\n'
                    '简繁转换词典基于OpenCC（Apache-2.0）\\n'
                    'https://github.com/BYVoid/OpenCC\\n\\n'
                    'http://scp-wiki-cn.wikidot.com/licensing-guide',
                    style: TextStyle(fontSize: 13, height: 1.5, color: cs.onSurface.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLink(BuildContext context, ColorScheme cs, String title, IconData icon, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: Icon(icon, size: 20, color: cs.primary),
        title: Text(title, style: TextStyle(fontSize: 15, color: cs.onSurface)),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
