import 'package:flutter/material.dart';
import '../detail/detail_page.dart';

/// 图书馆 — 分类子菜单页
/// 所有分类条目均为 Wikidot 在线列表页
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('图书馆')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: _data.length,
        itemBuilder: (_, i) {
          final s = _data[i];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(s.icon, color: cs.onPrimaryContainer, size: 20),
              ),
              title: Text(s.label, style: const TextStyle(fontSize: 15)),
              subtitle: Text(
                'Wikidot 在线页面',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                final link = s.link.startsWith('/') ? s.link.substring(1) : s.link;
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => DetailPage(link: link, title: s.label),
                ));
              },
            ),
          );
        },
      ),
    );
  }
}

class _LibItem {
  final String label;
  final IconData icon;
  final String link;
  const _LibItem(this.label, this.icon, this.link);
}

const _data = <_LibItem>[
  _LibItem('用户推荐清单', Icons.thumb_up_outlined, '/user-curated-lists'),
  _LibItem('异常物品记录', Icons.inventory_2_outlined, '/log-of-anomalous-items'),
  _LibItem('超常现象记录', Icons.bolt_outlined, '/log-of-extranormal-events'),
  _LibItem('未解明地点记录', Icons.map_outlined, '/log-of-unexplained-locations'),
  _LibItem('GoI格式', Icons.groups_outlined, '/goi-formats'),
  _LibItem('音频记录', Icons.headphones_outlined, '/audio-adaptations'),
  _LibItem('艺术作品', Icons.palette_outlined, '/scp-artwork-hub'),
  _LibItem('征文竞赛', Icons.emoji_events_outlined, '/contest-archive'),
  _LibItem('CN异常物品记录', Icons.inventory_outlined, '/log-of-anomalous-items-cn'),
  _LibItem('CN超常现象记录', Icons.auto_awesome_outlined, '/log-of-extranormal-events-cn'),
  _LibItem('CN征文竞赛', Icons.emoji_events_outlined, '/contest-archive-cn'),
  _LibItem('被放逐者之图书馆', Icons.auto_stories_outlined, '/wanderers:start'),
  _LibItem('CN被放逐者之图书馆', Icons.explore_outlined, '/wanderers:the-library-cn'),
];
