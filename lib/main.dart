import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/services/preference_service.dart';
import 'core/services/database_helper.dart';
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

  // 后台加载离线库由用户手动触发（下载/选择文件）
  // 启动时不自动扫描，避免无谓的 I/O

  // 后台申请存储权限（用于字体扫描、离线库文件扫描等）
  // 静默申请，不阻塞；用户实际操作（扫描字体/导入离线库）时若权限不足会再次触发
  if (!await hasStoragePermission()) {
    requestStoragePermission();
  }

  runApp(const ScpApp());
}
