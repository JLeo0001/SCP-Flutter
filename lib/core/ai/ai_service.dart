import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart' show visibleForTesting;

import 'ai_models.dart';

/// 一条对话消息 role = user | assistant | tool
class AiMessage {
  final String role;
  final String content;

  /// assistant 请求工具调用(OpenAI tool_calls / Claude tool_use / Gemini functionCall)
  final List<AiToolCall>? toolCalls;

  /// tool 结果消息:对应请求的调用 id 与名称
  final String? toolCallId;
  final String? toolName;

  const AiMessage({
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolCallId,
    this.toolName,
  });
}

/// 一次工具调用请求
class AiToolCall {
  final String id; // openai/claude 用;gemini 生成占位 id
  final String name;
  final String arguments; // JSON 字符串

  const AiToolCall({required this.id, required this.name, required this.arguments});
}

/// 内置工具:AI 分段读取当前文档,替代整篇注入,省 token
class AiTools {
  static const readDocument = 'read_document';

  static const description =
      '读取用户正在阅读的文档正文片段。首次调用可不带参数从头读取;'
      '根据返回的 total 与 hasMore 继续读取后续内容,只在需要时读取。';

  /// OpenAPI 子集 schema(OpenAI parameters / Claude input_schema / Gemini parameters 通用)
  static Map<String, dynamic> parametersSchema() => {
        'type': 'object',
        'properties': {
          'offset': {'type': 'integer', 'description': '从文档第几个字符开始读取(从 0 计)'},
          'length': {'type': 'integer', 'description': '本次读取字符数,默认 4000,上限 12000'},
        },
        'required': [],
      };

  static Map<String, dynamic> declarationFor(AiProviderType type) => switch (type) {
        AiProviderType.openai => {
          'type': 'function',
          'function': {
            'name': readDocument,
            'description': description,
            'parameters': parametersSchema(),
          },
        },
        AiProviderType.claude => {
          'name': readDocument,
          'description': description,
          'input_schema': parametersSchema(),
        },
        AiProviderType.gemini => {
          'functionDeclarations': [
            {
              'name': readDocument,
              'description': description,
              'parameters': parametersSchema(),
            }
          ],
        },
      };
}

/// AI 调用异常(携带可读信息,直接展示给用户)
class AiException implements Exception {
  final String message;
  final int? statusCode;
  AiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// 协作式取消令牌(工具循环轮间/流中检查)
class CancelToken {
  bool isCancelled = false;
}

class AiCancelled implements Exception {
  const AiCancelled();
  @override
  String toString() => '已取消';
}

/// 一帧 SSE 事件
class AiSseFrame {
  final String? event;
  final String data;
  const AiSseFrame(this.data, [this.event]);
}

/// SSE 分帧解析器(按 RFC 7230 空行分事件;容忍 chunk 在行中间截断)
class AiSseParser {
  final List<String> _dataLines = [];
  String? _event;
  String _lineBuf = '';

  /// 喂入任意分段文本,返回解析完整的帧
  List<AiSseFrame> feed(String chunk) {
    final out = <AiSseFrame>[];
    _lineBuf += chunk;
    final parts = _lineBuf.split('\n');
    _lineBuf = parts.removeLast(); // 最后一段可能不完整,留到下次
    for (var raw in parts) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty) {
        final f = _flush();
        if (f != null) out.add(f);
      } else if (line.startsWith(':')) {
        // 注释/心跳,忽略
      } else if (line.startsWith('data:')) {
        _dataLines.add(line.substring(5).trimLeft());
      } else if (line.startsWith('event:')) {
        _event = line.substring(6).trimLeft();
      }
      // 其他字段(id/retry)忽略
    }
    return out;
  }

  /// 流结束时调用,冲出残留的最后一行/未以空行收尾的帧
  List<AiSseFrame> end() {
    if (_lineBuf.isNotEmpty) {
      var line = _lineBuf;
      _lineBuf = '';
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.startsWith('data:')) {
        _dataLines.add(line.substring(5).trimLeft());
      } else if (line.startsWith('event:')) {
        _event = line.substring(6).trimLeft();
      }
    }
    final f = _flush();
    return f == null ? const [] : [f];
  }

  AiSseFrame? _flush() {
    if (_dataLines.isEmpty) {
      _event = null;
      return null;
    }
    final f = AiSseFrame(_dataLines.join('\n'), _event);
    _dataLines.clear();
    _event = null;
    return f;
  }
}

