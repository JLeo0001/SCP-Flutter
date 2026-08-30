import 'dart:convert';

/// 自由收藏条目 — 框选菜单保存的选段,每条独立成框
class FavoriteEntry {
  final String id;
  final String content;

  /// 来源文档标题(可为空)
  final String source;

  /// 来源文档链接(可为空)
  final String link;

  /// 收藏时间,毫秒时间戳
  final int createdAt;

  const FavoriteEntry({
    required this.id,
    required this.content,
    this.source = '',
    this.link = '',
    required this.createdAt,
  });

  FavoriteEntry copyWith({String? content}) => FavoriteEntry(
        id: id,
        content: content ?? this.content,
        source: source,
        link: link,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        if (source.isNotEmpty) 'source': source,
        if (link.isNotEmpty) 'link': link,
        'createdAt': createdAt,
      };

  factory FavoriteEntry.fromJson(Map<String, dynamic> j) => FavoriteEntry(
        id: (j['id'] ?? '') as String,
        content: (j['content'] ?? '') as String,
        source: (j['source'] ?? '') as String,
        link: (j['link'] ?? '') as String,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );

  /// 解析整段 JSON 列表;脏数据逐条跳过,坏 JSON 返回空
  static List<FavoriteEntry> listFromJsonString(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final v = jsonDecode(raw);
      if (v is! List) return const [];
      return [
        for (final item in v)
          if (item is Map<String, dynamic>) FavoriteEntry.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 列表序列化
  static String listToJsonString(List<FavoriteEntry> list) =>
      jsonEncode([for (final e in list) e.toJson()]);

  /// 预览文本:取首行,超 60 字截断
  String get preview {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';
    final firstLine = trimmed.split('\n').first.trim();
    if (firstLine.length <= 60) return firstLine;
    return '${firstLine.substring(0, 60)}…';
  }

  int get charCount => content.length;

  /// 相对时间文本(与草稿箱风格一致)
  String get timeLabel {
    final now = DateTime.now();
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}周前';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30}个月前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}
