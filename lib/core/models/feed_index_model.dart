import 'feed_model.dart';

/// Feed首页索引 - 对应 FeedIndexModel.kt
class FeedIndexModel {
  final List<FeedModel> latestCreate;
  final List<FeedModel> latestTranslate;

  FeedIndexModel({
    this.latestCreate = const [],
    this.latestTranslate = const [],
  });

  factory FeedIndexModel.fromJson(Map<String, dynamic> json) {
    return FeedIndexModel(
      latestCreate: (json['latest_create'] as List<dynamic>?)
              ?.map((e) => FeedModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      latestTranslate: (json['latest_translate'] as List<dynamic>?)
              ?.map((e) => FeedModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
