import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/backend/backend_service.dart';
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
  Timer? _autoScrollTimer;
  bool _autoScrolling = false;
  Timer? _positionTimer;
  bool _positionRestored = false;
  double? _pendingScrollY; // 页面加载完成后要恢复的滚动位置

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

  /// HTML安全的简繁转换 — 只转换标签外文本，自动检测是否为繁体
  String _htmlSafeConvert(String html) {
    // 先检测是否已经是繁体
    if (_isTraditionalText(html)) {
      return html; // 已经是繁体，跳过转换
    }
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
        buf.write(ChineseConverter.toTraditional(html.substring(i, j)));
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
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
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
    if (PreferenceService.getHanzType() == 1) {
      content = _htmlSafeConvert(content);
    }

    String imgCss = showImg ? '' : 'img, video, iframe, canvas { display: none !important; }';
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
    final int rt = PreferenceService.getReadingTheme();
    // 颜色方案: 0=auto 1=light 2=sepia 3=dark 4=pure_dark
    bool useDark = rt == 3 || rt == 4 || (rt == 0 && isDark);
    bool usePureDark = rt == 4;
    bool useSepia = rt == 2;
    String bgColor, textColor, linkColor, blockBg, blockBorder, secColor, headingColor, inlineCodeBg;
    String colorSchemeMeta = '';
    if (useSepia) {
      bgColor = '#f5eedd'; textColor = '#5b4636'; linkColor = '#8b6914';
      blockBg = '#ede4c8'; blockBorder = '#d8cdb0'; secColor = '#8a7a6a';
      headingColor = '#3d2e1e'; inlineCodeBg = '#e8dfc4';
    } else if (useDark) {
      bgColor = usePureDark ? '#000000' : '#16162a';
      textColor = '#d4d4d8'; linkColor = '#7ec8f0';
      blockBg = usePureDark ? '#1a1a1a' : '#22223a';
      blockBorder = usePureDark ? '#2a2a2a' : '#3a3a52';
      secColor = '#9898b0'; headingColor = '#e8e8ee';
      inlineCodeBg = usePureDark ? '#252525' : '#2e2e48';
      colorSchemeMeta = '<meta name="color-scheme" content="dark">';
    } else {
      bgColor = '#ffffff'; textColor = '#333333'; linkColor = '#1565c0';
      blockBg = '#f5f5f7'; blockBorder = '#e0e0e0'; secColor = '#888';
      headingColor = '#222'; inlineCodeBg = '#eef0f4';
    }
    String darkFixJs = isDark ? '''
window.addEventListener('DOMContentLoaded',function(){
  setTimeout(function(){
    var bodyBg=getComputedStyle(document.body).backgroundColor;
    function isDarkBg(c){var m=c.match(/\\d+/g);if(!m||m.length<3)return false;
      var r=parseInt(m[0]),g=parseInt(m[1]),b=parseInt(m[2]);
      return 0.2126*r/255+0.7152*g/255+0.0722*b/255<0.35;}
    if(!isDarkBg(bodyBg))return;
    function lum(r,g,b){return 0.2126*r/255+0.7152*g/255+0.0722*b/255;}
    document.querySelectorAll('*').forEach(function(el){
      if(el.nodeType!==1)return;
      var t=el.tagName;if(t==='A'||t==='IMG'||t==='INPUT'||t==='BUTTON'||t==='SELECT'||t==='SCRIPT'||t==='STYLE')return;
      if(el.closest('a')||el.closest('pre')||el.closest('code'))return;
      var bg=getComputedStyle(el).backgroundColor;
      if(bg&&bg!=='rgba(0, 0, 0, 0)'&&bg!=='transparent'&&isDarkBg(bg)===isDarkBg(bodyBg))return;
      var cl=getComputedStyle(el).color;
      var m=cl.match(/\\d+/g);if(!m||m.length<3)return;
      var r=parseInt(m[0]),g=parseInt(m[1]),b=parseInt(m[2]);
      if(lum(r,g,b)<0.35)el.style.setProperty('color','$textColor','important');
    });
  },150);
});
''' : '';

    final html = '''
<!DOCTYPE html><html><head>
$colorSchemeMeta
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=3,user-scalable=yes">
$customFontFaces
<style>
  * { -webkit-tap-highlight-color: transparent; box-sizing: border-box; }
  html { scroll-behavior: smooth; }
  body {
    font-family: $fontFamilyCss;
    font-size: ${ts}px; line-height: ${PreferenceService.getLineHeight()};
    font-weight: ${[400, 500, 600, 700][PreferenceService.getFontWeight()]};
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
    max-width: 100%; height: auto;
    border-radius: 8px; margin: 12px 0;
    box-shadow: 0 1px 4px rgba(0,0,0,0.08);
  }
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
  .scp-image-block { float: right; margin: 0 0 12px 20px; max-width: 300px; }
  .scp-image-caption {
    display: block; font-size: 0.85em; color: $secColor;
    text-align: center; padding: 6px 0;
  }
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
  .rating span, .odialog-shader, .yui-navset {
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
    position: fixed; left: 0; right: 0; height: 1px;
    background: $linkColor; opacity: 0; pointer-events: none;
    z-index: 99997; transition: opacity 0.3s ease;
  }
  #_ruler.show { opacity: 0.35; }
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after { transition-duration: 0.01ms !important; }
  }
</style>
<script>
// ── 初始化（页面加载时执行）──
(function(){
  var prog = document.getElementById('_progress');
  var ruler = document.getElementById('_ruler');
  var rulerOn = ${PreferenceService.getReadingRuler() ? 'true' : 'false'};

  // reading progress bar
  var ticking = false;
  function updateProgress(){
    var h = document.documentElement.scrollHeight - window.innerHeight;
    if(h<=0)return;
    var p = Math.min(100, (window.scrollY/h)*100);
    prog.style.width = p+'%';
  }
  window.addEventListener('scroll',function(){
    if(!ticking){ requestAnimationFrame(function(){ updateProgress(); ticking=false; }); ticking=true; }
  },{passive:true});
  updateProgress();

  // reading ruler
  function updateRuler(){
    if(!ruler)return;
    if(rulerOn){
      ruler.className='show';
      ruler.style.top=(window.scrollY+window.innerHeight*0.48)+'px';
    }else{ruler.className='';}
  }
  window.addEventListener('scroll',updateRuler,{passive:true});
  updateRuler();

})();// ── 点击事件 ──
document.addEventListener('click',function(e){
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
        pop.style.cssText='position:absolute;z-index:99999;background:#333;color:#eee;padding:10px 14px 12px;border-radius:8px;font-size:13px;line-height:1.6;box-shadow:0 4px 24px rgba(0,0,0,0.6);max-width:88vw;pointer-events:auto;';
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

  void _startAutoScroll(double speed) {
    _stopAutoScroll();
    _autoScrolling = true;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      if (!_autoScrolling || _webController == null) return;
      try {
        await _webController!.scrollBy(0, (speed * 3).ceil());
      } catch (_) {
        _stopAutoScroll();
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrolling = false;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
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

  void _openInBrowser() async {
    final url = '${SCPConstants.scpSiteUrl}/${widget.link}';
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
      await _webController!.scrollTo(0, 0);
    }
  }

  // ═══ 构建 ═══

  @override
  Widget build(BuildContext context) {
    final fullScreen = PreferenceService.getFullScreen();
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1a1a2e) : Colors.white,
      appBar: fullScreen ? null : AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.settings, size: 20), tooltip: '阅读设置', onPressed: _showSettings),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'like': _toggleLike(); break;
                case 'later': _toggleLater(); break;
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
                    ElevatedButton(onPressed: _openInBrowser, child: const Text('在浏览器中打开')),
                  ],
                ))
              : _webController != null
                  ? Stack(children: [
                      WebViewWidget(controller: _webController!),
                      if (PreferenceService.getFullScreen())
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 8,
                          right: 12,
                          child: _buildExitBtn(),
                        ),
                    ])
                  : const Center(child: Text('加载中...')),
      bottomNavigationBar: fullScreen ? null : _buildBottomBar(context),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1a1a2e) : null,
        border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
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
