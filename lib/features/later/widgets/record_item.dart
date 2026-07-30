import 'package:flutter/material.dart';
import '../../../core/models/scp_record_model.dart';
import '../../detail/detail_page.dart';

/// 记录项 widget
class RecordItem extends StatelessWidget {
  final ScpRecordModel record;

  const RecordItem({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(record.title,
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(record.showTime,
          style: TextStyle(
              fontSize: 12, color: Theme.of(context).disabledColor)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    DetailPage(link: record.link, title: record.title)));
      },
    );
  }
}
