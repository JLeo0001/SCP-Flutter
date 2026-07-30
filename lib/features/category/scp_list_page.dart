import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/services/database_helper.dart';
import '../../core/models/scp_item_model.dart';
import 'widgets/scp_list_item.dart';

/// SCP列表页 - 对应 ScpListFragment.kt
class ScpListPage extends StatefulWidget {
  final int saveType;
  final int groupIndex;
  final String extraType;
  final String title;

  const ScpListPage({
    super.key,
    required this.saveType,
    this.groupIndex = -1,
    this.extraType = '',
    this.title = '',
  });

  @override
  State<ScpListPage> createState() => _ScpListPageState();
}

class _ScpListPageState extends State<ScpListPage> {
  List<ScpItemModel> _scpList = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final list = await DatabaseHelper.getScpListByType(widget.saveType);
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

  void reverseList(int orderType) {
    setState(() {
      _scpList = orderType == OrderType.asc
          ? _scpList
          : _scpList.reversed.toList();
    });
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
