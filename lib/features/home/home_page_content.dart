import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/backend/backend_service.dart';
import '../../core/models/feed_model.dart';
import '../feed/feed_page.dart';
import '../feed/top_rated_page.dart';
import '../tag/tag_cloud_page.dart';
import '../library/library_page.dart';
import '../story/story_settings_page.dart';
import '../category/group_list_page.dart';
import '../category/doc_list_page.dart';
import '../category/international_page.dart';
import 'widgets/feed_item.dart';

/// 首页内容
class HomePageContent extends StatefulWidget {
  const HomePageContent({super.key});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> {
  final _backend = BackendService.instance;
  List<FeedModel> _latestCreate = [];
  List<FeedModel> _latestTranslate = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFeedIndex();
  }

  Future<void> _loadFeedIndex() async {
    try {
      final results = await Future.wait([
        _backend.getLatestScp(limit: 10),
        _backend.getLatestTranslated(limit: 10),
      ]);
      if (mounted) {
        setState(() {
          _latestCreate = results[0]
              .map((p) => FeedModel(title: p.title, link: p.link))
              .toList();
          _latestTranslate = results[1]
              .map((p) => FeedModel(title: p.title, link: p.link))
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
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _loadFeedIndex,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          _sectionHeader('快速入口'),
          const SizedBox(height: 8),
          _buildGrid(cs),
          const SizedBox(height: 28),
          _sectionHeader('最新原创', onMore: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const FeedPage()))),
          const SizedBox(height: 8),
          ..._buildFeedCards(_latestCreate, cs),
          const SizedBox(height: 24),
          _sectionHeader('最新翻译', onMore: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const FeedPage()))),
          const SizedBox(height: 8),
          ..._buildFeedCards(_latestTranslate, cs),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const TopRatedPage())),
                  icon: const Icon(Icons.star, size: 18),
                  label: const Text('最高评分'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const TagCloudPage())),
                  icon: const Icon(Icons.label, size: 18),
                  label: const Text('标签'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(ColorScheme cs) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.1,
      ),
      itemCount: _entries.length,
      itemBuilder: (_, i) {
        final e = _entries[i];
        return Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () {
              Widget page;
              if (e.type == Entry.internationalDoc) {
                page = const InternationalPage();
              } else if (e.type == Entry.libraryDoc) {
                page = const LibraryPage();
              } else if (e.type == Entry.storyDoc) {
                page = const StorySettingsPage();
              } else if (e.direct) {
                page = DocListPage(saveType: e.type, title: e.label);
              } else {
                page = GroupListPage(entryType: e.type);
              }
              Navigator.push(context, MaterialPageRoute(builder: (_) => page));
            },
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/icons/${e.asset}.png',
                    width: 32, height: 32,
                    errorBuilder: (_, __, ___) => Icon(e.icon, size: 28, color: cs.primary),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  e.label,
                  style: TextStyle(fontSize: 13, color: cs.onSurface),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onMore}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        if (onMore != null) TextButton(onPressed: onMore, child: const Text('更多')),
      ],
    );
  }

  List<Widget> _buildFeedCards(List<FeedModel> items, ColorScheme cs) {
    if (_loading) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '暂无数据',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4)),
          ),
        ),
      ];
    }
    return items.map((f) => FeedItem(feed: f)).toList();
  }
}

class _GridEntry {
  final String label;
  final IconData icon;
  final int type;
  final bool direct;
  final String asset; // assets/icons/ 下的文件名，空字符串表示不使用
  const _GridEntry(this.label, this.icon, this.type, [this.direct = false, this.asset = '']);
}

const _entries = [
  _GridEntry('SCP系列', Icons.article_outlined, Entry.scpDoc, false, 'scp'),
  _GridEntry('SCP-CN系列', Icons.language, Entry.scpCnDoc, false, 'scp-cn'),
  _GridEntry('故事与设定', Icons.auto_stories_outlined, Entry.storyDoc),
  _GridEntry('放逐者图书馆', Icons.explore_outlined, Entry.wanderDoc, false, 'wanderers'),
  _GridEntry('图书馆', Icons.local_library_outlined, Entry.libraryDoc, true),
  _GridEntry('国际版', Icons.public_outlined, Entry.internationalDoc, true, 'international'),
];
