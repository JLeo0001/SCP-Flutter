import 'scp_model.dart';

/// SCP条目模型 - 对应 ScpItemModel.kt
class ScpItemModel extends ScpModel {
  final String? subScpType;
  final String? createdTime;
  // 额外字段（来自数据库）
  final String? detailHtml;
  final int? notFound;
  final String? tags;
  final int? downloadType;
  final String? subText;
  final String? snippet;
  final String? desc;
  final String? creator;
  final String? pageCode;
  final String? contestName;
  final String? contestLink;
  final String? eventType;
  final String? month;
  final String? subLinks;
  final int? isCollection;
  final int? like;
  final int? hasRead;

  ScpItemModel({
    super.id,
    super.index,
    super.link,
    super.title,
    super.scpType,
    super.author,
    this.subScpType,
    this.createdTime,
    this.detailHtml,
    this.notFound,
    this.tags,
    this.downloadType,
    this.subText,
    this.snippet,
    this.desc,
    this.creator,
    this.pageCode,
    this.contestName,
    this.contestLink,
    this.eventType,
    this.month,
    this.subLinks,
    this.isCollection,
    this.like,
    this.hasRead,
  });

  factory ScpItemModel.fromMap(Map<String, dynamic> map) {
    final base = ScpModel.fromMap(map);
    return ScpItemModel(
      id: base.id,
      index: base.index,
      link: base.link,
      title: base.title,
      scpType: base.scpType,
      author: base.author,
      subScpType: map['sub_scp_type'] as String?,
      createdTime: map['created_time'] as String?,
      detailHtml: map['detailHtml'] as String?,
      notFound: map['notFound'] as int? ?? -1,
      tags: map['tags'] as String?,
      downloadType: map['downloadType'] as int?,
      subText: map['subtext'] as String?,
      snippet: map['snippet'] as String?,
      desc: map['desc'] as String?,
      creator: map['creator'] as String?,
      pageCode: map['pageCode'] as String?,
      contestName: map['contestName'] as String?,
      contestLink: map['contestLink'] as String?,
      eventType: map['eventType'] as String?,
      month: map['month'] as String?,
      subLinks: map['subLinks'] as String?,
      isCollection: map['isCollection'] as int? ?? 0,
      like: map['like'] as int? ?? 0,
      hasRead: map['hasRead'] as int? ?? 0,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      ...super.toMap(),
      'sub_scp_type': subScpType,
      'created_time': createdTime,
      'detailHtml': detailHtml,
      'notFound': notFound ?? -1,
      'tags': tags,
      'downloadType': downloadType,
      'subtext': subText,
      'snippet': snippet,
      'desc': desc,
      'creator': creator,
      'pageCode': pageCode,
      'contestName': contestName,
      'contestLink': contestLink,
      'eventType': eventType,
      'month': month,
      'subLinks': subLinks,
      'isCollection': isCollection ?? 0,
      'like': like ?? 0,
      'hasRead': hasRead ?? 0,
    };
  }
}
