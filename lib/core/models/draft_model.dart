/// 草稿模型 - 对应 DraftModel.kt
class DraftModel {
  final int draftId;
  final int lastModifyTime;
  final String title;
  final String content;

  DraftModel({
    this.draftId = 0,
    this.lastModifyTime = 0,
    this.title = '',
    this.content = '',
  });

  /// 内容预览：取第一行或截断前 80 字
  String get contentPreview {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';
    // 取第一行
    final firstLine = trimmed.split('\n').first.trim();
    if (firstLine.length <= 80) return firstLine;
    return '${firstLine.substring(0, 80)}…';
  }

  /// 相对时间文本
  String get relativeTime {
    final now = DateTime.now();
    final dt = DateTime.fromMillisecondsSinceEpoch(lastModifyTime);
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}周前';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30}个月前';

    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  /// 完整时间戳
  String get lastTimeString {
    final dt = DateTime.fromMillisecondsSinceEpoch(lastModifyTime);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 字数
  int get charCount => content.length;
  int get titleLength => title.length;

  factory DraftModel.fromMap(Map<String, dynamic> map) {
    return DraftModel(
      draftId: (map['id'] ?? 0) as int,
      lastModifyTime: (map['updated_at'] ?? 0) as int,
      title: (map['title'] ?? '') as String,
      content: (map['content'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': draftId,
      'updated_at': lastModifyTime,
      'title': title,
      'content': content,
    };
  }
}
