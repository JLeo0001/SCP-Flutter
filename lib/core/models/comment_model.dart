/// 评论模型 - 对应 CommentModel.kt
class CommentModel {
  final String comment;
  final String title;
  final String username;
  final String time;
  final List<CommentModel> replies;

  CommentModel({
    this.comment = '',
    this.title = '',
    this.username = '',
    this.time = '',
    this.replies = const [],
  });
}
