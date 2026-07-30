import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/services/preference_service.dart';
import 'core/services/database_helper.dart';
import 'core/services/offline_content_db.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/permissions.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await PreferenceService.init();
  AppTheme.init();

  // 预初始化数据库
  try {
    await DatabaseHelper.getCatalogDb();
    await DatabaseHelper.getDataDb();
  } catch (_) {}

  // 恢复上次加载的离线库
  await OfflineContentDb.load();

  // 后台申请存储权限（静默，不阻塞）
  if (!await hasStoragePermission()) {
    requestStoragePermission();
  }

  runApp(const ScpApp());
}
