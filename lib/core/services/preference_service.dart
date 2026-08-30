import '../models/favorite_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 偏好设置服务 — 所有持久化配置
class PreferenceService {
  static late SharedPreferences _prefs;
  static bool _initialized = false;

  static Future<void> init() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }

  // ═══════════════════════════════════════
  //  阅读设置
  // ═══════════════════════════════════════

  // ── 字号 ──
  static String getDetailTextSize() => _prefs.getString('detail_text_size') ?? '16px';
  static void setDetailTextSize(String v) => _prefs.setString('detail_text_size', v);

  // ── 字体 ──
  static int getFontFamily() => _prefs.getInt('font_family') ?? 0; // 0=系统 1=衬线 2=等宽
  static void setFontFamily(int v) => _prefs.setInt('font_family', v);

  // ── 行高 ──
  static double getLineHeight() => _prefs.getDouble('line_height') ?? 1.8;
  static void setLineHeight(double v) => _prefs.setDouble('line_height', v);

  // ── 显示图片 ──

  // ── 显示图片 ──
  static bool getShowImages() => _prefs.getBool('show_images') ?? true;
  static void setShowImages(bool v) => _prefs.setBool('show_images', v);

  // ── 自动滚动 ──
  static bool getAutoScroll() => _prefs.getBool('auto_scroll') ?? false;
  static void setAutoScroll(bool v) => _prefs.setBool('auto_scroll', v);
  static double getAutoScrollSpeed() => _prefs.getDouble('auto_scroll_speed') ?? 2.0;
  static void setAutoScrollSpeed(double v) => _prefs.setDouble('auto_scroll_speed', v);

  // ── 常亮(防止休眠) ──
  static bool getKeepScreenOn() => _prefs.getBool('keep_screen_on') ?? false;
  static void setKeepScreenOn(bool v) => _prefs.setBool('keep_screen_on', v);

  // ── 全屏阅读 ──
  static bool getFullScreen() => _prefs.getBool('full_screen') ?? false;
  static void setFullScreen(bool v) => _prefs.setBool('full_screen', v);

  // ── 保留原样式 ──
  static bool getKeepOriginalStyle() => _prefs.getBool('keep_original_style') ?? false;
  static void setKeepOriginalStyle(bool v) => _prefs.setBool('keep_original_style', v);
  static int getHanzType() => _prefs.getInt('detail_hanz_type') ?? 0;
  static void setHanzType(int v) => _prefs.setInt('detail_hanz_type', v);

  // ── 阅读主题 (0=auto 1=light 2=sepia 3=dark 4=pure_dark) ──
  static int getReadingTheme() => _prefs.getInt('reading_theme') ?? 0;
  static void setReadingTheme(int v) => _prefs.setInt('reading_theme', v);

  // ── 对齐方式 (0=left 1=justify) ──
  static int getTextAlign() => _prefs.getInt('text_align') ?? 1;
  static void setTextAlign(int v) => _prefs.setInt('text_align', v);

  // ── 段落间距倍率 (0.5~2.5) ──
  static double getParagraphSpacing() => _prefs.getDouble('para_spacing') ?? 1.0;
  static void setParagraphSpacing(double v) => _prefs.setDouble('para_spacing', v);

  // ── 页面边距 (0=narrow 1=normal 2=wide) ──
  static int getPagePadding() => _prefs.getInt('page_padding') ?? 1;
  static void setPagePadding(int v) => _prefs.setInt('page_padding', v);

  // ── 首行缩进 ──
  static bool getFirstLineIndent() => _prefs.getBool('first_line_indent') ?? false;
  static void setFirstLineIndent(bool v) => _prefs.setBool('first_line_indent', v);

  // ── 字重 (0=normal 1=medium 2=semibold 3=bold) ──
  static int getFontWeight() => _prefs.getInt('font_weight') ?? 0;
  static void setFontWeight(int v) => _prefs.setInt('font_weight', v);

  // ── 代码字号倍率 (0.7~1.3) ──
  static double getCodeFontScale() => _prefs.getDouble('code_font_scale') ?? 0.9;
  static void setCodeFontScale(double v) => _prefs.setDouble('code_font_scale', v);

  // ── 标题字号倍率 (1.0~1.6) ──
  static double getHeadingScale() => _prefs.getDouble('heading_scale') ?? 1.0;
  static void setHeadingScale(double v) => _prefs.setDouble('heading_scale', v);

  // ── 阅读标尺 ──
  static bool getReadingRuler() => _prefs.getBool('reading_ruler') ?? false;
  static void setReadingRuler(bool v) => _prefs.setBool('reading_ruler', v);

  // ── 图片宽度 (0=full 1=contained 2=compact) ──
  static int getImageWidth() => _prefs.getInt('image_width') ?? 0;
  static void setImageWidth(int v) => _prefs.setInt('image_width', v);

  // ── 引用块样式 (0=accent 1=subtle 2=modern) ──
  static int getBlockquoteStyle() => _prefs.getInt('bq_style') ?? 0;
  static void setBlockquoteStyle(int v) => _prefs.setInt('bq_style', v);

  // ── 自定义字体列表 (名称以 | 分隔) ──
  static String getCustomFontNames() => _prefs.getString('custom_font_names') ?? '';
  static void setCustomFontNames(String v) => _prefs.setString('custom_font_names', v);
  static String getCustomFontPaths() => _prefs.getString('custom_font_paths') ?? '';
  static void setCustomFontPaths(String v) => _prefs.setString('custom_font_paths', v);
  /// 解析为列表
  static List<String> get customFontNameList => getCustomFontNames().split('|').where((s) => s.isNotEmpty).toList();
  static List<String> get customFontPathList => getCustomFontPaths().split('|').where((s) => s.isNotEmpty).toList();

  // ═══════════════════════════════════════
  //  App 设置
  // ═══════════════════════════════════════

  static bool isFirstInstall() => _prefs.getBool('firstInstall') ?? true;
  static void setFirstInstall() => _prefs.setBool('firstInstall', false);

  static bool hasCheckPrivacy() => _prefs.getBool('checkPrivacy') ?? false;
  static void setCheckPrivacy() => _prefs.setBool('checkPrivacy', true);

  static String getNotice() => _prefs.getString('notice') ?? '';
  static void setNotice(String v) => _prefs.setString('notice', v);
  static bool getShowNotice() => _prefs.getBool('show_notice') ?? true;
  static void setShowNotice(bool v) => _prefs.setBool('show_notice', v);

  static String getApiUrl() => _prefs.getString('api_url') ?? '';
  static void setApiUrl(String v) => _prefs.setString('api_url', v);
  static int getAppMode() => _prefs.getInt('app_mode') ?? 0;
  static void setAppMode(int v) => _prefs.setInt('app_mode', v);
  static String getCookie() => _prefs.getString('cookie') ?? '';
  static void setCookie(String v) => _prefs.setString('cookie', v);
  static String getAgent() => _prefs.getString('agent') ?? '';
  static void setAgent(String v) => _prefs.setString('agent', v);

  static int getCurrentTheme() => _prefs.getInt('currentTheme') ?? 0;
  static void setCurrentTheme(int v) => _prefs.setInt('currentTheme', v);

  static int getPoint() => _prefs.getInt('point') ?? 0;
  static void addPoints(int p) => _prefs.setInt('point', getPoint() + p);
  static String getNickname() => _prefs.getString('nickname') ?? '';
  static void saveNickname(String n) => _prefs.setString('nickname', n);
  static String getJob() => _prefs.getString('job') ?? '';
  static void setJob(String j) => _prefs.setString('job', j);
  static String getUserId() => _prefs.getString('user_id') ?? '';
  static void setUserId(String id) => _prefs.setString('user_id', id);

  static String getDraftContent() => _prefs.getString('draft_content') ?? '';
  static void saveDraftContent(String c) => _prefs.setString('draft_content', c);
  static String getDraftTitle() => _prefs.getString('draft_title') ?? '';
  static void saveDraftTitle(String t) => _prefs.setString('draft_title', t);

  // ═══════════════════════════════════════
  //  自由收藏 (JSON 列表,见 core/models/favorite_model.dart)
  // ═══════════════════════════════════════

  static const String _favoriteKey = 'favorite_entries';

  static List<FavoriteEntry> getFavorites() =>
      FavoriteEntry.listFromJsonString(_prefs.getString(_favoriteKey) ?? '');

  static Future<void> _saveFavorites(List<FavoriteEntry> list) =>
      _prefs.setString(_favoriteKey, FavoriteEntry.listToJsonString(list));

  /// 新增收藏(插到最前);与最近一条内容相同则视为重复点击,跳过
  static Future<bool> addFavorite(FavoriteEntry e) async {
    final list = getFavorites();
    if (list.isNotEmpty && list.first.content.trim() == e.content.trim()) {
      return false;
    }
    await _saveFavorites([e, ...list]);
    return true;
  }

  /// 撤销删除时按原位置放回
  static Future<void> insertFavoriteAt(int index, FavoriteEntry e) async {
    final list = getFavorites();
    final at = index.clamp(0, list.length);
    await _saveFavorites([...list.sublist(0, at), e, ...list.sublist(at)]);
  }

  static Future<void> removeFavorite(String id) async {
    await _saveFavorites(getFavorites().where((e) => e.id != id).toList());
  }

  static Future<void> updateFavoriteContent(String id, String content) async {
    await _saveFavorites([
      for (final e in getFavorites())
        if (e.id == id) e.copyWith(content: content) else e,
    ]);
  }

  static Future<void> clearFavorites() => _saveFavorites(const []);


  static bool getHideFinished() => _prefs.getBool('hide_finished_article') ?? false;
  static void setHideFinished(bool v) => _prefs.setBool('hide_finished_article', v);

  static bool getShowMeal() => _prefs.getBool('show_meal') ?? false;
  static void setShowMeal(bool v) => _prefs.setBool('show_meal', v);

  // ═══════════════════════════════════════
  //  AI 助手设置 (存储 JSON,模型见 core/ai/ai_models.dart)
  // ═══════════════════════════════════════

  static String getAiSettingsJson() => _prefs.getString('ai_settings') ?? '';
  static Future<void> setAiSettingsJson(String v) => _prefs.setString('ai_settings', v);

  // ═══════════════════════════════════════
  //  离线数据优先
  // ═══════════════════════════════════════

  /// 联网状态下优先使用离线数据（省流量、更快）
  static bool getPreferOffline() => _prefs.getBool('prefer_offline') ?? true;
  static void setPreferOffline(bool v) => _prefs.setBool('prefer_offline', v);
}
