/// Feed模型 - 对应 FeedModel.kt
class FeedModel {
  final String title;
  final String link;
  final String createdTime;
  final String rank;

  FeedModel({
    this.title = '',
    this.link = '',
    this.createdTime = '',
    this.rank = '',
  });

  factory FeedModel.fromJson(Map<String, dynamic> json) {
    return FeedModel(
      title: (json['title'] ?? '') as String,
      link: (json['link'] ?? '') as String,
      createdTime: (json['created_time'] ?? '') as String,
      rank: (json['rank'] ?? '') as String,
    );
  }
}
