import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/services/preference_service.dart';
import '../../core/utils/permissions.dart';

/// 阅读设置变更类型
/// 阅读设置变更类型
enum SettingChange {
  visual,   // 所有视觉变更 → 需要重载WebView
  toggle,   // 自动滚动/常亮/全屏 → 直接应用
}

/// 阅读主题预设
class ReadingTheme {
  static const int auto = 0;
  static const int light = 1;
  static const int sepia = 2;
  static const int dark = 3;
  static const int pureDark = 4;

  static const labels = ['跟随系统', '浅色', '护眼', '深色', '纯黑'];
  static const icons = [
    Icons.brightness_auto, Icons.light_mode,
    Icons.wb_sunny_outlined, Icons.dark_mode, Icons.nightlight_round,
  ];
}

class FontWeightOption {
  static const int normal = 0;
  static const int medium = 1;
  static const int semibold = 2;
  static const int bold = 3;
  static const labels = ['正常', '中等', '半粗', '加粗'];
  static const values = [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700];
}

class BlockquoteStyle {
  static const int accent = 0;
  static const int subtle = 1;
  static const int modern = 2;
  static const labels = ['强调', '柔和', '现代'];
  static const icons = [Icons.format_quote_outlined, Icons.format_quote, Icons.auto_awesome];
}

/// 阅读设置面板 — 底部弹出增强版
class ReadingSettingsPanel extends StatefulWidget {
  final void Function(SettingChange type) onChanged;

  const ReadingSettingsPanel({super.key, required this.onChanged});

  @override
  State<ReadingSettingsPanel> createState() => _ReadingSettingsPanelState();
}

class _ReadingSettingsPanelState extends State<ReadingSettingsPanel> {
  // 字体
  double _textSize = 16;
  int _fontFamily = 0;
  double _lineHeight = 1.8;
  int _fontWeight = 0;
  double _codeFontScale = 0.9;
  double _headingScale = 1.0;
  static const _presetSizes = [14, 16, 18, 22];

  // 阅读主题
  int _readingTheme = 0;

  // 布局
  int _textAlign = 1;
  double _paraSpacing = 1.0;
  int _pagePadding = 1;
  bool _firstLineIndent = false;
  int _blockquoteStyle = 0;
  int _imageWidth = 0;

  // 功能
  bool _showImages = true;
  int _hanzType = 0;
  bool _autoScroll = false;
  double _autoSpeed = 2.0;
  bool _keepScreenOn = false;
  bool _fullScreen = false;
  bool _readingRuler = false;

