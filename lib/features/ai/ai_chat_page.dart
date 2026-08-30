import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ai/ai_models.dart';
import '../../core/ai/ai_service.dart';
import '../../core/ai/article_text.dart';

/// AI 助手对话页 —— 快捷功能 + 自由对话,流式输出
///
/// 配色从阅读页传入(bg/fg/border),保证与当前阅读主题(含 sepia/纯黑)一致。
class AiChatPage extends StatefulWidget {
  final String docTitle;
  final String articleText; // 未截断的正文纯文本
  final Color bg;
  final Color fg;
  final Color border;
  final bool dark;
  final String? autoRunFeatureId; // 打开后立即执行的快捷功能(框选菜单直达用)

  const AiChatPage({
    super.key,
    required this.docTitle,
    required this.articleText,
    required this.bg,
    required this.fg,
    required this.border,
    required this.dark,
    this.autoRunFeatureId,
  });

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _Msg {
  final String role; // user | assistant
  final String display; // 气泡中显示的文本(功能调用时是模板预览,不含全文)
  String text; // 实际发送/流式累积的内容;user 消息也保存,供后续对话作为历史
  bool streaming;
  bool error = false;
  final List<String> notes = []; // 工具读取记录,如「读取文档 1–4000 / 12345 字」
  final _TurnRequest? req; // 生成参数,重新生成用

  _Msg({required this.role, required this.display, this.text = '', this.streaming = false, this.req});
}

/// 一次生成请求的完整参数(历史 + 模式),重新生成时原样重放
class _TurnRequest {
  final AiProviderConfig provider;
  final String? model;
  final String? system;
  final bool useTools;
  final List<AiMessage> messages;

  const _TurnRequest({
    required this.provider,
    this.model,
    this.system,
    required this.useTools,
    required this.messages,
  });
}

class _AiChatPageState extends State<AiChatPage> {
  late AiSettings _settings;
  final List<_Msg> _msgs = [];
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  StreamSubscription<String>? _sub;
  Timer? _flushTimer;
  CancelToken? _cancelToken;
  bool _generating = false;
  bool _stickBottom = true;
  int _genCount = 0; // 已完成/中止的生成次数

  /// 传给模型的文档上下文({title} / {content} 的实际取值)
  late String _ctxTitle;
  late String _ctxContent;

