import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/ai/ai_models.dart';
import '../../core/ai/article_text.dart';
import '../ai/ai_chat_page.dart';
import '../../core/backend/backend_service.dart';
import '../../core/backend/backend_types.dart';
import '../../core/services/database_helper.dart';
import '../../core/services/preference_service.dart';
import '../../core/utils/chinese_converter.dart';
import 'reading_settings.dart';

/// 详情页 — WebView 渲染 + 完整阅读功能
class DetailPage extends StatefulWidget {
  final String link;
  final String title;
  final int? scpType;
  final int? index;

  const DetailPage({
    super.key,
    required this.link,
    required this.title,
    this.scpType,
    this.index,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> with WidgetsBindingObserver {
  final _backend = BackendService.instance;
  WebViewController? _webController;
  String? _detailHtml;
  bool _loading = true;
  bool _isLiked = false;
  bool _isRead = false;
  bool _isInLater = false;
  bool _laterChecked = false;
  bool _autoScrolling = false; // 自动滚动状态（实际滚动由 WebView 内 rAF 驱动）
  Timer? _positionTimer;
  bool _positionRestored = false;
  double? _pendingScrollY; // 页面加载完成后要恢复的滚动位置
  int _readingPct = -1; // 阅读进度百分比（Reader 通道上报，-1=未上报/页面不可滚动）
  List<_TocItem> _toc = []; // 文档目录（h1-h3），由页面 JS 上报
  final ValueNotifier<int> _tocActive = ValueNotifier<int>(-1); // 当前章节索引

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoScroll();
    _stopPositionTimer(saveFinal: true);
    _tocActive.dispose();
    if (PreferenceService.getKeepScreenOn()) {
      WidgetsBinding.instance.renderView.automaticSystemUiAdjustment = true;
    }
    if (PreferenceService.getFullScreen()) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  String get _cleanLink =>
      widget.link.startsWith('/') ? widget.link.substring(1) : widget.link;

  /// 检测文本是否已经是繁体中文
  bool _isTraditionalText(String text) {
    // 检查一些常见的繁体独有字
    final tradChars = ['爲','們','個','動','對','從','體','來','說','書',
        '時','間','門','開','關','學','習','見','長','風','飛',
        '馬','魚','鳥','龍','點','話','語','認','讀','寫','畫',
        '聲','質','數','據','記','錄','級','經','過','進','還',
        '這','麼','嗎','讓','給','處','後','戰','爭','勝','敗',
        '節','驗','報','資','輸','轉','導','軟','權','專','價',
        '幣','廠','醫','藥','樂','歡','愛','驚','張','緊','險',
        '護','幫','請','師','兒','親','訪','談','論','議','決',
        '義','願','離','圖','電','視','標','單','雙','舊','當',
        '極','類','種','樣','態','戲','詞','詩','優','壞','壓',
        '強','熱','凍','燒','頭','飯','湯','鮮','膽','腸','腦',
        '膚','發','復','鬥','曆','鍾','裏','匯','萬','葉','蘇',
        '傘','臺','鬆','穀','範','鬱'];
    int count = 0;
    for (final ch in tradChars) {
      if (text.contains(ch)) count++;
      if (count >= 3) return true; // 出现3个以上繁体字即判定为繁体
    }
    return false;
  }

  /// HTML安全的简繁转换 — 只转换标签外文本，不破坏HTML结构
  /// [toTraditional]: true=简→繁, false=繁→简
  String _htmlSafeConvert(String html, {required bool toTraditional}) {
    final converter = toTraditional
        ? ChineseConverter.toTraditional
        : ChineseConverter.toSimplified;
    final buf = StringBuffer();
    int i = 0;
    while (i < html.length) {
      if (html[i] == '<') {
        // 标签内容不动
        int j = html.indexOf('>', i);
        if (j == -1) { buf.write(html.substring(i)); break; }
        buf.write(html.substring(i, j + 1));
        i = j + 1;
      } else {
        // 文本内容转换
        int j = html.indexOf('<', i);
        if (j == -1) j = html.length;
        buf.write(converter(html.substring(i, j)));
        i = j;
      }
    }
    return buf.toString();
  }

  // ═══ 加载 ═══

  Future<void> _loadData() async {
    try {
      final page = await _backend.getPage(_cleanLink);
      if (page.content.isNotEmpty && mounted) {
        _detailHtml = page.content;
        _positionRestored = false;
        await _initWebView();
        _restorePosition();
        setState(() => _loading = false);
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is OfflinePageNotAvailableException
              ? '该页面不在离线数据库中'
              : '加载失败: $e')),
        );
      }
    }
    _isLiked = await DatabaseHelper.isLiked(_cleanLink);
    _isRead = await DatabaseHelper.hasRead(_cleanLink);
    // 仅记录到历史，不自动标记已读
    if (_detailHtml != null && _detailHtml!.isNotEmpty && mounted) {
      await DatabaseHelper.addRecord(_cleanLink, widget.title, SCPConstants.historyType);
    }
    _checkLaterStatus();
    if (mounted) setState(() {});
  }

  Future<void> _initWebView() async {
    _readingPct = 0;
    _toc = [];
    _tocActive.value = -1;
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('Reader', onMessageReceived: _onReaderMessage);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ts = double.tryParse(PreferenceService.getDetailTextSize().replaceAll('px', '')) ?? 16;
    final showImg = PreferenceService.getShowImages();
    final autoSpeed = PreferenceService.getAutoScrollSpeed();

    String content = _detailHtml!;

    // 移除 Wikidot 的原生 onclick 处理（WebView 中用不到）
    content = content.replaceAll(
        RegExp(r'onclick="WIKIDOT\.[^"]*"'),
        '');

    // 简繁切换：仅转换标签外文本，避免破坏HTML
    await ChineseConverter.ensureLoaded();
    final hanzType = PreferenceService.getHanzType();
    if (hanzType == 1) {
      // 用户选择繁体 → 简→繁转换（若已是繁体则是空操作）
      content = _htmlSafeConvert(content, toTraditional: true);
    } else {
      // 用户选择简体，但文档本身是繁体 → 繁→简转换
      if (_isTraditionalText(content)) {
        content = _htmlSafeConvert(content, toTraditional: false);
      }
    }

    String imgCss = showImg ? '' : 'img, video, iframe, canvas { display: none !important; }';
    // 图片宽度: 0=全宽 1=适中 2=紧凑（此前设置只存储未接入 CSS，导致无效）
    final iw = PreferenceService.getImageWidth().clamp(0, 2);
    final imgMaxPct = const [100, 72, 50][iw];
    final scpImgMax = const [300, 220, 160][iw];
    final imgCenterCss = iw == 0 ? '' : 'img{display:block;margin-left:auto;margin-right:auto;}';
    // 字体选择
    String fontFamilyCss;
    String customFontFaces = '';
    final ff = PreferenceService.getFontFamily();
    final customNames = PreferenceService.customFontNameList;
    final customPaths = PreferenceService.customFontPathList;
    if (ff == 0) {
      fontFamilyCss = '-apple-system,"Noto Sans SC","PingFang SC",sans-serif';
    } else if (ff >= 1 && (ff - 1) < customNames.length && (ff - 1) < customPaths.length) {
      final fontName = customNames[ff - 1];
      fontFamilyCss = '"$fontName",-apple-system,"Noto Sans SC",sans-serif';
      try {
        final file = File(customPaths[ff - 1]);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final b64 = base64Encode(bytes);
          final ext = customPaths[ff - 1].toLowerCase().endsWith('.otf') ? 'opentype' : 'truetype';
          customFontFaces = '<style>@font-face{font-family:"$fontName";src:url(data:font/$ext;base64,$b64)format("$ext");}</style>';
        }
      } catch (_) {}
    } else {
      fontFamilyCss = '-apple-system,"Noto Sans SC","PingFang SC",sans-serif';
    }
    // 字重映射 + 仿粗兜底：Android WebView 的系统 CJK 字体常忽略 font-weight
    // （尤其老设备只提供单一字重），用 -webkit-text-stroke 模拟加粗保证可见效果。
    final fwIndex = PreferenceService.getFontWeight().clamp(0, 3);
    final fw = [400, 500, 600, 700][fwIndex];
    final fwStroke = fw > 400 ? '${(0.02 + (fw - 500) / 100 * 0.015).toStringAsFixed(3)}em' : '0';

