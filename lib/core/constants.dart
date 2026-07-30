/// SCP基金会应用常量定义

class SCPConstants {
  static const String packageName = 'info.free.scp';
  static const String scpDbName = 'scp.db';
  static const String detailDbName = 'scp_data.db';
  static const String levelPrefName = 'level.xml';
  static const String appPrefName = 'app.xml';
  static const String publicDirName = 'scp_reader';
  static const int freeTime = 1619668800000;

  // API — 直连 scp-wiki-cn.wikidot.com，纯 Dart 爬取
  static const String feedApiUrl = '';
  static const String firebaseUrl = '';
  static const String scpSiteUrl = 'http://scp-wiki-cn.wikidot.com';

  static const int historyType = 0;
  static const int laterType = 1;
  static const int simple = 0;
  static const int traditional = 1;
  static const int latestCreated = -2;
  static const int latestTranslated = -3;
  static const int topRatedAll = 0;
  static const int topRatedScp = 1;
  static const int topRatedTales = 2;
  static const int topRatedGoi = 3;
  static const int topRatedWanders = 4;
}

// AppMode
class AppMode {
  static const int online = 0;
  static const int offline = 1;
}

// OrderType
class OrderType {
  static const int asc = 1;
  static const int desc = -1;
}

// SearchType
class SearchType {
  static const int title = 0;
  static const int content = 1;
  static const int tag = 2;
}

// Entry types
class Entry {
  static const int scpDoc = 1001;
  static const int scpCnDoc = 1002;
  static const int storyDoc = 1003;
  static const int goiDoc = 1004;
  static const int artDoc = 1005;
  static const int wanderDoc = 1006;
  static const int libraryDoc = 1007;
  static const int internationalDoc = 1008;
  static const int informationDoc = 1009;
}

// Category
class Category {
  static const int series = 1;
  static const int seriesCn = 2;
  static const int joke = 101;
  static const int scpEx = 102;
  static const int tales = 99;
  static const int talesCn = 98;
  static const int talesByTime = 97;
  static const int settings = 106;
  static const int settingsCn = 107;
  static const int storySeries = 108;
  static const int storySeriesCn = 109;
  static const int contest = 110;
  static const int contestCn = 111;
  static const int wander = 10;
  static const int wanderCn = 11;
}

// ScpType
class ScpType {
  static const int saveSeries = 1;
  static const int saveSeriesCn = 2;
  static const int saveJoke = 3;
  static const int saveJokeCn = 4;
  static const int saveEx = 5;
  static const int saveExCn = 6;
  static const int saveTales = 7;
  static const int saveTalesCn = 8;
  static const int saveCanon = 9;
  static const int saveCanonCn = 10;
  static const int saveStorySeries = 11;
  static const int saveStorySeriesCn = 12;
  static const int saveReport = 13;
  static const int saveAnomalousCn = 14;
  static const int saveShortStory = 15;
  static const int saveLibraryPage = 16;
  static const int saveGoi = 17;
  static const int saveArt = 18;
  static const int saveContest = 19;
  static const int saveContestCn = 20;
  static const int saveWander = 21;
  static const int saveWanderCn = 22;
  static const int saveInternational = 23;
  static const int saveInfoPage = 24;
  static const int saveTalesByTime = 101;
  static const int saveOffset = 100;
}

class BroadCastAction {
  static const String changeTheme = 'changeTheme';
}

class RequestCode {
  static const int categoryToDetail = 0;
  static const int requestFilePermission = 1;
  static const int requestPictureDir = 2;
  static const int requestPublicFile = 3;
  static const int requestBackupDir = 4;
  static const int requestRestoreDir = 5;
}
