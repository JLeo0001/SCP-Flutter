import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../category/group_list_page.dart';
import 'background_info_page.dart';

/// 故事与设定 — 二级分类页
class StorySettingsPage extends StatelessWidget {
  const StorySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('故事与设定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildCard(context, cs, '故事', Icons.auto_stories_outlined,
              '基金会故事 · CN原创故事 · 故事系列 · CN故事系列',
              [Category.tales, Category.talesCn, Category.storySeries, Category.storySeriesCn]),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.info_outline, color: cs.onPrimaryContainer, size: 22),
              ),
              title: const Text('背景资料', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              subtitle: Text('设定中心 · 关于基金会 · 相关组织 · 设施 · 特遣队 · 部门 ……',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const BackgroundInfoPage(),
                ));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, ColorScheme cs, String label,
      IconData icon, String subtitle, List<int> cats) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer, size: 22),
        ),
        title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => GroupListPage.storySub(entryType: Entry.storyDoc, categories: cats, title: label),
          ));
        },
      ),
    );
  }
}