    final int rt = PreferenceService.getReadingTheme();
    // 颜色方案: 0=auto 1=light 2=sepia 3=dark 4=pure_dark
    // WebView 内容与 Flutter 外壳（Scaffold/AppBar/底栏/进度浮窗）共用一套调色板，
    // 保证 sepia/纯黑等阅读主题下页面四周不留系统主题的色差
    final pal = _ReadingPalette.of(rt, isDark ? Brightness.dark : Brightness.light);
    final bgColor = pal.bgHex;
    final textColor = pal.textHex;
    final linkColor = pal.linkHex;
    final blockBg = pal.blockBgHex;
    final blockBorder = pal.blockBorderHex;
    final secColor = pal.secHex;
    final headingColor = pal.headingHex;
    final inlineCodeBg = pal.codeBgHex;
    final colorSchemeMeta = pal.isDarkTheme ? '<meta name="color-scheme" content="dark">' : '';
    try {
      await ctrl.setBackgroundColor(pal.bgColor); // 加载期间避免白闪
    } catch (_) {}
    // 深色反转补丁：只要"实际生效"的阅读主题是深色就注入（此前只看系统 isDark，
    // 系统浅色 + 手动选深色主题时，作者内联的浅色卡片会变成浅色字压浅色背景）
    String darkFixJs = pal.isDarkTheme ? '''
(function(){
  function apply(){
    var nodes=[].slice.call(document.querySelectorAll('*'));
    // ── 第一遍（父先子后）：作者硬编码的浅色背景一律压成主题 blockBg ──
    // 判据只看"元素自己是否画了背景"（计算值，不区分 class / 内联 style 写法），
    // 因此对所有文档里的浅灰卡片、浅色表格、提示块通用
    nodes.forEach(function(el){
      var t=el.tagName;
      if(t==='HTML'||t==='BODY'||t==='SCRIPT'||t==='STYLE'||t==='META'||t==='LINK'||t==='IMG')return;
      // 阅读器自身的浮层（进度条/标尺/灯箱/脚注卡）用的是主题强调色，不能被压成 blockBg
      if(el.id&&el.id.indexOf('_')===0)return;
      var cs=getComputedStyle(el);
      var bg=cs.backgroundColor;
      if(!bg||bg==='rgba(0, 0, 0, 0)'||bg==='transparent')return;
      var m=bg.match(/(\\d+)[^\\d]+(\\d+)[^\\d]+(\\d+)/);
      if(!m)return;
      var R=+m[1],G=+m[2],B=+m[3];
      if(0.2126*R+0.7152*G+0.0722*B<128)return;
      el.style.setProperty('background-color','$blockBg','important');
      var bd=cs.borderTopColor;
      if(parseFloat(cs.borderTopWidth)>0&&bd&&bd!=='rgba(0, 0, 0, 0)'){
        el.style.setProperty('border-color','$blockBorder','important');
      }
    });
    // ── 第二遍（子先父后）：作者为浅底准备的深色文字 → 提亮 ──
    // 只处理"元素自己显式设过 color"的（getOwnPropertyDescriptor 可区分作者写的与继承的），
    // 普通正文继承 body 的浅色字，无需干预
    nodes.slice().reverse().forEach(function(el){
      var t=el.tagName;
      if(t==='HTML'||t==='BODY'||t==='SCRIPT'||t==='STYLE'||t==='A'||t==='IMG')return;
      if(el.closest('pre')||el.closest('code'))return;
      var d=Object.getOwnPropertyDescriptor(el.style,'color');
      if(!d||!d.value||!d.value.trim())return;
      var cl=getComputedStyle(el).color;
      var m=cl.match(/(\\d+)[^\\d]+(\\d+)[^\\d]+(\\d+)/);
      if(!m)return;
      var R=+m[1],G=+m[2],B=+m[3];
      var mx=Math.max(R,G,B),mn=Math.min(R,G,B);
      var sat=mx===0?0:(mx-mn)/mx;
      // 保留作者强调色（红/蓝等饱和色常被当语义用），只反转低饱和的灰黑字；
      // 阈值放宽到 160：作者写 #999 这类"弱化灰"是给浅底用的，压暗后会看不清
      if(0.2126*R+0.7152*G+0.0722*B<160&&sat<=0.30){
        el.style.setProperty('color','$textColor','important');
      }
    });
    // ── 链接：按"脚下背景"决定深浅（Wikidot 的 a 常带 !important 内联色）──
    [].slice.call(document.querySelectorAll('a')).forEach(function(a){
      if(a.closest('pre')||a.closest('code'))return;
      var e=a,bg=null;
      while(e&&e.nodeType===1){
        var c=getComputedStyle(e).backgroundColor;
        if(c&&c!=='rgba(0, 0, 0, 0)'&&c!=='transparent'){var mm=c.match(/(\\d+)[^\\d]+(\\d+)[^\\d]+(\\d+)/);if(mm){bg=mm;break;}}
        e=e.parentElement;
      }
      var light=bg?(0.2126*(+bg[1])+0.7152*(+bg[2])+0.0722*(+bg[3]))>=128:false;
      a.style.setProperty('color',light?'#1565c0':'$linkColor','important');
    });
  }
  function run(){ try{apply();}catch(e){} }
  if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',run);}else{run();}
  // 图片延迟加载会撑开布局，稍后再收敛一次
  setTimeout(run,400);
})();
''' : '';

