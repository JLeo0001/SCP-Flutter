import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/services/category_map.dart';
import 'doc_list_page.dart';

/// 入口类型 → 自定义图标资产
const _entryIcons = <int, String>{
  Entry.scpDoc: 'scp',
  Entry.scpCnDoc: 'scp-cn',
  Entry.wanderDoc: 'wanderers',
};

/// 分类组页 — 数据驱动，无硬编码
class GroupListPage extends StatelessWidget {
  final int entryType;
  final List<int>? _categories;
  final String? _title;

  const GroupListPage({super.key, required this.entryType})
      : _categories = null, _title = null;

  const GroupListPage.storySub({super.key, required this.entryType, required List<int> categories, required String title})
      : _categories = categories, _title = title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = _title ?? entryNames[entryType] ?? '';
    final cats = _categories ?? entryCategories[entryType] ?? [];
    final assetIcon = _entryIcons[entryType];
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: cats.length,
        itemBuilder: (_, i) {
          final cat = cats[i];
          final name = categoryNames[cat] ?? '其他';
          final icon = categoryIcons[cat] ?? Icons.folder_outlined;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: cs.primaryContainer,
                backgroundImage: assetIcon != null
                    ? AssetImage('assets/icons/$assetIcon.png')
                    : null,
                child: assetIcon == null
                    ? Icon(icon, color: cs.onPrimaryContainer, size: 20)
                    : null,
              ),
              title: Text(name),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                final saveType = resolveSaveType(entryType, cat);
                if (saveType != null) {
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => DocListPage(saveType: saveType, title: name)));
                }
              },
            ),
          );
        },
      ),
    );
  }
}
