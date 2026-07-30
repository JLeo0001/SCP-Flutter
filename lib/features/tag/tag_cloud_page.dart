import 'package:flutter/material.dart';
import 'tag_detail_page.dart';

/// 标签云页面（手动输入标签名跳转）
class TagCloudPage extends StatefulWidget {
  const TagCloudPage({super.key});

  @override
  State<TagCloudPage> createState() => _TagCloudPageState();
}

class _TagCloudPageState extends State<TagCloudPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('标签搜索')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.label_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              '输入标签名称查看关联页面',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: '例如: keter、euclid、tale',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.search),
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TagDetailPage(tag: v.trim()),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                if (_controller.text.trim().isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TagDetailPage(tag: _controller.text.trim()),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.search, size: 18),
              label: const Text('搜索标签'),
            ),
          ],
        ),
      ),
    );
  }
}
