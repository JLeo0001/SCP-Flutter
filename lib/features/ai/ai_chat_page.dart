import 'dart:async';

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

  const AiChatPage({
    super.key,
    required this.docTitle,
    required this.articleText,
    required this.bg,
    required this.fg,
    required this.border,
    required this.dark,
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

  _Msg({required this.role, required this.display, this.text = '', this.streaming = false});
}

class _AiChatPageState extends State<AiChatPage> {
  late AiSettings _settings;
  final List<_Msg> _msgs = [];
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  StreamSubscription<String>? _sub;
  Timer? _flushTimer;
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
  }

  @override
  void dispose() {
    _sub?.cancel();
    _flushTimer?.cancel();
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── 数据 ──

  List<AiFeatureConfig> get _quickFeatures =>
      _settings.effectiveFeatures().where((f) => f.id != 'chat').toList();

  AiFeatureConfig? get _chatFeature {
    for (final f in _settings.effectiveFeatures()) {
      if (f.id == 'chat') return f;
    }
    return null;
  }

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

  void _runFeature(AiFeatureConfig f) {
    if (_generating) return;
    final provider = _settings.providerById(f.providerId);
    if (provider == null || !provider.enabled) {
      _snack('「${f.name}」绑定的供应商不可用,请到 AI 设置中检查');
      return;
    }
    String content;
    final tpl = f.userPromptTemplate.trim();
    if (tpl.isEmpty) {
      _snack('「${f.name}」未配置提示词模板');
      return;
    }
    content = _render(tpl, useContext: f.useArticleContext);
    final display = tpl.length > 160 ? '${tpl.substring(0, 160)}…' : tpl;
    final system = f.systemPrompt.trim().isEmpty ? null : _render(f.systemPrompt, useContext: f.useArticleContext);
    _startGeneration(
      provider,
      system: system,
      model: f.model.trim().isNotEmpty ? f.model.trim() : null,
      messages: [AiMessage(role: 'user', content: content)],
      userDisplay: display,
      userText: content,
    );
  }

  void _sendChat() {
    final text = _input.text.trim();
    if (text.isEmpty || _generating) return;
    final f = _chatFeature;
    if (f == null) {
      _snack('自由对话未启用或供应商未配置,请到 AI 设置中检查');
      return;
    }
    final provider = _settings.providerById(f.providerId);
    if (provider == null || !provider.enabled) {
      _snack('自由对话绑定的供应商不可用');
      return;
    }
    _input.clear();
    final system = f.systemPrompt.trim().isEmpty ? null : _render(f.systemPrompt, useContext: f.useArticleContext);
    // 历史:只保留最近 20 条,控制 token
    final history = <AiMessage>[];
    for (final m in _msgs) {
      if (m.error || m.text.trim().isEmpty) continue;
      history.add(AiMessage(role: m.role, content: m.text));
    }
    if (history.length > 20) history.removeRange(0, history.length - 20);
    final messages = [...history, AiMessage(role: 'user', content: text)];
    _startGeneration(
      provider,
      system: system,
      model: f.model.trim().isNotEmpty ? f.model.trim() : null,
      messages: messages,
      userDisplay: text,
      userText: text,
    );
  }

  void _startGeneration(
    AiProviderConfig provider, {
    String? system,
    String? model,
    required List<AiMessage> messages,
    required String userDisplay,
    String? userText,
  }) {
    _msgs.add(_Msg(role: 'user', display: userDisplay, text: userText ?? userDisplay));
    final assistant = _Msg(role: 'assistant', display: '', streaming: true);
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
    _sub?.cancel();
    _sub = AiService.instance
        .stream(provider, messages: messages, system: system, model: model)
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

  void _finishGeneration(_Msg assistant, StringBuffer buf, {String? errorText}) {
    _flushTimer?.cancel();
    if (buf.isNotEmpty) assistant.text += buf.toString();
    assistant.streaming = false;
    if (errorText != null) {
      assistant.error = true;
      if (assistant.text.isEmpty) assistant.text = errorText;
      // 出错信息完整展示
      _snack(errorText);
    }
    _generating = false;
    _sub = null;
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  void _stop() {
    if (!_generating) return;
    _genCount++;
    _sub?.cancel();
    _sub = null;
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
    final chat = _chatFeature;
    return Scaffold(
        backgroundColor: widget.bg,
        appBar: AppBar(
          backgroundColor: widget.bg,
          foregroundColor: fg,
          elevation: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI 助手', style: TextStyle(fontSize: 16)),
            Text(widget.docTitle,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: sub)),
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
            _buildInput(chat != null, fg, sub),
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
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
