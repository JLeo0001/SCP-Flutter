import 'dart:convert';
import 'package:flutter/services.dart';

/// 简繁转换器 — 基于 OpenCC 官方词典（Apache-2.0）
///
/// 词典文件（assets/data/，来自 BYVoid/OpenCC 发布版 opencc-data 1.4.1）：
///   - TSCharacters.txt / TSPhrases.txt  : 繁→简（单字 + 短语）
///   - STCharacters.txt / STPhrases.txt  : 简→繁（单字 + 短语）
/// 算法与 OpenCC 标准配置一致：先做短语最长匹配（forward maximum matching），
/// 未命中短语时再查单字词典；多值条目取第一个映射（OpenCC 默认行为）。
class ChineseConverter {
  static const _assetDir = 'assets/data';

  // 繁→简
  static Map<String, String>? _t2sChars;
  static Map<String, String>? _t2sPhrases;
  // 简→繁
  static Map<String, String>? _s2tChars;
  static Map<String, String>? _s2tPhrases;

  static int _maxPhraseLen = 1;
  static Set<String>? _phraseStarts;
  static bool _loaded = false;
  static Future<void>? _loading;

  /// 确保词典已加载（幂等；首次调用异步解析，之后直接返回）。
  /// 使用转换前先 await 一次。
  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      _t2sPhrases = await _loadDict('$_assetDir/TSPhrases.txt');
      _t2sChars = await _loadDict('$_assetDir/TSCharacters.txt');
      _s2tPhrases = await _loadDict('$_assetDir/STPhrases.txt');
      _s2tChars = await _loadDict('$_assetDir/STCharacters.txt');

      final starts = <String>{};
      for (final map in [_t2sPhrases!, _s2tPhrases!]) {
        for (final key in map.keys) {
          if (key.length > _maxPhraseLen) _maxPhraseLen = key.length;
          starts.add(key[0]);
        }
      }
      _phraseStarts = starts;
      _loaded = true;
    } finally {
      _loading = null;
    }
  }

  /// 解析 OpenCC 词典文本：`key\tvalue1 value2 ...`，取第一个映射。
  static Future<Map<String, String>> _loadDict(String path) async {
    final text = await rootBundle.loadString(path);
    final map = <String, String>{};
    final lines = const LineSplitter().convert(text);
    for (final line in lines) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final key = line.substring(0, tab);
      final rest = line.substring(tab + 1);
      final sp = rest.indexOf(' ');
      map[key] = sp == -1 ? rest : rest.substring(0, sp);
    }
    return map;
  }

  static String toTraditional(String text) {
    if (!_loaded) return text;
    return _convert(text, _s2tPhrases!, _s2tChars!);
  }

  static String toSimplified(String text) {
    if (!_loaded) return text;
    return _convert(text, _t2sPhrases!, _t2sChars!);
  }

  static String _convert(
      String text, Map<String, String> phrases, Map<String, String> chars) {
    final buf = StringBuffer();
    final starts = _phraseStarts!;
    final n = text.length;
    int i = 0;
    while (i < n) {
      // 短语最长匹配：只有当前字符能作为某条短语开头时才扫描
      if (starts.contains(text[i])) {
        final maxTry = (n - i) < _maxPhraseLen ? (n - i) : _maxPhraseLen;
        String? hit;
        for (int l = maxTry; l >= 2; l--) {
          final v = phrases[text.substring(i, i + l)];
          if (v != null) {
            hit = v;
            buf.write(v);
            i += l;
            break;
          }
        }
        if (hit != null) continue;
      }
      // 单字兜底
      final c = text[i];
      buf.write(chars[c] ?? c);
      i++;
    }
    return buf.toString();
  }
}
