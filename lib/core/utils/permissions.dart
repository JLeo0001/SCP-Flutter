import 'package:permission_handler/permission_handler.dart';

/// 请求外部存储访问权限
///
/// Android 11+ (API 30+): 需要 MANAGE_EXTERNAL_STORAGE
///   → 用户需在系统设置中手动开启「允许管理所有文件」
///   → request() 会自动跳转到系统设置页
/// Android 6-10 (API 23-29): 需要 READ_EXTERNAL_STORAGE
///   → 标准运行时权限弹窗
///
/// 返回 true 表示权限已获得
Future<bool> requestStoragePermission() async {
  // ── Android 11+ 第一步：MANAGE_EXTERNAL_STORAGE ──
  try {
    final mes = await Permission.manageExternalStorage.status;
    if (mes.isGranted) return true;

    // 还没申请过或已被拒绝 → 发起请求
    final result = await Permission.manageExternalStorage.request();
    if (result.isGranted) return true;

    // 用户选了「不再询问」→ 引导去设置页
    if (result.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    // 被拒绝但未永久 → 告诉用户用途
    return false;
  } catch (_) {
    // MANAGE_EXTERNAL_STORAGE 在当前系统不可用
    // （Android 10 以下），正常回退到普通 storage
  }

  // ── Android 10 以下回退：READ_EXTERNAL_STORAGE ──
  try {
    final storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted) return true;

    if (storageStatus.isPermanentlyDenied) {
      await openAppSettings();
    }
    return false;
  } catch (_) {
    return false;
  }
}

/// 检查是否已有存储权限（不发起请求）
Future<bool> hasStoragePermission() async {
  try {
    if (await Permission.manageExternalStorage.status.isGranted) return true;
  } catch (_) {}

  try {
    if (await Permission.storage.status.isGranted) return true;
  } catch (_) {}

  return false;
}
