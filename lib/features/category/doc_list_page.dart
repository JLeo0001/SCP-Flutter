import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/services/category_map.dart';
import '../../core/services/database_helper.dart';
import '../../core/services/wikidot_client.dart';
import '../../core/models/scp_item_model.dart';
import 'widgets/scp_list_item.dart';

/// 文档列表页 - 对应 DocListActivity.kt
/// 从本地数据库或 Wikidot 获取 SCP 条目列表
class DocListPage extends StatefulWidget {
  final int saveType;
  final int groupIndex;
  final String extraType;
  final String title;

  const DocListPage({
    super.key,
    required this.saveType,
    this.groupIndex = -1,
    this.extraType = '',
    this.title = '列表',
  });

  @override
  State<DocListPage> createState() => _DocListPageState();
}

class _DocListPageState extends State<DocListPage> {
  List<_DocItem> _items = [];
  List<_DocItem> _allItems = []; // 完整列表（筛选前）
  bool _loading = true;
  String? _error;
  int _seriesFilter = -1; // -1=全部, 0=I, 1=II, ...

  static const _seriesLabels = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];

  String get _seriesLabel => _seriesFilter >= 0 && _seriesFilter < _seriesLabels.length
      ? _seriesLabels[_seriesFilter] : '';

  List<int> get _seriesRanges {
    if (widget.saveType == ScpType.saveSeriesCn) return [1, 1000, 2000, 3000, 4000, 5000];
    return [1, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000];
  }

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  Future<void> _loadList() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await _fetchDocList();
      if (mounted) {
        setState(() {
          _allItems = items;
          _applySeriesFilter();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<List<_DocItem>> _fetchDocList() async {
    // ── 1. 从本地数据库获取 ──
    try {
      final dbItems = await _getFromDb();
      if (dbItems.isNotEmpty) return dbItems;
    } catch (_) {}

    // ── 2. 从 Wikidot 官网搜索 ──
    try {
      return await _getFromWikidot();
    } catch (_) {}

    throw Exception('暂无数据');
  }

  Future<List<_DocItem>> _getFromDb() async {
    List<ScpItemModel> all;

    switch (widget.saveType) {
      // ── SCP系列 / 搞笑 / 已解明 ──
      case ScpType.saveSeries:
      case ScpType.saveSeriesCn:
      case ScpType.saveJoke:
      case ScpType.saveJokeCn:
      case ScpType.saveEx:
      case ScpType.saveExCn:
        all = await DatabaseHelper.getScpListByType(widget.saveType);
        break;

      // ── 故事 / 放逐者 ──
      case ScpType.saveTales:
      case ScpType.saveTalesCn:
      case ScpType.saveTalesByTime:
      case ScpType.saveWander:
      case ScpType.saveWanderCn:
        if (widget.extraType.isNotEmpty) {
          all = await DatabaseHelper.getScpListByTypeAndExtra(
              widget.saveType, widget.extraType);
        } else {
          all = await DatabaseHelper.getScpListByType(widget.saveType);
        }
        break;

      // ── 设定 / 故事系列 / 征文 ──
      case ScpType.saveCanon:
      case ScpType.saveCanonCn:
      case ScpType.saveStorySeries:
      case ScpType.saveStorySeriesCn:
      case ScpType.saveContest:
      case ScpType.saveContestCn:
        all = await DatabaseHelper.getScpListByType(widget.saveType);
        break;

      // ── 国际版 ──
      case Entry.internationalDoc:
      case ScpType.saveInternational:
        if (widget.extraType.isNotEmpty) {
          all = await DatabaseHelper.getInternationalByCountry('${widget.extraType}-%');
        } else {
          all = await DatabaseHelper.getInternationalByCountry('%');
        }
        break;

      // ── GOI格式 ──
      case Entry.goiDoc:
        all = await DatabaseHelper.getScpListByType(ScpType.saveGoi);
        break;

      // ── 艺术作品 ──
      case Entry.artDoc:
        all = await DatabaseHelper.getScpListByType(ScpType.saveArt);
        break;

      // ── 背景资料 ──
      case Entry.informationDoc:
        all = await DatabaseHelper.getScpListByType(ScpType.saveInfoPage);
        break;

      default:
        all = await DatabaseHelper.getScpListByType(widget.saveType);
    }

    // 按 groupIndex 分页（每组 100 条）
    if (widget.groupIndex >= 0 && all.isNotEmpty) {
      const pageSize = 100;
      final start = widget.groupIndex * pageSize;
      if (start < all.length) {
        final end = (start + pageSize < all.length) ? start + pageSize : all.length;
        all = all.sublist(start, end);
      } else {
        all = [];
      }
    }

    return all.map((s) {
      final cleanLink = s.link.startsWith('/') ? s.link.substring(1) : s.link;
      return _DocItem(title: s.title, link: cleanLink, author: s.author ?? '', scpIndex: s.index);
    }).toList();
  }

  /// 应用系列筛选
  void _applySeriesFilter() {
    if (_seriesFilter < 0 || _allItems.isEmpty) {
      _items = List.from(_allItems);
      return;
    }
    final ranges = _seriesRanges;
    if (_seriesFilter >= ranges.length - 1) {
      _items = List.from(_allItems);
      return;
    }
    final minIdx = ranges[_seriesFilter];
    final maxIdx = ranges[_seriesFilter + 1];
    _items = _allItems.where((item) => item.scpIndex >= minIdx && item.scpIndex < maxIdx).toList();
  }

  void _showSeriesFilter() {
    final isCn = widget.saveType == ScpType.saveSeriesCn;
    final maxSeries = isCn ? 5 : 10;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('选择系列', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Wrap(
                spacing: 8, runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('全部', style: TextStyle(fontSize: 13)),
                    selected: _seriesFilter < 0,
                    onSelected: (_) { setState(() { _seriesFilter = -1; _applySeriesFilter(); }); Navigator.pop(ctx); },
                  ),
                  ...List.generate(maxSeries, (i) => ChoiceChip(
                    label: Text(_seriesLabels[i], style: const TextStyle(fontSize: 13)),
                    selected: _seriesFilter == i,
                    onSelected: (_) { setState(() { _seriesFilter = i; _applySeriesFilter(); }); Navigator.pop(ctx); },
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<_DocItem>> _getFromWikidot() async {
    final wd = WikidotClient.instance;
    final results = await wd.getRecentChanges(limit: 50);
    return results.map((r) => _DocItem(title: r.title, link: r.fullname)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isScpSeries = widget.saveType == ScpType.saveSeries || widget.saveType == ScpType.saveSeriesCn;
    return Scaffold(
      appBar: AppBar(
        title: Text(_seriesFilter >= 0 ? '$_title · ${_seriesLabel}' : _title),
        actions: [
          if (isScpSeries)
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: '系列筛选',
              onPressed: _showSeriesFilter,
            ),
          IconButton(
            icon: const Icon(Icons.swap_vert),
            tooltip: '逆序',
            onPressed: () => setState(() => _items = _items.reversed.toList()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadList, child: const Text('重试')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text('暂无数据', style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadList,
                      child: ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final item = _items[i];
                          return ScpListItem(
                            title: item.title,
                            link: item.link,
                            author: item.author,
                          );
                        },
                      ),
                    ),
    );
  }

  String get _title {
    if (widget.title != '列表') return widget.title;
    return typeNames[widget.saveType] ?? widget.title;
  }
}

class _DocItem {
  final String title;
  final String link;
  final String author;
  final int scpIndex;
  _DocItem({required this.title, required this.link, this.author = '', this.scpIndex = 0});
}