  @override
  void initState() {
    super.initState();
    _settings = AiSettingsStore.loadSync();
    _ctxTitle = _settings.includeTitle ? widget.docTitle : '';
    _ctxContent = ArticleText.truncateMiddle(widget.articleText, _settings.contextMaxChars);
    _scroll.addListener(() {
      final nearBottom = _scroll.position.maxScrollExtent - _scroll.position.pixels < 240;
      _stickBottom = nearBottom;
    });
    final auto = widget.autoRunFeatureId;
    if (auto != null && auto.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final f in _quickFeatures) {
          if (f.id == auto) {
            _runFeature(f);
            return;
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cancelToken?.isCancelled = true;
    _flushTimer?.cancel();
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── 数据 ──

  List<AiFeatureConfig> get _quickFeatures =>
      _settings.effectiveFeatures().where((f) => f.id != 'chat').toList();

  String _render(String tpl, {required bool useContext}) {
    if (!useContext) {
      return tpl.replaceAll('{title}', '').replaceAll('{content}', '');
    }
    return ArticleText.renderPrompt(tpl, title: _ctxTitle, content: _ctxContent);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || !_stickBottom) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  // ── 发送 ──

  /// 系统提示词:按功能的上下文模式渲染
  String? _systemFor(AiFeatureConfig f) {
    final sp = f.systemPrompt;
    switch (f.contextMode) {
      case 'none':
        final s = sp.replaceAll('{title}', '').replaceAll('{content}', '');
        return s.trim().isEmpty ? null : s;
      case 'tool':
        final s = _stripContentLines(sp);
        const note =
            '\n\n(文档正文未直接提供:需要正文内容时,请调用 read_document 工具分段读取;首次调用可不带参数。)';
        final out = (s + note).trim();
        return out.isEmpty ? null : out;
      default:
        return sp.trim().isEmpty ? null : _render(sp, useContext: f.useArticleContext);
    }
  }

  /// 去掉含 {content} 的行,{title} 按设置替换,折叠连续空行
  String _stripContentLines(String tpl) {
    final title = _settings.includeTitle ? widget.docTitle : '';
    final out = <String>[];
    for (final l in tpl.split('\n')) {
      if (l.contains('{content}')) continue;
      final t = l.replaceAll('{title}', title);
      if (t.trim().isEmpty && out.isNotEmpty && out.last.trim().isEmpty) continue;
      out.add(t);
    }
    return out.join('\n').trim();
  }

  /// 功能的用户消息(按上下文模式)
  String _featureUserContent(AiFeatureConfig f) {
    final tpl = f.userPromptTemplate.trim();
    switch (f.contextMode) {
      case 'none':
        return tpl.replaceAll('{title}', '').replaceAll('{content}', '');
      case 'tool':
        final base = _stripContentLines(tpl);
        return tpl.contains('{content}')
            ? '$base\n\n请先调用 read_document 工具读取文档,再完成任务。'
            : base;
      default:
        return _render(tpl, useContext: f.useArticleContext);
    }
  }

  void _runFeature(AiFeatureConfig f) {
    if (_generating) return;
    final provider = _settings.resolveFeatureProvider(f);
    if (provider == null || !provider.enabled) {
      _snack('「${f.name}」没有可用供应商,请到 AI 设置中检查');
      return;
    }
    final tpl = f.userPromptTemplate.trim();
    if (tpl.isEmpty) {
      _snack('「${f.name}」未配置提示词模板');
      return;
    }
    final content = _featureUserContent(f);
    final display = tpl.length > 160 ? '${tpl.substring(0, 160)}…' : tpl;
    _sendTurn(
      _TurnRequest(
        provider: provider,
        model: f.model.trim().isNotEmpty ? f.model.trim() : null,
        system: _systemFor(f),
        useTools: f.contextMode == 'tool' && widget.articleText.isNotEmpty,
        messages: [AiMessage(role: 'user', content: content)],
      ),
      userDisplay: display,
      userText: content,
    );
  }

  void _sendChat() {
    final text = _input.text.trim();
    if (text.isEmpty || _generating) return;
    final cap = _settings.chatCapability();
    if (cap == null) {
      _snack('请先在 AI 设置中配置并启用供应商');
      return;
    }
    _input.clear();
    // 历史:只保留最近 20 条,控制 token
    final history = <AiMessage>[];
    for (final m in _msgs) {
      if (m.error || m.text.trim().isEmpty) continue;
      history.add(AiMessage(role: m.role, content: m.text));
    }
    if (history.length > 20) history.removeRange(0, history.length - 20);
    _sendTurn(
      _TurnRequest(
        provider: cap.provider,
        model: cap.feature.model.trim().isNotEmpty ? cap.feature.model.trim() : null,
        system: _systemFor(cap.feature),
        useTools: cap.feature.contextMode == 'tool' && widget.articleText.isNotEmpty,
        messages: [...history, AiMessage(role: 'user', content: text)],
      ),
      userDisplay: text,
      userText: text,
    );
  }

  void _sendTurn(_TurnRequest req, {required String userDisplay, required String userText}) {
    _msgs.add(_Msg(role: 'user', display: userDisplay, text: userText));
    _beginAssistant(req);
  }

  /// 重新生成:去掉最后一条回复,按原参数重放
  void _regenerate(int index) {
    if (_generating || index <= 0) return;
    final m = _msgs[index];
    if (m.req == null) {
      _snack('该回复不支持重新生成');
      return;
    }
    setState(() => _msgs.removeRange(index, _msgs.length));
    _beginAssistant(m.req!);
  }

  void _beginAssistant(_TurnRequest req) {
    final assistant = _Msg(role: 'assistant', display: '', streaming: true, req: req);
    _msgs.add(assistant);
    _generating = true;
    _stickBottom = true;
    setState(() {});
    _scrollToBottom();

    // 节流刷新:delta 只写缓冲,定时统一 setState
    final buf = StringBuffer();
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (buf.isEmpty) return;
      assistant.text += buf.toString();
      buf.clear();
      setState(() {});
      _scrollToBottom();
    });

    final gen = ++_genCount;
    final token = CancelToken();
    _cancelToken = token;

    if (req.useTools) {
      // 工具模式:agent 循环(模型调用 read_document 读文档 → 回传 → 继续)
      () async {
        try {
          await AiService.instance.chatWithTools(
            req.provider,
            messages: req.messages,
            system: req.system,
            model: req.model,
            toolHandler: (call) async {
              final r = await _handleTool(call);
              if (gen == _genCount && mounted) {
                setState(() => assistant.notes.add(_toolNote(call, r)));
              }
              return r;
            },
            onDelta: buf.write,
            cancel: token,
          );
          if (gen != _genCount) return;
          _finishGeneration(assistant, buf);
        } on AiCancelled {
          if (gen != _genCount) return;
          _finishGeneration(assistant, buf, stopped: true);
        } on AiException catch (e) {
          if (gen != _genCount) return;
          _finishGeneration(assistant, buf, errorText: e.message);
        } catch (e) {
          if (gen != _genCount) return;
          _finishGeneration(assistant, buf, errorText: '请求失败: $e');
        }
      }();
    } else {
      _sub?.cancel();
      _sub = AiService.instance
          .stream(req.provider, messages: req.messages, system: req.system, model: req.model)
          .listen(
        (delta) {
          buf.write(delta);
        },
        onError: (Object e) {
          if (gen != _genCount) return;
          _finishGeneration(assistant, buf, errorText: e is AiException ? e.message : '请求失败: $e');
        },
        onDone: () {
          if (gen != _genCount) return;
          _finishGeneration(assistant, buf);
        },
        cancelOnError: true,
      );
    }
  }

  /// 执行 read_document:按 offset/length 切片返回
  Future<String> _handleTool(AiToolCall call) async {
    if (call.name != 'read_document') {
      return jsonEncode({'error': '未知工具: ${call.name}'});
    }
    Map<String, dynamic> args = {};
    try {
      final v = jsonDecode(call.arguments.isEmpty ? '{}' : call.arguments);
      if (v is Map<String, dynamic>) args = v;
    } catch (_) {}
    final full = widget.articleText;
    final total = full.length;
    if (total == 0) return jsonEncode({'total': 0, 'content': '', 'hasMore': false});
    final off = ((args['offset'] as num?)?.toInt() ?? 0).clamp(0, math.max(0, total - 1)).toInt();
    final len = ((args['length'] as num?)?.toInt() ?? 4000).clamp(200, 12000).toInt();
    final end = math.min(off + len, total);
    return jsonEncode({
      'total': total,
      'offset': off,
      'end': end,
      'hasMore': end < total,
      'content': full.substring(off, end),
    });
  }

  String _toolNote(AiToolCall call, String result) {
    try {
      final r = jsonDecode(result);
      if (r is Map<String, dynamic> && r['total'] is num) {
        final total = (r['total'] as num).toInt();
        final off = (r['offset'] as num?)?.toInt() ?? 0;
        final end = (r['end'] as num?)?.toInt() ?? 0;
        return '读取文档 ${off + 1}–$end / $total 字';
      }
    } catch (_) {}
    return '调用工具 ${call.name}';
  }

  void _finishGeneration(_Msg assistant, StringBuffer buf,
      {String? errorText, bool stopped = false}) {
    _flushTimer?.cancel();
    if (buf.isNotEmpty) assistant.text += buf.toString();
    assistant.streaming = false;
    if (errorText != null) {
      assistant.error = true;
      if (assistant.text.isEmpty) assistant.text = errorText;
      // 出错信息完整展示
      _snack(errorText);
    } else if (stopped && assistant.text.isEmpty) {
      assistant.text = '(已停止)';
    }
    _generating = false;
    _sub = null;
    _cancelToken = null;
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  void _stop() {
    if (!_generating) return;
    _genCount++;
    _sub?.cancel();
    _sub = null;
    _cancelToken?.isCancelled = true;
    _cancelToken = null;
    _flushTimer?.cancel();
    for (final m in _msgs) {
      if (m.streaming) {
        m.streaming = false;
        if (m.text.isEmpty) m.text = '(已停止)';
      }
    }
    _generating = false;
    setState(() {});
  }

  void _clear() {
    if (_generating) _stop();
    setState(_msgs.clear);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _snack('已复制');
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    final sub = fg.withValues(alpha: 0.55);
    final cap = _settings.chatCapability();
    final modeLabel = cap == null
        ? ''
        : cap.feature.contextMode == 'tool'
            ? ' · 工具读取'
            : cap.feature.contextMode == 'none'
                ? ' · 不带正文'
                : ' · 注入正文';
    return Scaffold(
        backgroundColor: widget.bg,
        appBar: AppBar(
          backgroundColor: widget.bg,
          foregroundColor: fg,
          elevation: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI 助手', style: TextStyle(fontSize: 16)),
            Text(
              cap == null
                  ? widget.docTitle
                  : '${widget.docTitle} · ${cap.provider.name}$modeLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: sub),
            ),
          ]),
          actions: [
            if (_msgs.isNotEmpty)
              IconButton(icon: const Icon(Icons.delete_sweep, size: 20), tooltip: '清空对话', onPressed: _clear),
          ],
        ),
        body: Column(
          children: [
            Divider(height: 1, color: widget.border),
            Expanded(
              child: _msgs.isEmpty ? _buildEmpty(sub) : _buildList(fg, sub),
            ),
            Divider(height: 1, color: widget.border),
            _buildQuickBar(sub),
            _buildInput(cap != null, fg, sub),
          ],
        ),
    );
  }

