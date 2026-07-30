import '../services/preference_service.dart';

/// 主题模式
class ThemeModeOption {
  static const int system = 0; // 跟随系统
  static const int light = 1;  // 始终日间
  static const int dark = 2;   // 始终夜间
}

/// 主题变化通知回调
typedef ThemeChangeCallback = void Function();

/// 主题管理
class AppTheme {
  static int _currentTheme = ThemeModeOption.system;
  static ThemeChangeCallback? _onChanged;

  static int get currentTheme => _currentTheme;

  static void init() {
    _currentTheme = PreferenceService.getCurrentTheme();
  }

  static void setOnChanged(ThemeChangeCallback cb) {
    _onChanged = cb;
  }

  static void setTheme(int theme) {
    _currentTheme = theme;
    PreferenceService.setCurrentTheme(theme);
    _onChanged?.call();
  }

  static void cycleTheme() {
    setTheme((_currentTheme + 1) % 3);
  }
}
