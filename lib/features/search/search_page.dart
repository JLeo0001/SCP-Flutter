import 'package:flutter/material.dart';
import '../../core/services/database_helper.dart';
import '../../core/models/scp_item_model.dart';
import '../detail/detail_page.dart';

/// 搜索页
class SearchPage extends StatefulWidget {
  final String initialKeyword;

  const SearchPage({super.key, this.initialKeyword = ''});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _searchController;
  List<ScpItemModel> _results = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialKeyword);
    if (widget.initialKeyword.isNotEmpty) {
      _search(widget.initialKeyword);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String keyword) async {
    if (keyword.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await DatabaseHelper.searchScpByTitle(keyword);
      if (mounted) {
        setState(() {
          _results = results;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索SCP标题...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white60),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: _search,
        ),
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? const Center(child: Text('输入关键词搜索SCP标题'))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final item = _results[i];
                    return ListTile(
                      title: Text(item.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: item.author != null && item.author!.isNotEmpty
                          ? Text(item.author!)
                          : null,
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => DetailPage(
                                    link: item.link, title: item.title)));
                      },
                    );
                  },
                ),
    );
  }
}