  Widget _buildEmpty(Color sub) {
    final feats = _quickFeatures;
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.auto_awesome, size: 40, color: sub),
        const SizedBox(height: 12),
        Text('已就绪', style: TextStyle(color: sub, fontSize: 13)),
        if (feats.isEmpty) ...[
          const SizedBox(height: 6),
          Text('在下方输入框向 AI 提问', style: TextStyle(color: sub, fontSize: 12)),
        ],
      ]),
    );
  }

  Widget _buildList(Color fg, Color sub) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: _msgs.length,
      itemBuilder: (ctx, i) {
        final m = _msgs[i];
        if (m.role == 'user') return _userBubble(m, fg);
        return _assistantBubble(m, fg, sub, i);
      },
    );
  }

  Widget _userBubble(_Msg m, Color fg) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8, left: 40),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: fg.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: fg.withValues(alpha: 0.15)),
          ),
          child: SelectableText(m.display, style: TextStyle(color: fg, fontSize: 14, height: 1.5)),
        ),
      ),
    );
  }

  Widget _assistantBubble(_Msg m, Color fg, Color sub, int index) {
    final body = m.streaming
        ? '${m.text}▌'
        : (m.text.isEmpty ? '…' : m.text);
    final isLast = index == _msgs.length - 1;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final n in m.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('🔧 $n', style: TextStyle(fontSize: 11, color: sub)),
          ),
        SelectableText(
          body,
          style: TextStyle(
            color: m.error ? Colors.red.shade300 : fg,
            fontSize: 14.5,
            height: 1.65,
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (!m.streaming && m.text.isNotEmpty && !m.error)
            _miniBtn(Icons.copy, '复制', sub, () => _copy(m.text)),
          if (isLast && !m.streaming && !m.error && !_generating && m.req != null)
            _miniBtn(Icons.refresh, '重新生成', sub, () => _regenerate(index)),
          if (m.streaming)
            Text('生成中…', style: TextStyle(fontSize: 11, color: sub)),
        ]),
      ]),
    );
  }

  Widget _miniBtn(IconData icon, String tip, Color color, VoidCallback onTap) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
      icon: Icon(icon, size: 15, color: color),
      tooltip: tip,
      onPressed: onTap,
    );
  }

  Widget _buildQuickBar(Color sub) {
    final feats = _quickFeatures;
    if (feats.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final f in feats)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: widget.border),
                backgroundColor: Colors.transparent,
                labelStyle: TextStyle(fontSize: 12.5, color: sub),
                label: Text(f.name),
                onPressed: _generating ? null : () => _runFeature(f),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInput(bool chatEnabled, Color fg, Color sub) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _inputFocus,
              enabled: chatEnabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendChat(),
              style: TextStyle(color: fg, fontSize: 14.5),
              cursorColor: fg,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: fg.withValues(alpha: 0.06),
                hintText: chatEnabled
                    ? (_generating ? '生成中,可先停止…' : '向 AI 提问…')
                    : '自由对话未启用(见 AI 设置)',
                hintStyle: TextStyle(color: sub, fontSize: 13.5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: widget.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: widget.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: sub),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: widget.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _input,
            builder: (ctx, v, _) {
              final active = _generating || (chatEnabled && v.text.trim().isNotEmpty);
              return IconButton.filled(
                onPressed: active ? (_generating ? _stop : _sendChat) : null,
                style: IconButton.styleFrom(
                  backgroundColor: active ? fg : fg.withValues(alpha: 0.15),
                  disabledBackgroundColor: fg.withValues(alpha: 0.15),
                ),
                icon: Icon(
                  _generating ? Icons.stop : Icons.send_rounded,
                  size: 18,
                  color: active ? widget.bg : sub,
                ),
              );
            },
          ),
        ]),
      ),
    );
  }
}
