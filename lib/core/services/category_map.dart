import 'package:flutter/material.dart';
import '../constants.dart';

/// 分类数据映射 — 全部数据驱动，无硬编码 switch/case

/// 类型ID → 显示名称
const typeNames = <int, String>{
  ScpType.saveSeries: 'SCP系列',
  ScpType.saveSeriesCn: 'SCP-CN系列',
  ScpType.saveJoke: '搞笑SCP',
  ScpType.saveJokeCn: 'CN搞笑SCP',
  ScpType.saveEx: '已解明SCP',
  ScpType.saveExCn: 'CN已解明SCP',
  ScpType.saveTales: '基金会故事',
  ScpType.saveTalesCn: 'CN原创故事',
  ScpType.saveTalesByTime: 'CN原创故事(按时间)',
  ScpType.saveCanon: '设定中心',
  ScpType.saveCanonCn: 'CN设定中心',
  ScpType.saveStorySeries: '故事系列',
  ScpType.saveStorySeriesCn: 'CN故事系列',
  ScpType.saveContest: '征文竞赛',
  ScpType.saveContestCn: 'CN征文竞赛',
  ScpType.saveWander: '放逐者图书馆',
  ScpType.saveWanderCn: 'CN放逐者图书馆',
  ScpType.saveGoi: 'GOI格式',
  ScpType.saveArt: '艺术作品',
  ScpType.saveInternational: '国际版',
  ScpType.saveInfoPage: '背景资料',
  ScpType.saveLibraryPage: '图书馆',
  ScpType.saveAnomalousCn: '异常CN',
  ScpType.saveShortStory: '短篇',
  ScpType.saveReport: '报告',
};

/// 入口页面 → 显示名称
const entryNames = <int, String>{
  Entry.scpDoc: 'SCP系列',
  Entry.scpCnDoc: 'SCP-CN系列',
  Entry.storyDoc: '故事',
  Entry.wanderDoc: '放逐者图书馆',
};

/// 入口页面 → 子分类列表
const entryCategories = <int, List<int>>{
  Entry.scpDoc: [
    Category.series,
    Category.joke, Category.scpEx,
    Category.contest,
  ],
  Entry.scpCnDoc: [
    Category.seriesCn,
    Category.joke, Category.scpEx,
    Category.contestCn,
  ],
  Entry.storyDoc: [
    Category.tales, Category.talesCn,
    Category.settings, Category.settingsCn,
    Category.storySeries, Category.storySeriesCn,
  ],
  Entry.wanderDoc: [
    Category.wander, Category.wanderCn,
  ],
};

/// 分类ID → 对应图标
const categoryIcons = <int, IconData>{
  Category.series: Icons.article_outlined,
  Category.seriesCn: Icons.language,
  Category.joke: Icons.sentiment_very_satisfied_outlined,
  Category.scpEx: Icons.check_circle_outline,
  Category.tales: Icons.auto_stories_outlined,
  Category.talesCn: Icons.edit_outlined,
  Category.talesByTime: Icons.access_time_outlined,
  Category.settings: Icons.settings_outlined,
  Category.settingsCn: Icons.settings_outlined,
  Category.storySeries: Icons.collections_bookmark_outlined,
  Category.storySeriesCn: Icons.collections_bookmark_outlined,
  Category.contest: Icons.emoji_events_outlined,
  Category.contestCn: Icons.emoji_events_outlined,
  Category.wander: Icons.explore_outlined,
  Category.wanderCn: Icons.explore_outlined,
};

/// 分类ID → 显示名称
const categoryNames = <int, String>{
  Category.series: 'SCP系列',
  Category.seriesCn: 'SCP-CN系列',
  Category.joke: '搞笑SCP',
  Category.scpEx: '已解明SCP',
  Category.tales: '基金会故事',
  Category.talesCn: 'CN原创故事',
  Category.talesByTime: 'CN原创故事(按时间)',
  Category.settings: '设定中心',
  Category.settingsCn: 'CN设定中心',
  Category.storySeries: '故事系列',
  Category.storySeriesCn: 'CN故事系列',
  Category.contest: '征文竞赛',
  Category.contestCn: 'CN征文竞赛',
  Category.wander: '放逐者图书馆',
  Category.wanderCn: 'CN放逐者图书馆',
};

/// 入口ID + 分类ID → ScpType
/// 格式: {$entryType}_{$category} → ScpType
const _c2t_s = {
  '${Entry.scpDoc}_${Category.series}': ScpType.saveSeries,
  '${Entry.scpDoc}_${Category.seriesCn}': ScpType.saveSeriesCn,
  '${Entry.scpDoc}_${Category.joke}': ScpType.saveJoke,
  '${Entry.scpDoc}_${Category.scpEx}': ScpType.saveEx,
  '${Entry.scpDoc}_${Category.contest}': ScpType.saveContest,
  '${Entry.scpDoc}_${Category.contestCn}': ScpType.saveContestCn,
  '${Entry.scpCnDoc}_${Category.seriesCn}': ScpType.saveSeriesCn,
  '${Entry.scpCnDoc}_${Category.joke}': ScpType.saveJokeCn,
  '${Entry.scpCnDoc}_${Category.scpEx}': ScpType.saveExCn,
  '${Entry.scpCnDoc}_${Category.contestCn}': ScpType.saveContestCn,
  '${Entry.storyDoc}_${Category.tales}': ScpType.saveTales,
  '${Entry.storyDoc}_${Category.talesCn}': ScpType.saveTalesCn,
  '${Entry.storyDoc}_${Category.talesByTime}': ScpType.saveTalesByTime,
  '${Entry.storyDoc}_${Category.settings}': ScpType.saveCanon,
  '${Entry.storyDoc}_${Category.settingsCn}': ScpType.saveCanonCn,
  '${Entry.storyDoc}_${Category.storySeries}': ScpType.saveStorySeries,
  '${Entry.storyDoc}_${Category.storySeriesCn}': ScpType.saveStorySeriesCn,
  '${Entry.storyDoc}_${Category.contest}': ScpType.saveContest,
  '${Entry.storyDoc}_${Category.contestCn}': ScpType.saveContestCn,
  '${Entry.wanderDoc}_${Category.wander}': ScpType.saveWander,
  '${Entry.wanderDoc}_${Category.wanderCn}': ScpType.saveWanderCn,
};

int? resolveSaveType(int entryType, int category) {
  return _c2t_s['${entryType}_$category'];
}