    final html = '''
<!DOCTYPE html><html><head>
$colorSchemeMeta
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=3,user-scalable=yes">
$customFontFaces
<style>
  * { -webkit-tap-highlight-color: transparent; box-sizing: border-box; }
  html { scroll-behavior: auto; }
  body {
    font-family: $fontFamilyCss;
    font-size: ${ts}px; line-height: ${PreferenceService.getLineHeight()};
    font-weight: $fw;
    -webkit-text-stroke: $fwStroke;
    font-synthesis: weight;
    color: $textColor; background: $bgColor;
    padding: ${PreferenceService.getPagePadding() == 0 ? '10px' : PreferenceService.getPagePadding() == 2 ? '24px' : '16px'}; margin: 0;
    word-wrap: break-word; overflow-wrap: break-word;
    text-align: ${PreferenceService.getTextAlign() == 0 ? 'left' : 'justify'};
    -webkit-font-smoothing: antialiased;
    letter-spacing: 0.02em;
  }
  p { margin: ${(12 * PreferenceService.getParagraphSpacing()).round()}px 0; word-break: break-word; ${PreferenceService.getFirstLineIndent() ? 'text-indent: 2em;' : ''} }
  p:first-child { margin-top: 0; ${PreferenceService.getFirstLineIndent() ? 'text-indent: 0;' : ''} }
  strong, b { color: $headingColor; }
  a {
    color: $linkColor; text-decoration: none;
    border-bottom: 1px solid transparent;
    transition: border-color 0.2s ease, opacity 0.2s ease;
  }
  a:active { opacity: 0.7; }
  img {
    max-width: $imgMaxPct%; height: auto;
    border-radius: 8px; margin: 12px 0;
    box-shadow: 0 1px 4px rgba(0,0,0,0.08);
  }
  $imgCenterCss
  $imgCss
  h1,h2,h3,h4,h5,h6 {
    margin: 24px 0 10px; color: $headingColor;
    line-height: 1.35; font-weight: 600;
    letter-spacing: 0.01em;
  }
  h1 { font-size: ${(1.35 * PreferenceService.getHeadingScale()).toStringAsFixed(2)}em; }
  h2 { font-size: ${(1.2 * PreferenceService.getHeadingScale()).toStringAsFixed(2)}em; border-bottom: 1px solid $blockBorder; padding-bottom: 6px; }
  h3 { font-size: ${(1.1 * PreferenceService.getHeadingScale()).toStringAsFixed(2)}em; }
  h4, h5, h6 { font-size: ${(1.0 * PreferenceService.getHeadingScale()).toStringAsFixed(2)}em; }
  blockquote {
    padding: 10px 16px; margin: 12px 0;
    color: $secColor;
    ${PreferenceService.getBlockquoteStyle() == 0 ? 'border-left: 3px solid $linkColor; background: $blockBg; border-radius: 0 6px 6px 0;' : ''}
    ${PreferenceService.getBlockquoteStyle() == 1 ? 'border-left: 2px solid $blockBorder; background: transparent; border-radius: 0;' : ''}
    ${PreferenceService.getBlockquoteStyle() == 2 ? 'border-left: none; background: linear-gradient(135deg, $blockBg, transparent); border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.05);' : ''}
  }
  ._tablewrap {
    overflow-x: auto;
    margin: 12px 0;
    border-radius: 6px;
    border: 1px solid $blockBorder;
  }
  ._tablewrap table { width: 100%; border-collapse: collapse; margin: 0; min-width: 480px; }
  td, th {
    border: 1px solid $blockBorder; padding: 8px 12px;
    text-align: left; vertical-align: top;
  }
  th { background: $blockBg; font-weight: 600; color: $headingColor; }
  pre {
    background: $blockBg; padding: 14px;
    overflow-x: auto; border-radius: 6px;
    font-size: ${(0.88 * PreferenceService.getCodeFontScale()).toStringAsFixed(2)}em;
    line-height: 1.5;
    border: 1px solid $blockBorder;
    position: relative;
  }
  code {
    background: $inlineCodeBg;
    padding: 2px 6px; border-radius: 4px;
    font-size: ${(0.9 * PreferenceService.getCodeFontScale()).toStringAsFixed(2)}em;
    font-family: "JetBrains Mono","Cascadia Code","SF Mono",monospace;
  }
  pre code { background: none; padding: 0; border-radius: 0; }
  hr { border: none; height: 1px; background: $blockBorder; margin: 24px 0; }
  .collapsible-block {
    margin: 10px 0; border: 1px solid $blockBorder;
    border-radius: 8px; overflow: hidden;
  }
  .collapsible-block-folded { padding: 10px 14px; background: $blockBg; cursor: pointer; font-weight: 500; }
  .collapsible-block-unfolded { padding: 14px; display: none; }
  .collapsible-block-content { padding: 4px 0; }
  .collapsible-block-link { color: $linkColor; text-decoration: none; font-size: 0.9em; }
  .scp-image-block { float: right; margin: 0 0 12px 20px; max-width: ${scpImgMax}px; }
  .scp-image-caption {
    display: block; font-size: 0.85em; color: $secColor;
    text-align: center; padding: 6px 0;
  }
  .scp-image-block img { max-width: 100%; }
  .page-tags { padding: 10px 0; margin-top: 20px; border-top: 1px solid $blockBorder; font-size: 0.85em; }
  .page-tags a { color: $linkColor; margin-right: 8px; }
  .heading {
    font-size: 1.15em; font-weight: 600;
    margin: 20px 0 10px; padding-bottom: 6px;
    border-bottom: 1px solid $blockBorder;
  }
  .licensebox {
    margin: 16px 0; padding: 10px 14px;
    border: 1px solid $blockBorder; background: $blockBg;
    font-size: 0.88em; color: $secColor; border-radius: 6px;
  }
  .content-separator { display: block; height: 1px; background: $blockBorder; margin: 20px 0; }
  .footer-wikiwalk-nav {
    text-align: center; padding: 14px; margin-top: 20px;
    border-top: 2px solid $blockBorder; font-size: 0.85em;
  }
  .scpnet-interwiki-wrapper { padding: 10px; margin: 10px 0; background: $blockBg; border-radius: 6px; font-size: 0.9em; }
  .list-pages-box { margin: 10px 0; }
  .list-pages-item { padding: 8px 0; border-bottom: 1px solid $blockBorder; }
  sup { font-size: 0.72em; vertical-align: super; color: $linkColor; }
  sub { font-size: 0.72em; vertical-align: sub; }
  /* ═══ Wikidot class compatibility ═══ */
  .wiki-content-table td, .wiki-content-table th,
  .content-panel, .info-container, .notice-block,
  .rating span, .odialog-shader, .yui-navset,
  [style*="background:#f0eeee"], [style*="background: #f0eeee"],
  [style*="background-color:#f0eeee"], [style*="background-color: #f0eeee"] {
    color: $textColor !important;
    background-color: $blockBg !important;
  }
  .yui-navset .yui-content { background: transparent !important; }
  .yui-nav .selected a, .yui-nav a { color: $linkColor !important; }

  /* rating widget — 只读展示，不隐藏 */
  .page-rate-widget-box {
    display: inline-flex; align-items: center; gap: 2px;
    margin: 8px 0; padding: 4px 8px;
    background: $blockBg; border-radius: 6px;
    border: 1px solid $blockBorder;
    font-size: 13px;
  }
  .rate-box-with-text .rate-box-text { color: $secColor; }
  .page-rate-widget-box .cancel { display: none; }
  .page-rate-widget-box .rate-box-label { color: $secColor; font-size: 11px; }

  /* page info footer */
  #page-info, .page-info {
    margin: 16px 0; padding: 8px 12px;
    background: $blockBg; border-radius: 6px;
    font-size: 12px; color: $secColor;
    border: 1px solid $blockBorder;
  }

  /* hide admin/edit buttons in WebView */
  #action-area, #page-options, .edit-button, .edit-buttons,
  .printonly, .print-footer, .options-bar,
  #page-options-bottom, #page-options-area,
  .buttons, .button-bar, .action-buttons { display: none !important; }

  /* AJAX loading indicator */
  .wait-block, .ajax-loader, .loading-indicator { display: none !important; }

  /* foldable blocks */
  .foldable-block { margin: 10px 0; border: 1px solid $blockBorder; border-radius: 8px; overflow: hidden; }
  .foldable-block-folded { padding: 10px 14px; background: $blockBg; cursor: pointer; font-weight: 500; }
  .foldable-block-unfolded { padding: 14px; display: none; }

  /* featured content */
  .featured, .featured-box {
    margin: 12px 0; padding: 12px 16px;
    background: $blockBg; border-radius: 6px;
    border-left: 3px solid $linkColor;
  }

  /* hover / action panels */
  .hover-box, .action-box {
    margin: 10px 0; padding: 10px 14px;
    background: $blockBg; border-radius: 6px;
    border: 1px solid $blockBorder;
  }

  /* inline rating spans */
  span.rating { color: $linkColor; font-weight: 500; }

  /* citation / bibliography */
  .cite, .citation {
    margin: 8px 0; padding: 6px 10px;
    font-size: 0.88em; color: $secColor;
    border-left: 2px solid $blockBorder;
  }

  /* level / header anchors */
  a[name], a[id] { scroll-margin-top: 8px; }

  /* list pages alternative */
  .list-pages-box { margin: 10px 0; }
  .list-pages-item { padding: 8px 0; border-bottom: 1px solid $blockBorder; }

  /* image container */
  .image-container { max-width: 100%; margin: 10px 0; }
  .image-container img { border-radius: 8px; }

  /* blockquote variants */
  .blockquote, .blockquote-style {
    margin: 10px 0; padding: 10px 16px;
    background: $blockBg; border-radius: 6px;
    border-left: 3px solid $linkColor;
    color: $secColor;
  }

  /* math / formulas */
  .math-equation, .formula { overflow-x: auto; margin: 8px 0; }

  /* address / author credit */
  .credit, .license-area, .license {
    font-size: 0.85em; color: $secColor;
    margin: 12px 0; padding: 6px 0;
    border-top: 1px solid $blockBorder;
  }
  ._copybtn {
    position: absolute; top: 6px; right: 6px;
    padding: 3px 10px; font-size: 11px;
    background: rgba(128,128,128,0.15);
    color: $secColor; border: none; border-radius: 4px;
    cursor: pointer; opacity: 0; transition: opacity 0.2s;
  }
  pre:hover ._copybtn { opacity: 1; }
  ._fnpop {
    position: absolute; z-index: 99999;
    padding: 10px 14px 12px; border-radius: 10px;
    font-size: 13px; line-height: 1.6;
    max-width: 88vw; pointer-events: auto;
    box-shadow: 0 4px 24px rgba(0,0,0,0.3);
    opacity: 0; transform: translateY(4px);
    transition: opacity 0.18s ease, transform 0.18s ease;
  }
  ._fnpop.show { opacity: 1; transform: translateY(0); }
  #_progress {
    position: fixed; top: 0; left: 0; height: 2px;
    background: $linkColor; width: 0%;
    z-index: 99998; transition: width 0.3s ease;
  }
  #_ruler {
    position: fixed; left: 0; right: 0; height: 2px;
    background: $linkColor; opacity: 0; pointer-events: none;
    z-index: 99997; transition: opacity 0.3s ease;
  }
  #_ruler.show { opacity: 0.5; }
  /* 图片点击放大遮罩 */
  #_lightbox {
    position: fixed; top: 0; left: 0; right: 0; bottom: 0; z-index: 100000; display: none;
    background: rgba(0,0,0,0.9);
    align-items: center; justify-content: center; flex-direction: column;
  }
  #_lightbox img { max-width: 96vw; max-height: 84vh; box-shadow: none; margin: 0; border-radius: 0; }
  #_lightbox .cap { color: #ddd; font-size: 13px; margin-top: 12px; padding: 0 16px; text-align: center; max-width: 92vw; }
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after { transition-duration: 0.01ms !important; }
  }
</style>
<script>
// ── 初始化（DOM 就绪后执行）──
// 脚本位于 <head>，解析时 <body> 尚未生成，直接 getElementById 会拿到 null；
// 必须等 DOMContentLoaded 之后才能操作 _progress / _ruler。
function _initReader(){
  var prog = document.getElementById('_progress');
  var ruler = document.getElementById('_ruler');
  var rulerOn = ${PreferenceService.getReadingRuler() ? 'true' : 'false'};

  // reading progress bar
  var ticking = false, lastPct = -2;
  function updateProgress(){
    if(!prog)return;
    var h = document.documentElement.scrollHeight - window.innerHeight;
    if(h<=0){ if(lastPct!==-1){ lastPct=-1; _post({t:'progress',p:-1}); } return; }
    var p = Math.min(100, (window.scrollY/h)*100);
    prog.style.width = p+'%';
    var pct = Math.round(p);
    if(pct!==lastPct){ lastPct=pct; _post({t:'progress',p:pct}); }
  }
  window.addEventListener('scroll',function(){
    if(!ticking){ requestAnimationFrame(function(){ updateProgress(); updateTocActive(); ticking=false; }); ticking=true; }
  },{passive:true});
  updateProgress();

  // reading ruler
  function updateRuler(){
    if(!ruler)return;
    if(rulerOn){
      ruler.className='show';
      // #_ruler 为 position:fixed，top 必须用视口坐标；
      // 之前误加 scrollY，滚动后标尺被推到视口之外不可见
      ruler.style.top=(window.innerHeight*0.48)+'px';
    }else{ruler.className='';}
  }
  window.addEventListener('scroll',updateRuler,{passive:true});
  window.addEventListener('resize',updateRuler);
  updateRuler();

  // ── 目录 (TOC)：采集 h1-h3 标题，赋 id，供跳转与当前章节高亮 ──
  var _tocHeads = [];
  function measureToc(){
    for(var i=0;i<_tocHeads.length;i++){
      var el=document.getElementById(_tocHeads[i].id);
      if(el){ var r=el.getBoundingClientRect(); _tocHeads[i].top=r.top+window.scrollY; }
    }
  }
  function buildToc(){
    var hs = document.querySelectorAll('h1,h2,h3');
    if(!hs||!hs.length)return;
    var seen={}, items=[];
    for(var i=0;i<hs.length;i++){
      var h=hs[i], txt=(h.textContent||'').trim();
      if(!txt || txt.length>120) continue;
      if(!h.id) h.id='_toc_'+i;
      if(seen[h.id])continue; seen[h.id]=1;
      _tocHeads.push({id:h.id, top:0});
      items.push({lvl:parseInt(h.tagName.substring(1)), text:txt, id:h.id});
    }
    if(items.length){ _post({t:'toc', items:items}); }
    measureToc();
    window.addEventListener('resize',function(){ setTimeout(measureToc,200); });
  }
  var tocActive = -1;
  function updateTocActive(){
    if(!_tocHeads.length)return;
    var y = window.scrollY + window.innerHeight*0.28, idx = -1;
    for(var i=0;i<_tocHeads.length;i++){ if(_tocHeads[i].top<=y) idx=i; else break; }
    if(idx!==tocActive){ tocActive=idx; _post({t:'tocActive', idx:idx}); }
  }
  buildToc();
  updateTocActive();
}
if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',_initReader);
}else{
  _initReader();
}
// ── 自动滚动（rAF 帧驱动，无级平滑；触摸即暂停；到底自动停止）──
// _post 供全脚本使用（进度上报/自动滚动事件），必须位于顶层作用域
function _post(o){ try{ if(window.Reader&&Reader.postMessage)Reader.postMessage(JSON.stringify(o)); }catch(e){} }
var _auto={on:false,speed:120,last:0,raf:0};
function __autoStart(sp){
  __autoStop();
  _auto.on=true;_auto.speed=sp;_auto.last=0;
  function step(ts){
    if(!_auto.on)return;
    if(_auto.last===0)_auto.last=ts;
    var dt=(ts-_auto.last)/1000;_auto.last=ts;
    var h=document.documentElement.scrollHeight-window.innerHeight;
    if(h>0&&window.scrollY>=h-1){_auto.on=false;_post({t:'auto_end'});return;}
    window.scrollBy(0,_auto.speed*dt);
    _auto.raf=requestAnimationFrame(step);
  }
  _auto.raf=requestAnimationFrame(step);
}
function __autoStop(){
  _auto.on=false;
  if(_auto.raf){cancelAnimationFrame(_auto.raf);_auto.raf=0;}
}
document.addEventListener('touchstart',function(){
  if(_auto.on)_post({t:'auto_touch'});
},{passive:true});
// ── 目录跳转（供 Flutter 侧调用）：目标前留 12px 避让顶部进度条 ──
window.__tocGo=function(id){
  var el=document.getElementById(id);
  if(!el)return;
  var y=el.getBoundingClientRect().top+window.scrollY-12;
  window.scrollTo({top:y<0?0:y,behavior:'smooth'});
};
// ── 点击事件 ──
document.addEventListener('click',function(e){
  // 图片点击放大（仅当 img src 或所在 <a> href 指向图片时拦截，普通链接照常跳转）
  if(e.target && e.target.tagName==='IMG'){
    var im=e.target, src=im.currentSrc||im.src||'';
    var la=im.closest('a'), href=la?(la.href||''):'';
    var imgRe=/[.](png|jpe?g|gif|webp|bmp|svg)([?].*)?[\$]/i;
    if(imgRe.test(src)||imgRe.test(href)){
      e.preventDefault();e.stopPropagation();
      var box=document.createElement('div');box.id='_lightbox';
      var big=document.createElement('img');big.src=imgRe.test(href)?href:src;
      box.appendChild(big);
      var blk=im.closest('.scp-image-block');
      if(blk){var cp=blk.querySelector('.scp-image-caption');
        if(cp&&cp.textContent.trim()){var c=document.createElement('div');c.className='cap';c.textContent=cp.textContent.trim();box.appendChild(c);}}
      box.style.display='flex';
      box.addEventListener('click',function(ev){ev.stopPropagation();ev.preventDefault();box.remove();},true);
      document.body.appendChild(box);
      return;
    }
  }
  // collapsible blocks
  var f=e.target.closest('.collapsible-block-folded');
  if(f){var b=f.closest('.collapsible-block');var u=b.querySelector('.collapsible-block-unfolded');
  f.style.display='none';u.style.display='block';return;}
  var uc=e.target.closest('.collapsible-block-unfolded-link');
  if(uc){var b=uc.closest('.collapsible-block');var f2=b.querySelector('.collapsible-block-folded');
  var un=b.querySelector('.collapsible-block-unfolded');
  un.style.display='none';f2.style.display='block';return;}
  // foldable blocks
  var ff=e.target.closest('.foldable-block-folded');
  if(ff){var fb=ff.closest('.foldable-block');var fu=fb.querySelector('.foldable-block-unfolded');
  ff.style.display='none';fu.style.display='block';return;}
  var fu=e.target.closest('.foldable-block-unfolded-link');
  if(fu){var fb=fu.closest('.foldable-block');var ff2=fb.querySelector('.foldable-block-folded');
  var fu2=fb.querySelector('.foldable-block-unfolded');
  fu2.style.display='none';ff2.style.display='block';return;}
  // Rate widget clicks — no-op in WebView
  if(e.target.closest('.page-rate-widget-box')){e.preventDefault();return;}
  // 脚注弹窗 — 显示在点击引用上方
  var fr=e.target.closest('.footnoteref');
  if(fr){
    e.preventDefault();e.stopPropagation();
    var id=fr.id.replace('footnoteref-','');
    var fn=document.getElementById('footnote-'+id);
    if(fn){
      var pop=document.getElementById('_fnpop');
      if(!pop){
        pop=document.createElement('div');pop.id='_fnpop';
        pop.style.cssText='position:absolute;z-index:99999;background:${pal.fnBgHex};color:${pal.fnTextHex};border:1px solid ${pal.fnBorderHex};padding:10px 14px 12px;border-radius:8px;font-size:13px;line-height:1.6;box-shadow:0 4px 24px rgba(0,0,0,0.25);max-width:88vw;pointer-events:auto;';
        // header
        var hd=document.createElement('div');
        hd.style.cssText='display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;';
        var lb=document.createElement('span');lb.textContent='脚注';lb.style.cssText='font-size:11px;opacity:0.5;';
        var cl=document.createElement('span');cl.textContent='✕';cl.style.cssText='font-size:16px;cursor:pointer;padding:0 4px;opacity:0.6;';
        cl.onclick=function(ev){ev.stopPropagation();pop.remove();};
        hd.appendChild(lb);hd.appendChild(cl);pop.appendChild(hd);
        // body
        var bd=document.createElement('div');pop.appendChild(bd);
        document.body.appendChild(pop);
        // 滚动或窗口大小变化时关闭
        var closePop=function(){if(pop.parentNode)pop.remove();};
        window.addEventListener('scroll',closePop,{once:true});
        window.addEventListener('resize',closePop,{once:true});
      }
      var bd=pop.querySelector('div:last-child');
      bd.innerHTML=fn.innerHTML;
      // 定位：获取 fr 相对 viewport 的位置
      var rect=fr.getBoundingClientRect();
      var pageTop=window.scrollY+rect.top;
      pop.style.display='block';pop.style.visibility='hidden';
      var ph=pop.offsetHeight,pw=pop.offsetWidth,vw=window.innerWidth;
      var popTop=pageTop-ph-8; // 默认上方
      if(popTop<window.scrollY+8)popTop=pageTop+rect.height+8; // 上方不够放下方
      var popLeft=rect.left+rect.width/2-pw/2;
      popLeft=Math.max(8,Math.min(popLeft,vw-pw-8));
      pop.style.top=popTop+'px';pop.style.left=popLeft+'px';
      pop.style.visibility='visible';\n    requestAnimationFrame(function(){pop.className='_fnpop show';});
    }
    return;
  }
  // 点击其他地方关闭脚注弹窗
  var p=document.getElementById('_fnpop');
  if(p&&p.style.display!=='none'&&!p.contains(e.target)&&!e.target.closest('.footnoteref')){p.remove();}
});
$darkFixJs
</script></head><body>
<div id="_progress"></div>
<div id="_ruler"></div>
$content
</body></html>''';

