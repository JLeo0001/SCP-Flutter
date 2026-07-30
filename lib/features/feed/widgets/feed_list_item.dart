import 'package:flutter/material.dart';
import '../../../core/models/feed_model.dart';
import '../../detail/detail_page.dart';

/// Feed通用列表项 - 对应 FeedAdapter.kt
class FeedListItem extends StatelessWidget {
  final FeedModel feed;

  const FeedListItem({super.key, required this.feed});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text(feed.title,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: feed.createdTime.isNotEmpty
            ? Text(feed.createdTime,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).disabledColor))
            : null,
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      DetailPage(link: feed.link, title: feed.title)));
        },
      ),
    );
  }
}
