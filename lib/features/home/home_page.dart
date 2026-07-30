import 'package:flutter/material.dart';
import 'home_page_content.dart';
import '../search/search_page.dart';
import '../direct/direct_page.dart';
import '../random/random_page.dart';

/// 首页 — 搜索框占顶栏
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SearchPage()),
          ),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 8),
                Text(
                  '搜索SCP文章…',
                  style: TextStyle(
                    fontSize: 15,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tag),
            tooltip: '编号直达',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DirectPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.shuffle),
            tooltip: '随机',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RandomPage()),
            ),
          ),
        ],
      ),
      body: const HomePageContent(),
    );
  }
}
