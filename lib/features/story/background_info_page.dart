import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../category/group_list_page.dart';
import '../category/doc_list_page.dart';
import '../detail/detail_page.dart';

/// 背景资料 — 二级分类页
class BackgroundInfoPage extends StatelessWidget {
  const BackgroundInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('背景资料')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── 本地数据库分类 ──
          _dbCard(context, cs, '设定中心', Icons.settings_outlined, '设定中心',
              [Category.settings]),
          _dbCard(context, cs, 'CN设定中心', Icons.settings_outlined, 'CN设定中心',
              [Category.settingsCn]),
          _dbCard2(context, cs, '背景资料', Icons.description_outlined,
              '信息页', ScpType.saveInfoPage),

          // ── Wikidot 参考页面 ──
          ..._wikidotPages.map((s) => _wikidotCard(context, cs, s)),
        ],
      ),
    );
  }

  Widget _dbCard(BuildContext context, ColorScheme cs, String label,
      IconData icon, String subtitle, List<int> cats) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer, size: 20),
        ),
        title: Text(label, style: const TextStyle(fontSize: 15)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => GroupListPage.storySub(
              entryType: Entry.storyDoc, categories: cats, title: label),
          ));
        },
      ),
    );
  }

  Widget _dbCard2(BuildContext context, ColorScheme cs, String label,
      IconData icon, String subtitle, int scpType) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer, size: 20),
        ),
        title: Text(label, style: const TextStyle(fontSize: 15)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => DocListPage(saveType: scpType, title: label),
          ));
        },
      ),
    );
  }

  Widget _wikidotCard(BuildContext context, ColorScheme cs, _WikidotRef s) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.tertiaryContainer,
          child: Icon(s.icon, color: cs.onTertiaryContainer, size: 20),
        ),
        title: Text(s.label, style: const TextStyle(fontSize: 15)),
        subtitle: Text('Wikidot 参考', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () {
          final link = s.link.startsWith('/') ? s.link.substring(1) : s.link;
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => DetailPage(link: link, title: s.label),
          ));
        },
      ),
    );
  }
}

class _WikidotRef {
  final String label;
  final IconData icon;
  final String link;
  const _WikidotRef(this.label, this.icon, this.link);
}

const _wikidotPages = <_WikidotRef>[
  _WikidotRef('关于基金会', Icons.info_outline, '/about-the-scp-foundation'),
  _WikidotRef('相关组织', Icons.groups_outlined, '/groups-of-interest'),
  _WikidotRef('项目等级', Icons.category_outlined, '/object-classes'),
  _WikidotRef('职员档案', Icons.person_outline, '/personnel-and-character-dossier'),
  _WikidotRef('安保许可等级', Icons.shield_outlined, '/security-clearance-levels'),
  _WikidotRef('安保设施', Icons.location_city_outlined, '/secure-facilities-locations'),
  _WikidotRef('机动特遣队', Icons.flash_on_outlined, '/task-forces'),
  _WikidotRef('基金会部门', Icons.business_outlined, '/departments'),
  _WikidotRef('中国相关组织', Icons.groups_outlined, '/groups-of-interest-cn'),
  _WikidotRef('中国分部设施', Icons.location_city_outlined, '/secure-facilities-locations-cn'),
  _WikidotRef('中国分部机动特遣队', Icons.flash_on_outlined, '/task-forces-cn'),
];
