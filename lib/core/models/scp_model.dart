/// SCP数据模型 - 对应 ScpModel.kt
class ScpModel {
  final int id;
  final int index;
  final String link;
  final String title;
  final int scpType;
  final String? author;

  ScpModel({
    this.id = -1,
    this.index = -1,
    this.link = '',
    this.title = '',
    this.scpType = -1,
    this.author = '',
  });

  factory ScpModel.fromMap(Map<String, dynamic> map) {
    return ScpModel(
      id: (map['_id'] ?? -1) as int,
      index: (map['_index'] ?? -1) as int,
      link: (map['link'] ?? '') as String,
      title: (map['title'] ?? '') as String,
      scpType: (map['scp_type'] ?? -1) as int,
      author: map['author'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      '_index': index,
      'link': link,
      'title': title,
      'scp_type': scpType,
      'author': author,
    };
  }
}
