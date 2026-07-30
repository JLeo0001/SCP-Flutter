import 'package:flutter/material.dart';
import '../../core/constants.dart';
import 'like_list_page.dart';
import 'record_list_page.dart';
import 'read_list_page.dart';

/// 待读页
class LaterPage extends StatefulWidget {
  final int initialTab;
  const LaterPage({super.key, this.initialTab = 0});

  @override
  State<LaterPage> createState() => _LaterPageState();
}

class _LaterPageState extends State<LaterPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('待读'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: '待读'),
            Tab(text: '历史'),
            Tab(text: '已读'),
            Tab(text: '收藏'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          RecordListPage(viewListType: SCPConstants.laterType),
          RecordListPage(viewListType: SCPConstants.historyType),
          const ReadListPage(),
          const LikeListPage(),
        ],
      ),
    );
  }
}
