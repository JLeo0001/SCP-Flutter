import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/services/database_helper.dart';
import '../../core/services/offline_content_db.dart';
import '../detail/detail_page.dart';

/// 搜索页 — 支持离线 FTS5 全文搜索 + 标题搜索
class SearchPage extends StatefulWidget {
  final String initialKeyword;

  const SearchPage({super.key, this.initialKeyword = ''});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _searchController;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _isOfflineSearch = false;
  bool _useFts = false;

  Timer? _debounce;
  int _searchId = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialKeyword);
    _useFts = OfflineContentDb.isLoaded;
    if (widget.initialKeyword.isNotEmpty) {
      _search(widget.initialKeyword);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String keyword) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search(keyword);
    });
  }

  Future<void> _search(String keyword) async {
    if (keyword.isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }

    final id = ++_searchId;
    setState(() => _searching = true);

    // 优先 FTS5 全文搜索
    if (_useFts) {
      // fullTextSearch 内部已兜底，永不抛异常
      final results = await OfflineContentDb.fullTextSearch(keyword, limit: 50);
      if (!mounted || id != _searchId) return;
      if (results.isNotEmpty) {
        setState(() {
          _results = results;
          _isOfflineSearch = true;
          _searching = false;
        });
        return;
      }
      // 离线库搜不到 — 继续回退到 scp.db 标题搜索
    }

    // 后备：标题搜索
    try {
      final items = await DatabaseHelper.searchScpByTitle(keyword);
      if (!mounted || id != _searchId) return;
      setState(() {
        _results = items.take(50).map((s) => <String, dynamic>{
          'link': s.link,
          'title': s.title,
          'snippet': '',
          'scp_type': s.scpType,
          '_index': s.index,
        }).toList();
        _isOfflineSearch = false;
        _searching = false;
      });
    } catch (_) {
      if (mounted && id == _searchId) setState(() => _searching = false);
    }
  }

  IconData _typeIcon(int? scpType) {
    return switch (scpType) {
      1 || 2 => Icons.description,        // SCP
      7 || 8 => Icons.auto_stories,       // 故事
      9 || 10 => Icons.bookmark,          // 设定
      17 => Icons.groups,                 // GoI
      21 || 22 => Icons.explore,          // 漫游
      24 => Icons.info_outline,           // 信息页
      _ => Icons.article,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: _useFts ? '全文搜索SCP文档...' : '搜索SCP标题...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.4)),
          ),
          style: TextStyle(color: cs.onSurface),
          onChanged: _onSearchChanged,
        ),
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search, size: 64,
                          color: cs.onSurface.withValues(alpha: 0.15)),
                      const SizedBox(height: 16),
                      Text(
                        _useFts
                            ? '输入关键词搜索文档全文'
                            : '输入关键词搜索SCP标题\n(加载离线数据库后可搜索全文)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isOfflineSearch)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          '全文搜索 ${_results.length} 条结果',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final item = _results[i];
                          final link = item['link'] as String? ?? '';
                          final title = item['title'] as String? ?? '';
                          final snippet = item['snippet'] as String? ?? '';
                          final scpType = item['scp_type'] as int?;
                          final index = item['_index'] as int?;

                          return ListTile(
                            leading: Icon(
                              _typeIcon(scpType),
                              size: 20,
                              color: cs.primary.withValues(alpha: 0.6),
                            ),
                            title: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: snippet.isNotEmpty
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      _stripTags(snippet),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurface.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  )
                                : null,
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () {
                              final cleanLink = link.startsWith('/')
                                  ? link.substring(1)
                                  : link;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DetailPage(
                                    link: cleanLink,
                                    title: title,
                                    scpType: scpType,
                                    index: index,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  /// 移除 FTS5 snippet 中的 <b></b> 标记用于纯文本显示
  String _stripTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '');
  }
}
