/// 详情模型 - 对应 ScpDetail.kt
class ScpDetail {
  final String link;
  final String? detail;
  final int notFound;
  final String? tags;

  ScpDetail({
    required this.link,
    this.detail,
    this.notFound = -1,
    this.tags = '',
  });

  factory ScpDetail.fromMap(Map<String, dynamic> map) {
    return ScpDetail(
      link: map['link'] as String,
      detail: map['detail'] as String?,
      notFound: (map['not_found'] ?? -1) as int,
      tags: map['tags'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'link': link,
      'detail': detail,
      'not_found': notFound,
      'tags': tags,
    };
  }
}
