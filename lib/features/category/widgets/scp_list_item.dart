import 'package:flutter/material.dart';
import '../../detail/detail_page.dart';

/// SCP列表项 - 对应 ScpAdapter.kt
class ScpListItem extends StatelessWidget {
  final String title;
  final String link;
  final String author;
  final String? subtitle;

  const ScpListItem({
    super.key,
    required this.title,
    required this.link,
    this.author = '',
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: author.isNotEmpty
          ? Text(
              author,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).disabledColor),
            )
          : null,
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => DetailPage(link: link, title: title)));
      },
    );
  }
}
