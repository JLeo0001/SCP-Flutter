/// 阅读记录模型 - 对应 ScpRecordModel.kt
class ScpRecordModel {
  final String link;
  final String title;
  final int viewListType; // 0=history, 1=later
  final int viewTime; // timestamp

  ScpRecordModel({
    this.link = '',
    this.title = '',
    this.viewListType = -1,
    this.viewTime = 0,
  });

  String get showTime {
    final dt = DateTime.fromMillisecondsSinceEpoch(viewTime);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}/${dt.day}';
  }

  factory ScpRecordModel.fromMap(Map<String, dynamic> map) {
    return ScpRecordModel(
      link: (map['link'] ?? '') as String,
      title: (map['title'] ?? '') as String,
      viewListType: (map['viewListType'] ?? -1) as int,
      viewTime: (map['viewTime'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'link': link,
      'title': title,
      'viewListType': viewListType,
      'viewTime': viewTime,
    };
  }
}