  // 自定义字体
  List<String> _customFontNames = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _textSize = double.tryParse(PreferenceService.getDetailTextSize().replaceAll('px', '')) ?? 16;
    _fontFamily = PreferenceService.getFontFamily();
    _lineHeight = PreferenceService.getLineHeight();
    _fontWeight = PreferenceService.getFontWeight();
    _codeFontScale = PreferenceService.getCodeFontScale();
    _headingScale = PreferenceService.getHeadingScale();
    _readingTheme = PreferenceService.getReadingTheme();
    _textAlign = PreferenceService.getTextAlign();
    _paraSpacing = PreferenceService.getParagraphSpacing();
    _pagePadding = PreferenceService.getPagePadding();
    _firstLineIndent = PreferenceService.getFirstLineIndent();
    _blockquoteStyle = PreferenceService.getBlockquoteStyle();
    _imageWidth = PreferenceService.getImageWidth();
    _showImages = PreferenceService.getShowImages();
    _hanzType = PreferenceService.getHanzType();
    _autoScroll = PreferenceService.getAutoScroll();
    _autoSpeed = PreferenceService.getAutoScrollSpeed();
    _keepScreenOn = PreferenceService.getKeepScreenOn();
    _fullScreen = PreferenceService.getFullScreen();
    _readingRuler = PreferenceService.getReadingRuler();
    _customFontNames = PreferenceService.customFontNameList;
  }

  /// 扫描外部字体目录（优先 /sdcard/Fonts）
  Future<void> _scanFonts() async {
    // 先申请权限
    final hasPermission = await requestStoragePermission();
    
    final dirs = <String>[];
    if (hasPermission) {
      dirs.addAll(['/sdcard/Fonts', '/storage/emulated/0/Fonts']);
    }
    // 备用：外部存储目录
    try {
      final extDirs = await getExternalStorageDirectories();
      if (extDirs != null) {
        for (final d in extDirs) {
          dirs.add('${d.path}/Fonts');
          break;
        }
      }
    } catch (_) {}

    final names = <String>[];
    final paths = <String>[];
    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list()) {
          final path = entity.path.toLowerCase();
          if (path.endsWith('.ttf') || path.endsWith('.otf')) {
            names.add(entity.path.split('/').last.replaceAll(RegExp(r'\.(ttf|otf)$', caseSensitive: false), ''));
            paths.add(entity.path);
          }
        }
      } catch (_) {}
    }
    if (names.isEmpty) {
      final msg = hasPermission
          ? '未在 /sdcard/Fonts/ 找到字体'
          : '需要存储权限才能扫描字体，请在设置中授予';
      _snack(msg);
      return;
    }
    setState(() { _customFontNames = names; });
    PreferenceService.setCustomFontNames(names.join('|'));
    PreferenceService.setCustomFontPaths(paths.join('|'));
    _snack('找到 ${names.length} 个字体');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _saveVisual() {
    PreferenceService.setDetailTextSize('${_textSize.toInt()}px');
    PreferenceService.setFontFamily(_fontFamily);
    PreferenceService.setLineHeight(_lineHeight);
    PreferenceService.setFontWeight(_fontWeight);
    PreferenceService.setCodeFontScale(_codeFontScale);
    PreferenceService.setHeadingScale(_headingScale);
    PreferenceService.setReadingTheme(_readingTheme);
    PreferenceService.setTextAlign(_textAlign);
    PreferenceService.setParagraphSpacing(_paraSpacing);
    PreferenceService.setPagePadding(_pagePadding);
    PreferenceService.setFirstLineIndent(_firstLineIndent);
    PreferenceService.setBlockquoteStyle(_blockquoteStyle);
    PreferenceService.setImageWidth(_imageWidth);
    PreferenceService.setShowImages(_showImages);
    PreferenceService.setHanzType(_hanzType);
    PreferenceService.setReadingRuler(_readingRuler);
    widget.onChanged(SettingChange.visual);
  }

  void _saveToggle() {
    PreferenceService.setAutoScroll(_autoScroll);
    PreferenceService.setAutoScrollSpeed(_autoSpeed);
    PreferenceService.setKeepScreenOn(_keepScreenOn);
    PreferenceService.setFullScreen(_fullScreen);
    widget.onChanged(SettingChange.toggle);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          // ── 拖拽条 ──
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('阅读设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 20),

          // ═══ 阅读主题 ═══
          _sectionTitle('阅读主题', cs),
          Wrap(spacing: 8, runSpacing: 8, children: List.generate(ReadingTheme.labels.length, (i) {
            final active = _readingTheme == i;
            return ChoiceChip(
              avatar: Icon(ReadingTheme.icons[i], size: 16, color: active ? cs.onPrimaryContainer : null),
              label: Text(ReadingTheme.labels[i], style: const TextStyle(fontSize: 12)),
              selected: active,
              selectedColor: cs.primaryContainer,
              onSelected: (_) => setState(() { _readingTheme = i; _saveVisual(); }),
            );
          })),
          const SizedBox(height: 8), const Divider(height: 16),

          // ═══ 字号 ═══
          _sectionTitle('字号', cs),
          Row(children: [
            IconButton(onPressed: () => setState(() { _textSize = (_textSize - 2).clamp(12, 32); _saveVisual(); }), icon: const Icon(Icons.text_decrease)),
            Expanded(child: Slider(
              value: _textSize, min: 12, max: 32, divisions: 10,
              label: '${_textSize.toInt()}px',
              onChanged: (v) => setState(() => _textSize = v),
              onChangeEnd: (_) => _saveVisual(),
            )),
            IconButton(onPressed: () => setState(() { _textSize = (_textSize + 2).clamp(12, 32); _saveVisual(); }), icon: const Icon(Icons.text_increase)),
            SizedBox(width: 40, child: Text('${_textSize.toInt()}px', style: TextStyle(fontSize: 13, color: cs.onSurface))),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: _presetSizes.map((s) {
            final active = _textSize.toInt() == s;
            return SizedBox(width: 52, height: 30, child: OutlinedButton(
              onPressed: () => setState(() { _textSize = s.toDouble(); _saveVisual(); }),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero, backgroundColor: active ? cs.primaryContainer : null,
                side: BorderSide(color: active ? cs.primary : cs.outlineVariant),
              ), child: Text('$s', style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w600 : null)),
            ));
          }).toList()),
          const SizedBox(height: 4),

          // ═══ 字重 ═══
          _sectionTitle('字重', cs),
          Wrap(spacing: 6, children: List.generate(FontWeightOption.labels.length, (i) {
            final active = _fontWeight == i;
            return ChoiceChip(
              label: Text(FontWeightOption.labels[i], style: const TextStyle(fontSize: 12)),
              selected: active,
              selectedColor: cs.primaryContainer,
              onSelected: (_) => setState(() { _fontWeight = i; _saveVisual(); }),
            );
          })),

          // ═══ 字体 + 行高 ═══
          _sectionTitle('字体', cs),
          Wrap(spacing: 8, children: [
            ChoiceChip(
              label: Text('系统', style: const TextStyle(fontSize: 13)),
              selected: _fontFamily == 0,
              onSelected: (_) => setState(() { _fontFamily = 0; _saveVisual(); }),
            ),
            ActionChip(
              avatar: const Icon(Icons.folder_open, size: 16),
              label: Text('扫描', style: TextStyle(fontSize: 12, color: cs.primary)),
              onPressed: _scanFonts,
            ),
          ]),
          // 自定义字体列表（可折叠）
          if (_customFontNames.length > 6)
            _buildCollapsibleFonts(cs)
          else
            ...List.generate(_customFontNames.length, (i) => _fontChip(i, cs)),
          _sectionTitle('行高', cs),
          Row(children: [
            Expanded(child: Slider(
              value: _lineHeight, min: 1.2, max: 2.6, divisions: 14,
              label: _lineHeight.toStringAsFixed(1),
              onChanged: (v) => setState(() => _lineHeight = v),
              onChangeEnd: (_) => _saveVisual(),
            )),
            SizedBox(width: 40, child: Text(_lineHeight.toStringAsFixed(1), style: TextStyle(fontSize: 13, color: cs.onSurface))),
          ]),

          // ═══ 标题倍率 ═══
          _sectionTitle('标题大小', cs),
          Row(children: [
            const Text('×', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: Slider(
              value: _headingScale, min: 0.8, max: 1.6, divisions: 8,
              label: _headingScale.toStringAsFixed(1)+'x',
              onChanged: (v) => setState(() => _headingScale = v),
              onChangeEnd: (_) => _saveVisual(),
            )),
            SizedBox(width: 36, child: Text('${_headingScale.toStringAsFixed(1)}x', style: TextStyle(fontSize: 12, color: cs.onSurface))),
          ]),

          // ═══ 代码字号 ═══
          _sectionTitle('代码字号', cs),
          Row(children: [
            Expanded(child: Slider(
              value: _codeFontScale, min: 0.7, max: 1.3, divisions: 12,
              label: _codeFontScale.toStringAsFixed(1)+'x',
              onChanged: (v) => setState(() => _codeFontScale = v),
              onChangeEnd: (_) => _saveVisual(),
            )),
            SizedBox(width: 36, child: Text('${_codeFontScale.toStringAsFixed(1)}x', style: TextStyle(fontSize: 12, color: cs.onSurface))),
          ]),

          const Divider(height: 16),

          // ═══ 布局 ═══
          _sectionTitle('布局', cs),

          // 对齐
          Row(children: [
            Text('对齐', style: TextStyle(fontSize: 13, color: cs.onSurface)),
            const SizedBox(width: 12),
            Expanded(child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('左对齐', style: TextStyle(fontSize: 12)), icon: Icon(Icons.format_align_left, size: 16)),
                ButtonSegment(value: 1, label: Text('两端', style: TextStyle(fontSize: 12)), icon: Icon(Icons.format_align_justify, size: 16)),
              ], selected: {_textAlign},
              onSelectionChanged: (v) => setState(() { _textAlign = v.first; _saveVisual(); }),
            )),
          ]),
          const SizedBox(height: 8),

          // 段落间距
          Row(children: [
            Text('段距', style: TextStyle(fontSize: 13, color: cs.onSurface)),
            const SizedBox(width: 12),
            Expanded(child: Slider(
              value: _paraSpacing, min: 0.5, max: 2.5, divisions: 8,
              label: _paraSpacing.toStringAsFixed(1)+'x',
              onChanged: (v) => setState(() => _paraSpacing = v),
              onChangeEnd: (_) => _saveVisual(),
            )),
            SizedBox(width: 32, child: Text('${_paraSpacing.toStringAsFixed(1)}x', style: TextStyle(fontSize: 12, color: cs.onSurface))),
          ]),

          // 页面边距
          Row(children: [
            Text('边距', style: TextStyle(fontSize: 13, color: cs.onSurface)),
            const SizedBox(width: 12),
            Expanded(child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('窄', style: TextStyle(fontSize: 12)), icon: Icon(Icons.arrow_left, size: 16)),
                ButtonSegment(value: 1, label: Text('普通', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 2, label: Text('宽', style: TextStyle(fontSize: 12)), icon: Icon(Icons.arrow_right, size: 16)),
              ], selected: {_pagePadding},
              onSelectionChanged: (v) => setState(() { _pagePadding = v.first; _saveVisual(); }),
            )),
          ]),
          const SizedBox(height: 4),

          // 首行缩进
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: const Text('首行缩进', style: TextStyle(fontSize: 14)),
            subtitle: Text('中文阅读习惯，每段首行空两格', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
            value: _firstLineIndent,
            onChanged: (v) => setState(() { _firstLineIndent = v; _saveVisual(); }),
          ),

          // ═══ 引用块样式 ═══
          _sectionTitle('引用块样式', cs),
          Wrap(spacing: 8, children: List.generate(BlockquoteStyle.labels.length, (i) {
            final active = _blockquoteStyle == i;
            return ChoiceChip(
              avatar: Icon(BlockquoteStyle.icons[i], size: 16),
              label: Text(BlockquoteStyle.labels[i], style: const TextStyle(fontSize: 12)),
              selected: active,
              selectedColor: cs.primaryContainer,
              onSelected: (_) => setState(() { _blockquoteStyle = i; _saveVisual(); }),
            );
          })),

          // ═══ 图片宽度 ═══
          _sectionTitle('图片大小', cs),
          Wrap(spacing: 8, children: [
            _chip('全宽', 0, _imageWidth, (v) => setState(() { _imageWidth = v; _saveVisual(); }), cs),
            _chip('适中', 1, _imageWidth, (v) => setState(() { _imageWidth = v; _saveVisual(); }), cs),
            _chip('紧凑', 2, _imageWidth, (v) => setState(() { _imageWidth = v; _saveVisual(); }), cs),
          ]),

          const Divider(height: 16),

          // ═══ 功能 ═══
          _sectionTitle('功能', cs),

          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: const Text('显示图片', style: TextStyle(fontSize: 14)),
            value: _showImages,
            onChanged: (v) => setState(() { _showImages = v; _saveVisual(); }),
          ),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: const Text('阅读标尺', style: TextStyle(fontSize: 14)),
            subtitle: Text('横向参考线辅助阅读定位', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
            value: _readingRuler,
            onChanged: (v) => setState(() { _readingRuler = v; _saveVisual(); }),
          ),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: const Text('自动滚动', style: TextStyle(fontSize: 14)),
            subtitle: _autoScroll ? Row(children: [
              Text('速度', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
              Expanded(child: Slider(
                value: _autoSpeed, min: 0.5, max: 5.0, divisions: 9,
                onChanged: (v) => setState(() { _autoSpeed = v; _saveToggle(); }),
              )),
            ]) : null,
            value: _autoScroll,
            onChanged: (v) => setState(() { _autoScroll = v; _saveToggle(); }),
          ),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: const Text('屏幕常亮', style: TextStyle(fontSize: 14)),
            value: _keepScreenOn,
            onChanged: (v) => setState(() { _keepScreenOn = v; _saveToggle(); }),
          ),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: const Text('全屏阅读', style: TextStyle(fontSize: 14)),
            value: _fullScreen,
            onChanged: (v) => setState(() { _fullScreen = v; _saveToggle(); }),
          ),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: const Text('简繁切换', style: TextStyle(fontSize: 14)),
            subtitle: Text(_hanzType == 0 ? '简体' : '繁体', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
            value: _hanzType == 1,
            onChanged: (v) => setState(() { _hanzType = v ? 1 : 0; _saveVisual(); }),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int value, int current, ValueChanged<int> onTap, ColorScheme cs) {
    final active = current == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: active,
      selectedColor: cs.primaryContainer,
      onSelected: (_) => onTap(value),
    );
  }

  Widget _sectionTitle(String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.6))),
    );
  }

  /// 单个字体 chip
  Widget _fontChip(int index, ColorScheme cs) {
    final active = _fontFamily == 1 + index;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: ChoiceChip(
        label: Text(_customFontNames[index], style: const TextStyle(fontSize: 13)),
        selected: active,
        selectedColor: cs.primaryContainer,
        onSelected: (_) => setState(() { _fontFamily = 1 + index; _saveVisual(); }),
      ),
    );
  }

  /// 可折叠的字体列表（超过6个时）
  Widget _buildCollapsibleFonts(ColorScheme cs) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('自定义字体 (${_customFontNames.length}个)',
          style: TextStyle(fontSize: 13, color: cs.primary)),
      childrenPadding: const EdgeInsets.only(top: 4),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: List.generate(_customFontNames.length, (i) => _fontChip(i, cs)),
        ),
      ],
    );
  }
}
