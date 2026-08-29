import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// 从 Wikidot 页面 HTML 提取纯文本,供 AI 上下文使用
class ArticleText {
  /// 提取正文纯文本。优先取 #page-content;剥离脚本/样式/评分/页脚导航等噪音。
  static String extract(String html) {
    final doc = html_parser.parse(html);
    Element? root;
    try {
      root = doc.querySelector('#page-content');
    } catch (_) {}
    root ??= doc.body;
    if (root == null) return '';

    const noise = [
      'script', 'style', 'noscript', 'iframe',
      '.page-rate-widget-box', '.footer-wikiwalk-nav', '.page-tags',
      '#page-info', '#licensebox', '.anom-bar', '.creditRate',
    ];
    for (final sel in noise) {
      try {
        root.querySelectorAll(sel).forEach((e) => e.remove());
      } catch (_) {}
    }

    final out = _Out(buf: StringBuffer());
    _walk(root, out);
    return _clean(out.buf.toString());
  }

  /// 渲染提示词模板:{title} → 标题,{content} → 正文
  static String renderPrompt(String template, {required String title, required String content}) {
    return template.replaceAll('{title}', title).replaceAll('{content}', content);
  }

  /// 中段截断:保留开头 60% + 结尾 40%,中间以省略标记替代
  static String truncateMiddle(String text, int maxChars) {
    if (maxChars <= 0 || text.length <= maxChars) return text;
    const marker = '\n\n……[正文过长,中间部分已省略]……\n\n';
    final keep = maxChars - marker.length;
    if (keep <= 0) return text.substring(0, maxChars);
    final head = (keep * 0.6).floor();
    final tail = keep - head;
    return '${text.substring(0, head)}$marker${text.substring(text.length - tail)}';
  }

  // ── 内部 ──

  static const _blockTags = {
    'address', 'article', 'aside', 'blockquote', 'center', 'details', 'dd', 'div',
    'dl', 'dt', 'fieldset', 'figcaption', 'figure', 'footer', 'form', 'h1', 'h2',
    'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main', 'nav', 'ol', 'p', 'pre',
    'section', 'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'ul',
  };

  static void _walk(Node n, _Out out) {
    if (n is Text) {
      out.write(n.text);
      return;
    }
    if (n is Element) {
      final tag = n.localName ?? '';
      if (tag == 'br') {
        out.buf.write('\n');
        out.lastNl = true;
        return;
      }
      final block = _blockTags.contains(tag);
      if (block && !out.lastNl) {
        out.buf.write('\n');
        out.lastNl = true;
      }
      for (final c in n.nodes) {
        _walk(c, out);
      }
      if (block && !out.lastNl) {
        out.buf.write('\n');
        out.lastNl = true;
      }
    }
  }

  static String _clean(String s) {
    final lines = s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ').trimRight());
    final out = <String>[];
    int blanks = 0;
    for (final l in lines) {
      if (l.isEmpty) {
        blanks++;
        if (blanks > 1) continue;
      } else {
        blanks = 0;
      }
      out.add(l);
    }
    return out.join('\n').trim();
  }
}

class _Out {
  final StringBuffer buf;
  bool lastNl = true;
  _Out({required this.buf});
  void write(String s) {
    if (s.isEmpty) return;
    buf.write(s);
    lastNl = s.endsWith('\n');
  }
}
