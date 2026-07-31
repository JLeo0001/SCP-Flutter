import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'core/theme/app_theme.dart';
import 'core/backend/backend_service.dart';
import 'core/utils/route_observer.dart';
import 'features/home/home_page.dart';
import 'features/later/later_page.dart';
import 'features/user/user_page.dart';

/// 主应用 — 日夜切换带动画
class ScpApp extends StatefulWidget {
  const ScpApp({super.key});

  @override
  State<ScpApp> createState() => _ScpAppState();
}

class _ScpAppState extends State<ScpApp> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int _themeTick = 0; // 每次主题变化 +1，触发热区外重建

  /// 底部 tab 索引通知 — 供各页面感知"回到本页"并刷新数据
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);

  late final List<Widget> _pages = [
    const HomePage(),
    const LaterPage(),
    UserPage(tabIndex: _tabIndex),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppTheme.setOnChanged(_onThemeChanged);
    // 启动嵌入式后端
    BackendService.instance.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppTheme.setOnChanged(() {});
    _tabIndex.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (AppTheme.currentTheme == ThemeModeOption.system) {
      setState(() => _themeTick++);
    }
  }

  void _onThemeChanged() {
    if (mounted) setState(() => _themeTick++);
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final light = lightDynamic ??
            ColorScheme.fromSeed(seedColor: const Color(0xFFF0A1A8), brightness: Brightness.light);
        final dark = darkDynamic ??
            ColorScheme.fromSeed(seedColor: const Color(0xFFF0A1A8), brightness: Brightness.dark);
        // 用 _themeTick 触发 DynamicColorBuilder 重建，但不销毁 MaterialApp
        return _ThemeApp(
          key: ValueKey('t$_themeTick'),
          lightScheme: light,
          darkScheme: dark,
          currentIndex: _currentIndex,
          onTabChange: (i) {
            setState(() => _currentIndex = i);
            _tabIndex.value = i;
          },
          pages: _pages,
        );
      },
    );
  }
}

/// 分离出来的主题 App，key 变化时整体重建=动画
class _ThemeApp extends StatelessWidget {
  final ColorScheme lightScheme;
  final ColorScheme darkScheme;
  final int currentIndex;
  final ValueChanged<int> onTabChange;
  final List<Widget> pages;

  const _ThemeApp({
    super.key,
    required this.lightScheme,
    required this.darkScheme,
    required this.currentIndex,
    required this.onTabChange,
    required this.pages,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SCP基金会',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [RouteObservers.observer],
      theme: _buildTheme(lightScheme, Brightness.light),
      darkTheme: _buildTheme(darkScheme, Brightness.dark),
      themeMode: _resolveThemeMode(),
      themeAnimationDuration: const Duration(milliseconds: 500),
      themeAnimationCurve: Curves.easeInOut,
      home: Scaffold(
        body: IndexedStack(index: currentIndex, children: pages),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onTabChange,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: '首页'),
            BottomNavigationBarItem(icon: Icon(Icons.bookmark_border), activeIcon: Icon(Icons.bookmark), label: '待读'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: '我的'),
          ],
        ),
      ),
    );
  }

  ThemeMode _resolveThemeMode() {
    switch (AppTheme.currentTheme) {
      case ThemeModeOption.light: return ThemeMode.light;
      case ThemeModeOption.dark: return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  ThemeData _buildTheme(ColorScheme cs, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      appBarTheme: AppBarTheme(
        centerTitle: true, elevation: 0,
        backgroundColor: brightness == Brightness.dark ? cs.surface : cs.primary,
        foregroundColor: brightness == Brightness.dark ? cs.onSurface : cs.onPrimary,
        scrolledUnderElevation: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cs.surface, selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurfaceVariant, type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tabBarTheme: TabBarTheme(
        labelColor: cs.onPrimary, unselectedLabelColor: cs.onPrimary.withOpacity(0.6),
        indicatorColor: cs.onPrimary,
      ),
    );
  }
}
