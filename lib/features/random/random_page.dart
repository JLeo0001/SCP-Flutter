import 'package:flutter/material.dart';
import '../../core/services/database_helper.dart';
import '../detail/detail_page.dart';

/// 随机SCP页 — 从本地数据库随机选一篇
class RandomPage extends StatefulWidget {
  const RandomPage({super.key});

  @override
  State<RandomPage> createState() => _RandomPageState();
}

class _RandomPageState extends State<RandomPage> {
  bool _loading = true;
  String _title = '';
  String _link = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _title = ''; _link = ''; });
    try {
      final results = await DatabaseHelper.getRandomScp(count: 1);
      if (results.isNotEmpty && mounted) {
        setState(() {
          _title = results.first.title;
          _link = results.first.link;
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('随机SCP'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle),
            onPressed: _loading ? null : _fetch,
            tooltip: '再来一篇',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_loading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                const Text('随机挑选中...',
                    style: TextStyle(color: Colors.grey)),
              ] else if (_title.isNotEmpty) ...[
                const Icon(Icons.auto_awesome,
                    size: 48, color: Colors.amber),
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    title: Text(_title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => DetailPage(
                                link: _link, title: _title))),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _fetch,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('换一篇'),
                ),
              ] else ...[
                const Icon(Icons.error_outline,
                    size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('暂无数据'),
                const SizedBox(height: 16),
                ElevatedButton(
                    onPressed: _fetch, child: const Text('重试')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
