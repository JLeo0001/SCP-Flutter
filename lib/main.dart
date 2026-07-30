import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/services/preference_service.dart';
import 'core/services/database_helper.dart';
import 'core/theme/app_theme.dart';
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

  // 后台申请存储权限（用于字体扫描等）
  _requestStoragePermission();

  runApp(const ScpApp());
}

Future<void> _requestStoragePermission() async {
  try {
    // Android 11+ 用 manageExternalStorage，旧版用 storage
    Permission permission;
    if (await Permission.manageExternalStorage.status.isDenied) {
      permission = Permission.manageExternalStorage;
    } else {
      permission = Permission.storage;
    }
    // 不阻塞启动，静默申请
    await permission.request();
  } catch (_) {}
}