    ctrl.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (_) async {
        // 页面渲染完成后恢复阅读位置
        if (_pendingScrollY != null && _pendingScrollY! > 0) {
          try {
            await ctrl.runJavaScript('window.scrollTo(0, $_pendingScrollY)');
          } catch (_) {}
          _pendingScrollY = null;
        }
        // loadHtmlString 后立即启动的自动滚动可能早于脚本就绪而空转，这里补一次
        if (_autoScrolling) {
          try {
            final px = (PreferenceService.getAutoScrollSpeed() * 60).clamp(30.0, 480.0).toStringAsFixed(1);
            await ctrl.runJavaScript('if(window.__autoStart)__autoStart($px)');
          } catch (_) {}
        }
      },
      onNavigationRequest: (req) async {
        if (req.url.startsWith('about:blank')) return NavigationDecision.navigate;
        final uri = Uri.tryParse(req.url);
        if (uri == null) {
          launchUrl(Uri.parse(req.url), mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        }

        // 识别站内链接
        final isWikidot = uri.host == 'scp-wiki-cn.wikidot.com' ||
            uri.host == 'scp-wiki.wikidot.com' ||
            uri.host == 'www.scp-wiki-cn.wikidot.com';
        final isRelative = !uri.hasScheme || uri.host.isEmpty;
        final isAboutBlank = uri.scheme == 'about' && uri.path.isNotEmpty;

        if (isWikidot || isRelative || isAboutBlank) {
          String pn = uri.path;
          if (isAboutBlank) {
            pn = uri.path; // about:blank/scp-173 → /scp-173 或 scp-173
          }
          if (pn.startsWith('/')) pn = pn.substring(1);
          // 去掉fragment hash
          if (pn.contains('#')) pn = pn.split('#').first;
          if (pn.isEmpty || pn.startsWith('system:') || pn.startsWith('_')) {
            return NavigationDecision.prevent;
          }
          // 查本地数据库（尝试多种链接格式）
          String? dbTitle;
          try {
            // 优先精确匹配
            var match = await DatabaseHelper.getScpByLink('/$pn');
            if (match == null) {
              // 尝试转小写（Wikidot 链接大小写不敏感）
              match = await DatabaseHelper.getScpByLink('/${pn.toLowerCase()}');
            }
            if (match == null) {
              // 尝试去掉特殊后缀
              final base = pn.replaceAll(RegExp(r'_[a-z]+$'), '');
              if (base != pn) {
                match = await DatabaseHelper.getScpByLink('/$base');
              }
            }
            if (match != null) {
              final m = match; // 局部固定非空引用
              dbTitle = m.title;
              if (mounted) {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => DetailPage(link: m.link, title: m.title)));
                return NavigationDecision.prevent;
              }
            }
          } catch (_) {}
          // 数据库未命中：用 pn 生成友好标题
          final fallbackTitle = dbTitle ?? pn.replaceAll('-', ' ').replaceAll('_', ' ');
          if (mounted) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => DetailPage(link: pn, title: fallbackTitle)));
          }
          return NavigationDecision.prevent;
        }

        // 外部链接
        launchUrl(Uri.parse(req.url), mode: LaunchMode.externalApplication);
        return NavigationDecision.prevent;
      },
    ));

    await ctrl.loadHtmlString(html, baseUrl: 'http://scp-wiki-cn.wikidot.com');
    _webController = ctrl;

    // 应用系统设置
    _applySystemSettings();
    // 自动滚动
    if (PreferenceService.getAutoScroll()) _startAutoScroll(autoSpeed);
  }

  void _applySystemSettings() {
    if (PreferenceService.getKeepScreenOn()) {
      WidgetsBinding.instance.renderView.automaticSystemUiAdjustment = false;
    }
    if (PreferenceService.getFullScreen()) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // ═══ 自动滚动 ═══

  /// [speed] 为设置面板 0.5~5.0 档位；×60 换算为 px/s（与旧版每 50ms speed*3px 等速），
  /// 实际滚动由页面内 rAF 逐帧执行，比 Timer + scrollBy 平滑得多
  void _startAutoScroll(double speed) {
    _autoScrolling = true;
    final px = (speed * 60).clamp(30.0, 480.0).toStringAsFixed(1);
    try {
      _webController?.runJavaScript('if(window.__autoStart)__autoStart($px)');
    } catch (_) {}
  }

  void _stopAutoScroll() {
    _autoScrolling = false;
    try {
      _webController?.runJavaScript('if(window.__autoStop)__autoStop()');
    } catch (_) {}
  }

  // ═══ JS 通道（Reader）═══

  void _onReaderMessage(JavaScriptMessage msg) {
    Object? data;
    try {
      data = jsonDecode(msg.message);
    } catch (_) {
      return;
    }
    if (data is! Map) return;
    switch (data['t']) {
      case 'progress':
        final p = (data['p'] as num?)?.round();
        if (p == null || p < -1 || p > 100) return;
        if (p != _readingPct && mounted) setState(() => _readingPct = p);
        break;
      case 'auto_touch': // 用户触摸屏幕 → 暂停自动滚动
      case 'auto_end': // 滚动到页面底部 → 停止
        if (!_autoScrolling) return;
        _stopAutoScroll();
        if (mounted) {
          setState(() {});
          if (data['t'] == 'auto_end') _snack('已到达页面底部');
        }
        break;
      case 'toc': // 页面解析出目录
        final list = data['items'];
        if (list is! List) return;
        final items = <_TocItem>[];
        for (final it in list) {
          if (it is Map && it['id'] != null) {
            items.add(_TocItem(
              level: (it['lvl'] as num?)?.toInt() ?? 2,
              text: (it['text'] ?? '').toString(),
              id: it['id'].toString(),
            ));
          }
        }
        if (mounted) setState(() => _toc = items);
        break;
      case 'tocActive': // 当前所在章节变化
        final idx = (data['idx'] as num?)?.toInt() ?? -1;
        if (idx != _tocActive.value) _tocActive.value = idx;
        break;
    }
  }

  // ═══ 阅读位置 ═══

  void _startPositionTimer() {
    _stopPositionTimer();
    _positionTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _saveCurrentPosition();
    });
  }

  void _stopPositionTimer({bool saveFinal = false}) {
    _positionTimer?.cancel();
    _positionTimer = null;
    if (saveFinal) _saveCurrentPosition();
  }

  Future<void> _saveCurrentPosition() async {
    if (_webController == null || !_positionRestored) return;
    try {
      final result = await _webController!.runJavaScriptReturningResult(
          'window.scrollY || document.documentElement.scrollTop || 0');
      final scrollY = double.tryParse(result.toString()) ?? 0;
      await DatabaseHelper.saveReadingPosition(_cleanLink, scrollY);
    } catch (_) {}
  }

  Future<void> _restorePosition() async {
    if (_positionRestored || _webController == null) return;
    _positionRestored = true;
    try {
      final saved = await DatabaseHelper.getReadingPosition(_cleanLink);
      if (saved != null && saved > 0) {
        _pendingScrollY = saved;
        // 立即尝试 scrollTo — 页面可能已渲染完毕
        await _tryScrollNow(saved);
        // 让用户知道位置变化来自"继续阅读"而非页面 bug
        if (mounted && _readingPct > 0) {
          _snack('已恢复上次阅读位置 · $_readingPct%');
        } else if (mounted) {
          _snack('已恢复上次阅读位置');
        }
      }
    } catch (_) {}
    _startPositionTimer();
  }

  /// 立即尝试滚动，不等待 onPageFinished
  Future<void> _tryScrollNow(double y) async {
    if (_webController == null) return;
    try {
      await _webController!.runJavaScript('window.scrollTo(0, $y)');
    } catch (_) {}
  }

  // ═══ 目录 ═══

  Future<void> _showToc() async {
    if (_toc.length < 2) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      builder: (sheetCtx) {
        // 面板内的跳转按钮用 PopScope 之外的方式：点击项 → 关面板 → 滚动
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(children: [
                  Text('目录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(sheetCtx).colorScheme.onSurface)),
                  const Spacer(),
                  Text('${_toc.length} 个章节', style: TextStyle(fontSize: 12, color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant)),
                ]),
              ),
              Flexible(
                child: ValueListenableBuilder<int>(
                  valueListenable: _tocActive,
                  builder: (_, active, __) => ListView.builder(
                    shrinkWrap: true,
                    itemCount: _toc.length,
                    itemBuilder: (_, i) {
                      final it = _toc[i];
                      final isCur = i == active;
                      final indent = (it.level - 1) * 14.0;
                      return ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -1),
                        contentPadding: EdgeInsets.only(left: 16 + indent, right: 16),
                        leading: isCur
                            ? Icon(Icons.circle, size: 8, color: Theme.of(sheetCtx).colorScheme.primary)
                            : null,
                        title: Text(
                          it.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: it.level == 1 ? 15 : 14,
                            fontWeight: isCur ? FontWeight.w600 : (it.level == 1 ? FontWeight.w600 : FontWeight.normal),
                            color: isCur ? Theme.of(sheetCtx).colorScheme.primary : Theme.of(sheetCtx).colorScheme.onSurface,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          _tocGo(it.id);
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _tocGo(String id) {
    final c = _webController;
    if (c == null) return;
    // 与触摸暂停一致：手动跳转章节时先停自动滚动，避免 rAF 打断平滑动画
    if (_autoScrolling) {
      _stopAutoScroll();
      if (mounted) setState(() {});
    }
    try {
      c.runJavaScript('window.__tocGo && window.__tocGo(${jsonEncode(id)})');
    } catch (_) {}
  }

  Widget _buildExitBtn() {
    return GestureDetector(
      onTap: () {
        PreferenceService.setFullScreen(false);
        setState(() {});
        _applySystemSettings();
      },
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.black26,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, size: 18, color: Colors.white70),
      ),
    );
  }

  Widget _buildTocBtn() {
    return GestureDetector(
      onTap: _showToc,
      child: Container(
        width: 36, height: 36,
        decoration: const BoxDecoration(
          color: Colors.black26,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.list_alt, size: 18, color: Colors.white70),
      ),
    );
  }

  // ═══ 设置面板 ═══

  Future<void> _showSettings() async {
    _stopAutoScroll();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ReadingSettingsPanel(
        onChanged: (SettingChange type) {
          setState(() {});
          _applySystemSettings();
          if (type == SettingChange.visual && _webController != null && _detailHtml != null) {
            // 视觉变更(字号/字体/行高/图片/简繁) → 重载 WebView
            _reloadWebViewWithPosition();
          } else if (type == SettingChange.toggle) {
            // 简单开关(自动滚动/常亮/全屏) → 直接控制，不重载
            if (PreferenceService.getAutoScroll()) {
              _startAutoScroll(PreferenceService.getAutoScrollSpeed());
            } else {
              _stopAutoScroll();
            }
          }
        },
      ),
    );

    // 关闭面板后，确保自动滚动状态与 preference 一致
    if (PreferenceService.getAutoScroll()) {
      _startAutoScroll(PreferenceService.getAutoScrollSpeed());
    } else {
      _stopAutoScroll();
    }
  }

  /// 保存当前位置 → 重建 WebView → 恢复位置
  Future<void> _reloadWebViewWithPosition() async {
    if (_webController == null || _detailHtml == null) return;
    double scrollY = 0;
    try {
      final result = await _webController!.runJavaScriptReturningResult(
          'window.scrollY || document.documentElement.scrollTop || 0');
      scrollY = double.tryParse(result.toString()) ?? 0;
    } catch (_) {}
    await DatabaseHelper.saveReadingPosition(_cleanLink, scrollY);
    _positionRestored = false;
    _pendingScrollY = scrollY; // onPageFinished 会在页面渲染后恢复
    await _initWebView();
    if (_webController != null) {
      _positionRestored = true;
      _startPositionTimer();
    }
    setState(() {});
  }

  // ═══ 操作 ═══

  Future<void> _toggleLike() async {
    await DatabaseHelper.setLike(_cleanLink, widget.title, !_isLiked);
    setState(() => _isLiked = !_isLiked);
    _snack(_isLiked ? '已收藏' : '已取消收藏');
  }

  Future<void> _markRead() async {
    if (_isRead) {
      await DatabaseHelper.setUnread(_cleanLink);
      setState(() => _isRead = false);
      _snack('已取消已读');
    } else {
      await DatabaseHelper.setHasRead(_cleanLink, widget.title);
      // 写入历史记录(replace覆盖待读记录，因link是主键)
      await DatabaseHelper.addRecord(_cleanLink, widget.title, SCPConstants.historyType);
      setState(() => _isRead = true);
      _snack('已标记为已读');
    }
  }

  Future<void> _checkLaterStatus() async {
    try {
      final records = await DatabaseHelper.getRecords(SCPConstants.laterType);
      _isInLater = records.any((r) => r.link == _cleanLink);
      _laterChecked = true;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _toggleLater() async {
    if (!_laterChecked) await _checkLaterStatus();
    if (_isInLater) {
      await DatabaseHelper.removeRecord(_cleanLink);
      _isInLater = false;
      _snack('已移出待读列表');
    } else {
      await DatabaseHelper.addRecord(_cleanLink, widget.title, SCPConstants.laterType);
      _isInLater = true;
      _snack('已加入待读列表');
    }
    if (mounted) setState(() {});
  }

  /// 打开 AI 助手(上下文 = 当前文档纯文本,配色跟随阅读主题)
  void _openAiAssistant() {
    final html = _detailHtml;
    if (html == null || html.isEmpty) {
      _snack('内容尚未加载');
      return;
    }
    final pal = _ReadingPalette.of(
        PreferenceService.getReadingTheme(), Theme.of(context).brightness);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatPage(
          docTitle: widget.title,
          articleText: ArticleText.extract(html),
          bg: pal.bgColor,
          fg: pal.fgColor,
          border: pal.borderColor,
          dark: pal.isDarkTheme,
        ),
      ),
    );
  }

  void _openInBrowser() async {
    final url = '${SCPConstants.scpSiteUrl}/$_cleanLink';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: '${SCPConstants.scpSiteUrl}/${widget.link}'));
    _snack('链接已复制');
  }
  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _jumpToTop() async {
    if (_webController != null) {
      try {
        await _webController!.runJavaScript('window.scrollTo({top:0,behavior:"smooth"})');
      } catch (_) {
        await _webController!.scrollTo(0, 0);
      }
    }
  }

  // ═══ 构建 ═══

  @override
  Widget build(BuildContext context) {
    final fullScreen = PreferenceService.getFullScreen();
    final pal = _ReadingPalette.of(PreferenceService.getReadingTheme(), Theme.of(context).brightness);
    return Scaffold(
      backgroundColor: pal.bgColor,
      appBar: fullScreen ? null : AppBar(
        backgroundColor: pal.bgColor,
        foregroundColor: pal.fgColor,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_toc.length >= 2)
            IconButton(icon: const Icon(Icons.list_alt, size: 20), tooltip: '目录', onPressed: _showToc),
          if (AiSettingsStore.available(AiSettingsStore.reload()))
            IconButton(icon: const Icon(Icons.auto_awesome, size: 20), tooltip: 'AI 助手', onPressed: _openAiAssistant),
          IconButton(icon: const Icon(Icons.settings, size: 20), tooltip: '阅读设置', onPressed: _showSettings),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'like': _toggleLike(); break;
                case 'later': _toggleLater(); break;
                case 'refresh':
                  setState(() { _loading = true; _detailHtml = null; _webController = null; });
                  _loadData();
                  break;
                case 'browser': _openInBrowser(); break;
                case 'copy': _copyLink(); break;
                case 'read': _markRead(); break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'like', child: Row(children: [
                Icon(_isLiked ? Icons.favorite : Icons.favorite_border, size: 20, color: Theme.of(ctx).colorScheme.onSurface),
                const SizedBox(width: 8), Text(_isLiked ? '取消收藏' : '收藏'),
              ])),
              PopupMenuItem(value: 'later', child: Row(children: [
                Icon(Icons.bookmark_border, size: 20, color: Theme.of(ctx).colorScheme.onSurface), SizedBox(width: 8), Text(_isInLater ? '移出待读' : '加入待读'),
              ])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'refresh', child: Row(children: [
                Icon(Icons.refresh, size: 20, color: Theme.of(ctx).colorScheme.onSurface), SizedBox(width: 8), Text('刷新'),
              ])),
              PopupMenuItem(value: 'browser', child: Row(children: [
                Icon(Icons.open_in_browser, size: 20, color: Theme.of(ctx).colorScheme.onSurface), SizedBox(width: 8), Text('浏览器打开'),
              ])),
              PopupMenuItem(value: 'copy', child: Row(children: [
                Icon(Icons.copy, size: 20, color: Theme.of(ctx).colorScheme.onSurface), SizedBox(width: 8), Text('复制链接'),
              ])),
              if (!_isRead) PopupMenuItem(value: 'read', child: Row(children: [
                Icon(Icons.check_circle_outline, size: 20, color: Theme.of(ctx).colorScheme.onSurface), SizedBox(width: 8), Text('标记已读'),
              ])),
              if (_isRead) PopupMenuItem(value: 'read', child: Row(children: [
                Icon(Icons.undo, size: 20, color: Theme.of(ctx).colorScheme.onSurface), SizedBox(width: 8), Text('取消已读'),
              ])),
            ],
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70 : null))
          : _detailHtml == null || _detailHtml!.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white30 : Colors.grey),
                    const SizedBox(height: 16),
                    Text('无法加载内容',
                        style: TextStyle(color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white54 : Colors.grey.shade600)),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: () {
                          setState(() { _loading = true; _detailHtml = null; });
                          _loadData();
                        },
                        label: const Text('刷新'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(onPressed: _openInBrowser, child: const Text('在浏览器中打开')),
                    ]),
                  ],
                ))
              : _webController != null
                  ? Stack(children: [
                      WebViewWidget(controller: _webController!),
                      if (_readingPct >= 0)
                        Positioned(
                          top: fullScreen ? MediaQuery.of(context).padding.top + 8 : 8,
                          left: 12,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$_readingPct%',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ),
                        ),
                      if (PreferenceService.getFullScreen())
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 8,
                          right: 12,
                          child: _buildExitBtn(),
                        ),
                      if (PreferenceService.getFullScreen() && _toc.length >= 2)
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 8,
                          right: 56,
                          child: _buildTocBtn(),
                        ),
                    ])
                  : const Center(child: Text('加载中...')),
      bottomNavigationBar: fullScreen ? null : _buildBottomBar(context),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pal = _ReadingPalette.of(PreferenceService.getReadingTheme(), Theme.of(context).brightness);
    return Container(
      decoration: BoxDecoration(
        color: pal.bgColor,
        border: Border(top: BorderSide(color: pal.borderColor)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _btn(Icons.favorite_outlined, _isLiked ? Colors.red : null, '收藏', _toggleLike),
              _btn(Icons.bookmark_border, null, '待读', _toggleLater),
              if (!_isRead)
                TextButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text('已读', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : null)),
                    onPressed: _markRead),
              if (_isRead)
                TextButton.icon(
                    icon: const Icon(Icons.undo, size: 18),
                    label: Text('取消已读', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : null)),
                    onPressed: _markRead),
              _btn(Icons.vertical_align_top, null, '顶部', _jumpToTop),
              _btn(Icons.settings, null, '设置', _showSettings),
              if (_autoScrolling)
                _btn(Icons.pause, Colors.orange, '暂停', () { _stopAutoScroll(); setState(() {}); }),
              if (!_autoScrolling && PreferenceService.getAutoScroll())
                _btn(Icons.play_arrow, Colors.green, '自动滚动', () { _startAutoScroll(PreferenceService.getAutoScrollSpeed()); setState(() {}); }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(IconData icon, Color? color, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 20, color: color),
      onPressed: onTap, tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36), padding: EdgeInsets.zero,
    );
  }
}

