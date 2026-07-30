import 'package:flutter/material.dart';
import '../../core/services/database_helper.dart';
import '../../core/models/scp_item_model.dart';
import 'doc_list_page.dart';

/// 国家代码 → 图标文件映射
const _countryIconMap = <String, String>{
  '俄国分部': 'ru',
  '韩国分部': 'ko',
  '法国分部': 'fr',
  '波兰分部': 'pl',
  '西班牙分部': 'es',
  '泰国分部': 'th',
  '日本分部': 'ja',
  '意大利分部': 'it',
  '乌克兰分部': 'uk',
  '德国分部': 'de',
  '葡萄牙语分部': 'pt',
  '捷克分部': 'cs',
  '越南分部': 'vi',
};

/// 国际版国家列表 — 先选国家再浏览条目
class InternationalPage extends StatefulWidget {
  const InternationalPage({super.key});

  @override
  State<InternationalPage> createState() => _InternationalPageState();
}

class _InternationalPageState extends State<InternationalPage> {
  final List<_CountryGroup> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await DatabaseHelper.getInternationalByCountry('%');
      final countries = <String, List<_SubCategory>>{};
      for (final item in all) {
        final subType = item.subScpType ?? '';
        if (subType.isEmpty) continue;
        // "日本分部-series" → 国家="日本分部", 子类="series"
        final parts = subType.split('-');
        if (parts.length < 2) continue;
        final country = parts[0]; // "日本分部"
        final category = parts.sublist(1).join('-'); // "series"
        countries.putIfAbsent(country, () => []);
        countries[country]!.add(_SubCategory(category, item));
      }

      // 转为排序列表：每个国家一个 group，合并计数
      _groups.clear();
      for (final entry in countries.entries) {
        final cats = entry.value;
        final total = cats.length;
        final displayName = entry.key; // "日本分部" 保持原样
        _groups.add(_CountryGroup(
          rawName: entry.key,
          displayName: displayName,
          total: total,
          subCategories: cats,
        ));
      }
      _groups.sort((a, b) => b.total.compareTo(a.total));

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SCP国际版')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? const Center(child: Text('暂无数据'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _groups.length,
                  itemBuilder: (_, i) => _buildCountryCard(_groups[i]),
                ),
    );
  }

  Widget _buildCountryCard(_CountryGroup group) {
    final cs = Theme.of(context).colorScheme;
    final iconFile = _countryIconMap[group.rawName];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DocListPage(
              saveType: 23,
              title: group.displayName,
              extraType: group.rawName,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: cs.primaryContainer,
                backgroundImage: iconFile != null
                    ? AssetImage('assets/icons/$iconFile.png')
                    : null,
                child: iconFile == null
                    ? Text(
                        group.displayName.isNotEmpty ? group.displayName[0] : '?',
                        style: TextStyle(color: cs.onPrimaryContainer),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.displayName,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('${group.total} 个页面',
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountryGroup {
  final String rawName;
  final String displayName;
  final int total;
  final List<_SubCategory> subCategories;
  _CountryGroup({
    required this.rawName,
    required this.displayName,
    required this.total,
    required this.subCategories,
  });
}

class _SubCategory {
  final String category;
  final ScpItemModel item;
  _SubCategory(this.category, this.item);
}
