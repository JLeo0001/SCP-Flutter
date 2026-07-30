/// 收藏模型 - 对应 ScpLikeModel.kt
class ScpLikeModel {
  final String link;
  final String title;
  final bool like;
  final bool hasRead;
  final int boxId;

  ScpLikeModel({
    this.link = '',
    this.title = '',
    this.like = false,
    this.hasRead = false,
    this.boxId = 0,
  });

  factory ScpLikeModel.fromMap(Map<String, dynamic> map) {
    return ScpLikeModel(
      link: (map['link'] ?? '') as String,
      title: (map['title'] ?? '') as String,
      like: map['like'] == 1,
      hasRead: map['hasRead'] == 1,
      boxId: (map['boxId'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'link': link,
      'title': title,
      'like': like ? 1 : 0,
      'hasRead': hasRead ? 1 : 0,
      'boxId': boxId,
    };
  }
}

/// 收藏夹模型
class ScpLikeBox {
  final int id;
  final String name;

  ScpLikeBox({this.id = 0, this.name = ''});

  factory ScpLikeBox.fromMap(Map<String, dynamic> map) {
    return ScpLikeBox(
      id: (map['id'] ?? 0) as int,
      name: (map['name'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }
}
