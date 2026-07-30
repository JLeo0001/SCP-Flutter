/// 嵌入式后端数据模型

/// 页面内容
class PageData {
  final String link;
  final String title;
  final String content; // HTML
  final List<String> tags;
  final String html; // 原始HTML
  final DateTime fetchedAt;

  PageData({
    required this.link,
    required this.title,
    required this.content,
    required this.tags,
    required this.html,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();
}

/// 页面引用（列表用）
class PageRef {
  final String link;
  final String title;
  final double? rating;
  final String? category;
  final DateTime? lastUpdated;

  PageRef({
    required this.link,
    required this.title,
    this.rating,
    this.category,
    this.lastUpdated,
  });
}

/// 标签模型
class BackendTag {
  final String name;
  final int count;
  BackendTag({required this.name, required this.count});
}

/// 同步状态
class SyncStatus {
  final int pagesCached;
  final int tagsCollected;
  final int catalogEntries;
  final DateTime? lastSync;
  final List<String> activeJobs;

  SyncStatus({
    this.pagesCached = 0,
    this.tagsCollected = 0,
    this.catalogEntries = 0,
    this.lastSync,
    this.activeJobs = const [],
  });
}