/// 阅读主题调色板 — WebView 内容与 Flutter 外壳（背景/AppBar/底栏/浮窗）共用，
/// 避免 sepia/纯黑等阅读主题下页面四周仍是系统主题颜色的割裂感
class _ReadingPalette {
  final bool isDarkTheme;
  // WebView CSS 用
  final String bgHex, textHex, linkHex, blockBgHex, blockBorderHex, secHex, headingHex, codeBgHex;
  // 脚注弹窗（此前硬编码深色，浅色主题下突兀）
  final String fnBgHex, fnTextHex, fnBorderHex;
  // Flutter 外壳用
  final Color bgColor, fgColor, borderColor;

  const _ReadingPalette({
    required this.isDarkTheme,
    required this.bgHex,
    required this.textHex,
    required this.linkHex,
    required this.blockBgHex,
    required this.blockBorderHex,
    required this.secHex,
    required this.headingHex,
    required this.codeBgHex,
    required this.fnBgHex,
    required this.fnTextHex,
    required this.fnBorderHex,
    required this.bgColor,
    required this.fgColor,
    required this.borderColor,
  });

  /// [rt] 阅读主题 (0=auto 1=light 2=sepia 3=dark 4=pure_dark)
  static _ReadingPalette of(int rt, Brightness systemBrightness) {
    final useSepia = rt == 2;
    final useDark = rt == 3 || rt == 4 || (rt == 0 && systemBrightness == Brightness.dark);
    final usePureDark = rt == 4;
    if (useSepia) {
      return const _ReadingPalette(
        isDarkTheme: false,
        bgHex: '#f5eedd', textHex: '#5b4636', linkHex: '#8b6914',
        blockBgHex: '#ede4c8', blockBorderHex: '#d8cdb0',
        secHex: '#8a7a6a', headingHex: '#3d2e1e', codeBgHex: '#e8dfc4',
        fnBgHex: '#fbf6ea', fnTextHex: '#5b4636', fnBorderHex: '#d8cdb0',
        bgColor: Color(0xFFF5EEDD), fgColor: Color(0xFF5B4636), borderColor: Color(0xFFD8CDB0),
      );
    }
    if (useDark) {
      return _ReadingPalette(
        isDarkTheme: true,
        bgHex: usePureDark ? '#000000' : '#16162a',
        textHex: '#d4d4d8', linkHex: '#7ec8f0',
        blockBgHex: usePureDark ? '#1a1a1a' : '#22223a',
        blockBorderHex: usePureDark ? '#2a2a2a' : '#3a3a52',
        secHex: '#9898b0', headingHex: '#e8e8ee',
        codeBgHex: usePureDark ? '#252525' : '#2e2e48',
        fnBgHex: usePureDark ? '#1f1f1f' : '#26263e',
        fnTextHex: '#e4e4e8',
        fnBorderHex: usePureDark ? '#333333' : '#3a3a52',
        bgColor: usePureDark ? const Color(0xFF000000) : const Color(0xFF16162A),
        fgColor: const Color(0xFFD4D4D8),
        borderColor: usePureDark ? const Color(0xFF2A2A2A) : const Color(0xFF3A3A52),
      );
    }
    return const _ReadingPalette(
      isDarkTheme: false,
      bgHex: '#ffffff', textHex: '#333333', linkHex: '#1565c0',
      blockBgHex: '#f5f5f7', blockBorderHex: '#e0e0e0',
      secHex: '#888', headingHex: '#222', codeBgHex: '#eef0f4',
      fnBgHex: '#ffffff', fnTextHex: '#333333', fnBorderHex: '#c9c9c9',
      bgColor: Colors.white, fgColor: Color(0xFF333333), borderColor: Color(0xFFE0E0E0),
    );
  }
}

/// 文档目录条目（由页面内 JS 采集 h1-h3 后上报）
class _TocItem {
  final int level; // 1=h1 2=h2 3=h3
  final String text;
  final String id; // 元素 id，交给 window.__tocGo 滚动定位

  const _TocItem({required this.level, required this.text, required this.id});
}
