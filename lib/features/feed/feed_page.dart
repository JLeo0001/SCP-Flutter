import 'package:flutter/material.dart';
import '../../core/backend/backend_service.dart';
import '../detail/detail_page.dart';

/// 最近更新页
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        title: const Text('最近更新'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: '最新原创'), Tab(text: '最新翻译')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_FeedTab(filter: 'scp'), _FeedTab(filter: 'translated')],
      ),
    );
  }
}

class _FeedTab extends StatefulWidget {
  final String filter;
  const _FeedTab({required this.filter});

  @override
  State<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<_FeedTab> {
  final _backend = BackendService.instance;
  List<_Item> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final refs = widget.filter == 'scp'
          ? await _backend.getLatestScp(limit: 30)
          : await _backend.getLatestTranslated(limit: 30);
      if (mounted) setState(() {
        _items = refs.map((r) => _Item(r.title, r.link)).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('无法获取更新列表', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, i) => ListTile(
          title: Text(_items[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => DetailPage(link: _items[i].link, title: _items[i].title))),
        ),
      ),
    );
  }
}

class _Item {
  final String title;
  final String link;
  _Item(this.title, this.link);
}
