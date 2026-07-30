import 'package:flutter/material.dart';
import '../../core/services/wikidot_client.dart';
import '../../core/services/database_helper.dart';
import '../category/widgets/scp_list_item.dart';

/// 标签详情页 — 从 Wikidot + 本地数据库获取关联页面
class TagDetailPage extends StatefulWidget {
  final String tag;
  const TagDetailPage({super.key, required this.tag});

  @override
  State<TagDetailPage> createState() => _TagDetailPageState();
}

class _TagDetailPageState extends State<TagDetailPage> {
  bool _loading = true;
  List<ScpItemDisplay> _scps = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 1. 尝试从 Wikidot 按标签获取
      final pages = await WikidotClient.instance.getPagesByTag(widget.tag);
      if (pages.isNotEmpty) {
        if (mounted) {
          setState(() {
            _scps = pages
                .map((p) => ScpItemDisplay(
                    title: p.title, link: p.fullname, author: ''))
                .toList();
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}

    // 2. 回退：本地目录搜索
    try {
      final results = await DatabaseHelper.searchScpByTitle(widget.tag);
      if (mounted) {
        setState(() {
          _scps = results
              .map((e) => ScpItemDisplay(
                  title: e.title, link: e.link, author: e.author ?? ''))
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('标签: ${widget.tag}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _scps.isEmpty
              ? const Center(child: Text('暂无内容'))
              : ListView.builder(
                  itemCount: _scps.length,
                  itemBuilder: (context, i) => ScpListItem(
                      title: _scps[i].title,
                      link: _scps[i].link,
                      author: _scps[i].author)),
    );
  }
}

class ScpItemDisplay {
  final String title;
  final String link;
  final String author;
  ScpItemDisplay(
      {required this.title, required this.link, required this.author});
}
