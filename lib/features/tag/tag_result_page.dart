import 'package:flutter/material.dart';
import '../../core/services/wikidot_client.dart';
import '../category/widgets/scp_list_item.dart';

/// 标签结果页
class TagResultPage extends StatelessWidget {
  final String tag;
  const TagResultPage({super.key, required this.tag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('标签: $tag')),
      body: FutureBuilder(
        future: WikidotClient.instance.getPagesByTag(tag),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final scps = snapshot.data ?? [];
          if (scps.isEmpty) return const Center(child: Text('暂无内容'));
          return ListView.builder(
            itemCount: scps.length,
            itemBuilder: (context, i) {
              final scp = scps[i];
              return ScpListItem(
                title: scp.title,
                link: scp.link,
                author: '',
              );
            },
          );
        },
      ),
    );
  }
}
