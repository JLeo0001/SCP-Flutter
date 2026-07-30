import 'package:flutter/material.dart';
import '../../core/services/database_helper.dart';
import '../../core/models/scp_item_model.dart';
import 'widgets/scp_list_item.dart';

/// 分类页 - 对应 CategoryFragment.kt
class CategoryPage extends StatefulWidget {
  final int entryType;
  final String title;

  const CategoryPage({
    super.key,
    required this.entryType,
    this.title = '',
  });

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  List<ScpItemModel> _scpList = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final list = await DatabaseHelper.getScpListByType(widget.entryType);
      if (mounted) {
        setState(() {
          _scpList = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      itemCount: _scpList.length,
      itemBuilder: (context, i) {
        final item = _scpList[i];
        return ScpListItem(
          title: item.title,
          link: item.link,
          author: item.author ?? '',
        );
      },
    );
  }
}
