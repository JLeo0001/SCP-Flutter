/// 标签模型 - 对应 TagModel.kt
class TagModel {
  final String name;
  final int count;

  TagModel({this.name = '', this.count = 0});

  factory TagModel.fromJson(Map<String, dynamic> json) {
    return TagModel(
      name: (json['name'] ?? '') as String,
      count: (json['count'] ?? 0) as int,
    );
  }
}
