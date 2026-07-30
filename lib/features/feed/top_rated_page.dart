import 'package:flutter/material.dart';
import '../../core/backend/backend_service.dart';
import '../detail/detail_page.dart';

/// 分类最近更新页（替代原最高评分）
class TopRatedPage extends StatefulWidget {
  const TopRatedPage({super.key});

  @override
  State<TopRatedPage> createState() => _TopRatedPageState();
}

class _TopRatedPageState extends State<TopRatedPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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
        title: const Text('最高评分'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: '最高'),
            Tab(text: 'SCP'), Tab(text: '故事'), Tab(text: 'GOI格式'), Tab(text: '放逐者'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ListTab(prefix: 'all'),
          _ListTab(prefix: 'scp'),
          _ListTab(prefix: 'tale'),
          _ListTab(prefix: 'goiformat'),
          _ListTab(prefix: 'wanderers'),
        ],
      ),
    );
  }
}

class _ListTab extends StatefulWidget {
  final String prefix;
  const _ListTab({required this.prefix});

  @override
  State<_ListTab> createState() => _ListTabState();
}

class _ListTabState extends State<_ListTab> {
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
      final refs = await _backend.getTopRated(category: widget.prefix, limit: 30);
      if (mounted) setState(() {
        _items = refs.map((r) => _Item(r.title, r.link, r.rating?.toString() ?? '')).toList();
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
          Text('暂无数据', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, i) => ListTile(
          title: Text(_items[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: _items[i].rating.isNotEmpty
              ? Row(children: [const Icon(Icons.star, size: 14, color: Colors.amber), Text(' ${_items[i].rating}')])
              : null,
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
  final String rating;
  _Item(this.title, this.link, this.rating);
}