/// 流式事件:文本增量 或 一次完整的工具调用批次
sealed class AiStreamEvent {
  const AiStreamEvent();
}

class AiTextEvent extends AiStreamEvent {
  final String text;
  const AiTextEvent(this.text);
}

class AiToolEvent extends AiStreamEvent {
  final List<AiToolCall> calls;
  const AiToolEvent(this.calls);
}

/// 从可能损坏的 JSON 文本解析 Map,失败返回 null
Map<String, dynamic>? _decodeJson(String s) {
  try {
    final v = jsonDecode(s);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}

/// 流式工具调用片段累积(按协议从 SSE 帧拼出完整调用)
class AiToolCallBuffer {
  final Map<int, List<String?>> _openai = {}; // index -> [id, name, args]
  final List<AiToolCall> _done = [];
  String? _claudeId;
  String? _claudeName;
  final StringBuffer _claudeArgs = StringBuffer();
  int _geminiSeq = 0;

  void feed(AiProviderType type, AiSseFrame frame) {
    final j = _decodeJson(frame.data);
    if (j == null) return;
    switch (type) {
      case AiProviderType.openai:
        final choices = j['choices'];
        if (choices is! List || choices.isEmpty) return;
        final delta = choices[0]['delta'];
        if (delta is! Map) return;
        final frags = delta['tool_calls'];
        if (frags is! List) return;
        for (final frag in frags) {
          if (frag is! Map) continue;
          final idx = (frag['index'] is num) ? (frag['index'] as num).toInt() : 0;
          final slot = _openai.putIfAbsent(idx, () => [null, null, '']);
          if (frag['id'] is String && (frag['id'] as String).isNotEmpty) slot[0] = frag['id'];
          final fn = frag['function'];
          if (fn is Map) {
            if (fn['name'] is String && (fn['name'] as String).isNotEmpty && slot[1] == null) {
              slot[1] = fn['name'];
            }
            if (fn['arguments'] is String) slot[2] = slot[2]! + (fn['arguments'] as String);
          }
        }
      case AiProviderType.claude:
        final t = j['type'];
        if (t == 'content_block_start') {
          final block = j['content_block'];
          if (block is Map && block['type'] == 'tool_use') {
            _claudeId = block['id'] as String?;
            _claudeName = block['name'] as String?;
            _claudeArgs.clear();
          }
        } else if (t == 'content_block_delta') {
          final d = j['delta'];
          if (d is Map && d['type'] == 'input_json_delta' && d['partial_json'] is String) {
            _claudeArgs.write(d['partial_json'] as String);
          }
        } else if (t == 'content_block_stop' && _claudeId != null) {
          _done.add(AiToolCall(
            id: _claudeId!,
            name: _claudeName ?? '',
            arguments: _claudeArgs.toString(),
          ));
          _claudeId = null;
          _claudeName = null;
          _claudeArgs.clear();
        }
      case AiProviderType.gemini:
        final cands = j['candidates'];
        if (cands is! List || cands.isEmpty) return;
        final content = cands[0]['content'];
        if (content is! Map) return;
        final parts = content['parts'];
        if (parts is! List) return;
        for (final part in parts) {
          if (part is Map && part['functionCall'] is Map) {
            final fc = part['functionCall'] as Map;
            final args = fc['args'] ?? fc['parameters'] ?? {};
            _done.add(AiToolCall(
              id: 'fn${_geminiSeq++}',
              name: '${fc['name'] ?? ''}',
              arguments: jsonEncode(args),
            ));
          }
        }
    }
  }

  List<AiToolCall> collect() {
    final out = <AiToolCall>[];
    final idxs = _openai.keys.toList()..sort();
    for (var i = 0; i < idxs.length; i++) {
      final s = _openai[idxs[i]]!;
      out.add(AiToolCall(id: s[0] ?? 'call_$i', name: s[1] ?? '', arguments: s[2] ?? ''));
    }
    out.addAll(_done);
    return out;
  }
}

/// AI 调用服务 —— OpenAI 兼容 / Claude / Gemini 三协议,支持 SSE 流式与工具调用
class AiService {
  AiService._();
  static final AiService instance = AiService._();

  static const Duration _connectTimeout = Duration(seconds: 45);

  // ═══ 请求构造(供测试) ═══

  @visibleForTesting
  static Uri buildUri(AiProviderConfig p, {required bool streaming, String? model}) {
    final useModel = (model != null && model.trim().isNotEmpty) ? model.trim() : p.model.trim();
    final base = p.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    var path = p.customPath.trim();
    if (path.isEmpty) {
      path = switch (p.type) {
        AiProviderType.openai => '/chat/completions',
        AiProviderType.claude => '/v1/messages',
        AiProviderType.gemini => streaming
            ? '/v1beta/models/$useModel:streamGenerateContent?alt=sse'
            : '/v1beta/models/$useModel:generateContent',
      };
      // Base URL 已带版本段时去重:…/v1 + /v1/messages → …/v1/messages
      if (path.startsWith('/v1/') && RegExp(r'/v\d+$').hasMatch(base)) {
        path = path.substring(3);
      }
    }
    path = path.replaceAll('{model}', Uri.encodeComponent(useModel));
    final Uri uri;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      uri = Uri.parse(path);
    } else {
      uri = Uri.parse('$base${path.startsWith('/') ? '' : '/'}$path');
    }
    return uri;
  }

  @visibleForTesting
  static Map<String, String> buildHeaders(AiProviderConfig p) {
    final h = <String, String>{'Content-Type': 'application/json'};
    final key = p.apiKey.trim();
    switch (p.type) {
      case AiProviderType.openai:
        if (key.isNotEmpty) h['Authorization'] = 'Bearer $key';
      case AiProviderType.claude:
        h['x-api-key'] = key;
        h['anthropic-version'] = '2023-06-01';
      case AiProviderType.gemini:
        if (key.isNotEmpty) h['x-goog-api-key'] = key;
    }
    p.customHeaders.forEach((k, v) {
      if (k.trim().isNotEmpty) h[k.trim()] = v;
    });
    return h;
  }

  /// 消息序列化为协议请求体
  @visibleForTesting
  static String buildBody(
    AiProviderConfig p, {
    required List<AiMessage> messages,
    String? system,
    required bool streaming,
    String? model,
    bool includeTools = false,
  }) {
    final useModel = (model != null && model.trim().isNotEmpty) ? model.trim() : p.model.trim();
    final sys = (system != null && system.trim().isNotEmpty) ? system : null;
    switch (p.type) {
      case AiProviderType.openai:
        final msgs = <Map<String, dynamic>>[
          if (sys != null) {'role': 'system', 'content': sys},
          ...messages.map((m) {
            if (m.role == 'tool') {
              return {
                'role': 'tool',
                'tool_call_id': m.toolCallId ?? '',
                'content': m.content,
              };
            }
            if (m.toolCalls != null && m.toolCalls!.isNotEmpty) {
              return {
                'role': 'assistant',
                if (m.content.isNotEmpty) 'content': m.content,
                'tool_calls': [
                  for (final c in m.toolCalls!)
                    {
                      'id': c.id,
                      'type': 'function',
                      'function': {'name': c.name, 'arguments': c.arguments},
                    }
                ],
              };
            }
            return {'role': m.role, 'content': m.content};
          }),
        ];
        return jsonEncode({
          'model': useModel,
          'messages': msgs,
          'stream': streaming,
          if (p.temperature != null) 'temperature': p.temperature,
          if (p.maxTokens != null) 'max_tokens': p.maxTokens,
          if (includeTools) ...{
            'tools': [AiTools.declarationFor(p.type)],
            'tool_choice': 'auto',
          },
        });
      case AiProviderType.claude:
        return jsonEncode({
          'model': useModel,
          'max_tokens': p.maxTokens ?? 2048,
          'messages': messages.map((m) {
            if (m.role == 'tool') {
              return {
                'role': 'user',
                'content': [
                  {
                    'type': 'tool_result',
                    'tool_use_id': m.toolCallId ?? '',
                    'content': m.content,
                  }
                ],
              };
            }
            if (m.toolCalls != null && m.toolCalls!.isNotEmpty) {
              return {
                'role': 'assistant',
                'content': [
                  if (m.content.isNotEmpty)
                    {'type': 'text', 'text': m.content},
                  for (final c in m.toolCalls!)
                    {
                      'type': 'tool_use',
                      'id': c.id,
                      'name': c.name,
                      'input': _json(c.arguments) ?? {},
                    }
                ],
              };
            }
            return {'role': m.role, 'content': m.content};
          }).toList(),
          'stream': streaming,
          if (sys != null) 'system': sys,
          if (p.temperature != null) 'temperature': p.temperature,
          if (includeTools)
            'tools': [
              {
                'name': AiTools.readDocument,
                'description': AiTools.description,
                'input_schema': AiTools.parametersSchema(),
              }
            ],
        });
      case AiProviderType.gemini:
        return jsonEncode({
          'contents': messages.map((m) {
            if (m.role == 'tool') {
              return {
                'role': 'user',
                'parts': [
                  {
                    'functionResponse': {
                      'name': m.toolName ?? AiTools.readDocument,
                      'response': {'result': m.content},
                    }
                  }
                ],
              };
            }
            if (m.toolCalls != null && m.toolCalls!.isNotEmpty) {
              return {
                'role': 'model',
                'parts': [
                  if (m.content.isNotEmpty)
                    {'text': m.content},
                  for (final c in m.toolCalls!)
                    {
                      'functionCall': {
                        'name': c.name,
                        'args': _json(c.arguments) ?? {},
                      }
                    }
                ],
              };
            }
            return {
              'role': m.role == 'assistant' ? 'model' : 'user',
              'parts': [
                {'text': m.content}
              ],
            };
          }).toList(),
          if (sys != null)
            'systemInstruction': {
              'parts': [
                {'text': sys}
              ]
            },
          'generationConfig': {
            if (p.temperature != null) 'temperature': p.temperature,
            if (p.maxTokens != null) 'maxOutputTokens': p.maxTokens,
          },
          if (includeTools) 'tools': [AiTools.declarationFor(p.type)],
        });
    }
  }

  /// 从一帧 SSE 提取文本增量;协议级错误抛 AiException
  @visibleForTesting
  static AiStreamDelta? extractDelta(AiProviderType type, AiSseFrame frame) {
    final data = frame.data;
    switch (type) {
      case AiProviderType.openai:
        if (data == '[DONE]') return const AiStreamDelta(end: true);
        final j = _json(data);
        if (j == null) return null;
        if (j['error'] != null) throw AiException(_errText(j['error']));
        final choices = j['choices'];
        if (choices is! List || choices.isEmpty) return null;
        final delta = choices[0]['delta'];
        if (delta is Map && delta['content'] is String) {
          return AiStreamDelta(text: delta['content'] as String);
        }
        return null;
      case AiProviderType.claude:
        final j = _json(data);
        if (j == null) return null;
        if (j['error'] != null) throw AiException(_errText(j['error']));
        final t = j['type'];
        if (t == 'message_stop') return const AiStreamDelta(end: true);
        if (t == 'content_block_delta') {
          final d = j['delta'];
          if (d is Map && d['type'] == 'text_delta' && d['text'] is String) {
            return AiStreamDelta(text: d['text'] as String);
          }
        }
        return null;
      case AiProviderType.gemini:
        final j = _json(data);
        if (j == null) return null;
        if (j['error'] != null) throw AiException(_errText(j['error']));
        final cands = j['candidates'];
        if (cands is! List || cands.isEmpty) return null;
        final content = cands[0]['content'];
        if (content is! Map) return null;
        final parts = content['parts'];
        if (parts is! List) return null;
        final buf = StringBuffer();
        for (final part in parts) {
          if (part is Map && part['text'] is String) buf.write(part['text'] as String);
        }
        final s = buf.toString();
        return s.isEmpty ? null : AiStreamDelta(text: s);
    }
  }

  /// 非流式响应:提取全文 + 工具调用
  @visibleForTesting
  static (String, List<AiToolCall>) extractResponse(AiProviderType type, String body) {
    final j = _json(body);
    if (j == null) throw AiException('响应不是有效的 JSON: ${_clip(body)}');
    if (j['error'] != null) throw AiException(_errText(j['error']));
    switch (type) {
      case AiProviderType.openai:
        final choices = j['choices'];
        if (choices is! List || choices.isEmpty) {
          throw AiException('响应缺少 choices: ${_clip(body)}');
        }
        final msg = choices[0]['message'];
        if (msg is! Map) {
          if (choices[0]['text'] is String) return (choices[0]['text'] as String, const []);
          throw AiException('响应缺少 message: ${_clip(body)}');
        }
        final text = msg['content'] is String ? msg['content'] as String : '';
        final calls = <AiToolCall>[];
        final tcs = msg['tool_calls'];
        if (tcs is List) {
          for (final tc in tcs) {
            if (tc is! Map) continue;
            final fn = tc['function'];
            if (fn is! Map) continue;
            calls.add(AiToolCall(
              id: '${tc['id'] ?? ''}',
              name: '${fn['name'] ?? ''}',
              arguments: fn['arguments'] is String ? fn['arguments'] as String : '{}',
            ));
          }
        }
        return (text, calls);
      case AiProviderType.claude:
        final content = j['content'];
        if (content is! List) throw AiException('响应缺少 content: ${_clip(body)}');
        final buf = StringBuffer();
        final calls = <AiToolCall>[];
        for (final blk in content) {
          if (blk is! Map) continue;
          if (blk['type'] == 'text' && blk['text'] is String) buf.write(blk['text'] as String);
          if (blk['type'] == 'tool_use') {
            calls.add(AiToolCall(
              id: '${blk['id'] ?? ''}',
              name: '${blk['name'] ?? ''}',
              arguments: jsonEncode(blk['input'] ?? {}),
            ));
          }
        }
        return (buf.toString(), calls);
      case AiProviderType.gemini:
        final cands = j['candidates'];
        if (cands is! List || cands.isEmpty) {
          throw AiException('响应缺少 candidates: ${_clip(body)}');
        }
        final content = cands[0]?['content'];
        if (content is! Map) throw AiException('响应缺少 content: ${_clip(body)}');
        final parts = content['parts'];
        if (parts is! List) throw AiException('响应缺少 parts: ${_clip(body)}');
        final buf = StringBuffer();
        final calls = <AiToolCall>[];
        for (final part in parts) {
          if (part is! Map) continue;
          if (part['text'] is String) buf.write(part['text'] as String);
          if (part['functionCall'] is Map) {
            final fc = part['functionCall'] as Map;
            calls.add(AiToolCall(
              id: 'fn0',
              name: '${fc['name'] ?? ''}',
              arguments: jsonEncode(fc['args'] ?? {}),
            ));
          }
        }
        return (buf.toString(), calls);
    }
  }

  /// 非流式响应提取全文
  @visibleForTesting
  static String extractFullText(AiProviderType type, String body) {
    final (text, _) = extractResponse(type, body);
    return text;
  }

  // ═══ 对外 API ═══

  /// 单轮流式:文本增量 + 工具调用批次
  Stream<AiStreamEvent> _send(
    AiProviderConfig p, {
    required List<AiMessage> messages,
    String? system,
    String? model,
    bool? forceStream,
    bool includeTools = false,
  }) async* {
    final streaming = forceStream ?? p.stream;
    final client = http.Client();
    try {
      final req = http.Request('POST', buildUri(p, streaming: streaming, model: model))
        ..headers.addAll(buildHeaders(p))
        ..body = buildBody(p, messages: messages, system: system, streaming: streaming,
            model: model, includeTools: includeTools);
      final resp = await client.send(req).timeout(_connectTimeout);
      if (resp.statusCode != 200) {
        final body = await resp.stream.bytesToString();
        throw AiException(_errorFromResponse(resp.statusCode, body), statusCode: resp.statusCode);
      }
      if (!streaming) {
        final full = await resp.stream.bytesToString();
        final (text, calls) = extractResponse(p.type, full);
        if (text.isNotEmpty) yield AiTextEvent(text);
        if (calls.isNotEmpty) yield AiToolEvent(calls);
        return;
      }
      final parser = AiSseParser();
      final toolBuf = AiToolCallBuffer();
      var done = false;
      await for (final chunk in resp.stream.transform(utf8.decoder)) {
        for (final frame in parser.feed(chunk)) {
          final d = extractDelta(p.type, frame);
          if (d != null && d.end) {
            done = true;
            break;
          }
          if (d != null && d.text != null && d.text!.isNotEmpty) yield AiTextEvent(d.text!);
          toolBuf.feed(p.type, frame);
        }
        if (done) break;
      }
      // 收尾:流自然结束(未收到结束标记)时也要解析剩余帧
      if (!done) {
        for (final frame in parser.end()) {
          final d = extractDelta(p.type, frame);
          if (d == null || d.end) continue;
          if (d.text != null && d.text!.isNotEmpty) yield AiTextEvent(d.text!);
        }
      }
      final calls = toolBuf.collect();
      if (calls.isNotEmpty) yield AiToolEvent(calls);
    } on TimeoutException {
      throw AiException('连接超时(${_connectTimeout.inSeconds}s),请检查网络或 API 地址');
    } on AiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw AiException('网络错误: ${e.message}');
    } finally {
      client.close();
    }
  }

  /// 流式对话:逐段 yield 文本增量(不带工具)
  Stream<String> stream(
    AiProviderConfig p, {
    required List<AiMessage> messages,
    String? system,
    String? model,
  }) async* {
    await for (final ev in _send(p, messages: messages, system: system, model: model)) {
      if (ev is AiTextEvent) yield ev.text;
    }
  }

  /// 带工具的对话循环:模型调用工具 → 执行 → 回传结果 → 继续生成,直至产出文本
  ///
  /// [onDelta] 流式输出每轮的文本增量;[onToolCall] 在执行工具前回调(供 UI 提示)。
  Future<String> chatWithTools(
    AiProviderConfig p, {
    required List<AiMessage> messages,
    String? system,
    String? model,
    required Future<String> Function(AiToolCall call) toolHandler,
    void Function(String delta)? onDelta,
    void Function(AiToolCall call)? onToolCall,
    CancelToken? cancel,
    int maxRounds = 4,
  }) async {
    final convo = [...messages];
    for (var round = 0; round < maxRounds; round++) {
      if (cancel?.isCancelled ?? false) throw const AiCancelled();
      final calls = <AiToolCall>[];
      final buf = StringBuffer();
      await for (final ev in _send(p, messages: convo, system: system, model: model,
          includeTools: true)) {
        if (cancel?.isCancelled ?? false) throw const AiCancelled();
        switch (ev) {
          case AiTextEvent(:final text):
            buf.write(text);
            onDelta?.call(text);
          case AiToolEvent(calls: final batch):
            calls.addAll(batch);
        }
      }
      if (calls.isEmpty) return buf.toString();
      convo.add(AiMessage(role: 'assistant', content: buf.toString(), toolCalls: calls));
      for (final c in calls) {
        onToolCall?.call(c);
        String result;
        try {
          result = await toolHandler(c);
        } catch (e) {
          result = jsonEncode({'error': '$e'});
        }
        convo.add(AiMessage(role: 'tool', content: result, toolCallId: c.id, toolName: c.name));
      }
    }
    throw AiException('工具调用超过 $maxRounds 轮仍未完成,已中止');
  }

  /// 非流式对话:等待完整响应
  Future<String> send(
    AiProviderConfig p, {
    required List<AiMessage> messages,
    String? system,
    String? model,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('POST', buildUri(p, streaming: false, model: model))
        ..headers.addAll(buildHeaders(p))
        ..body = buildBody(p, messages: messages, system: system, streaming: false, model: model);
      final resp = await client.send(req).timeout(_connectTimeout);
      final body = await resp.stream.bytesToString();
      if (resp.statusCode != 200) {
        throw AiException(_errorFromResponse(resp.statusCode, body), statusCode: resp.statusCode);
      }
      return extractFullText(p.type, body);
    } on TimeoutException {
      throw AiException('连接超时(${_connectTimeout.inSeconds}s),请检查网络或 API 地址');
    } on AiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw AiException('网络错误: ${e.message}');
    } finally {
      client.close();
    }
  }

  /// 测试连通性:发一条极短消息,返回结果文本
  Future<String> testConnection(AiProviderConfig p) async {
    if (p.baseUrl.trim().isEmpty) throw AiException('请先填写 API 地址');
    if (p.model.trim().isEmpty) throw AiException('请先填写模型名');
    final out = await send(p, messages: const [AiMessage(role: 'user', content: 'ping')]);
    return '连接成功 · ${p.model.trim()} · ${_clip(out, 40)}';
  }

  // ═══ 错误解析 ═══

  static Map<String, dynamic>? _json(String s) {
    try {
      final v = jsonDecode(s);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static String _errText(dynamic err) {
    if (err is Map) {
      final m = err['message'];
      if (m is String && m.isNotEmpty) return m;
    }
    return '$err';
  }

  static String _clip(String s, [int n = 300]) {
    s = s.trim().replaceAll('\n', ' ');
    return s.length <= n ? s : '${s.substring(0, n)}…';
  }

  static String _errorFromResponse(int status, String body) {
    final j = _json(body);
    if (j != null && j['error'] != null) {
      final msg = _errText(j['error']);
      return 'HTTP $status: $msg';
    }
    return 'HTTP $status: ${_clip(body)}';
  }
}

/// 流式增量(单帧解析结果)
class AiStreamDelta {
  final String? text;
  final bool end;
  const AiStreamDelta({this.text, this.end = false});
}
