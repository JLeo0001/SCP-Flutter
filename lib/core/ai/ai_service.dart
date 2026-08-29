import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart' show visibleForTesting;

import 'ai_models.dart';

/// 一条对话消息 role = user | assistant
class AiMessage {
  final String role;
  final String content;
  const AiMessage({required this.role, required this.content});
}

/// AI 调用异常(携带可读信息,直接展示给用户)
class AiException implements Exception {
  final String message;
  final int? statusCode;
  AiException(this.message, {this.statusCode});
  @override
  String toString() => message;
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

/// 流式增量(单帧解析结果)
class AiStreamDelta {
  final String? text;
  final bool end;
  const AiStreamDelta({this.text, this.end = false});
}

/// AI 调用服务 —— OpenAI 兼容 / Claude / Gemini 三协议,支持 SSE 流式
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

  @visibleForTesting
  static String buildBody(
    AiProviderConfig p, {
    required List<AiMessage> messages,
    String? system,
    required bool streaming,
    String? model,
  }) {
    final useModel = (model != null && model.trim().isNotEmpty) ? model.trim() : p.model.trim();
    switch (p.type) {
      case AiProviderType.openai:
        final msgs = <Map<String, String>>[
          if (system != null && system.trim().isNotEmpty) {'role': 'system', 'content': system},
          ...messages.map((m) => {'role': m.role, 'content': m.content}),
        ];
        return jsonEncode({
          'model': useModel,
          'messages': msgs,
          'stream': streaming,
          if (p.temperature != null) 'temperature': p.temperature,
          if (p.maxTokens != null) 'max_tokens': p.maxTokens,
        });
      case AiProviderType.claude:
        return jsonEncode({
          'model': useModel,
          'max_tokens': p.maxTokens ?? 2048,
          'messages': messages.map((m) => {'role': m.role, 'content': m.content}).toList(),
          'stream': streaming,
          if (system != null && system.trim().isNotEmpty) 'system': system,
          if (p.temperature != null) 'temperature': p.temperature,
        });
      case AiProviderType.gemini:
        return jsonEncode({
          'contents': messages
              .map((m) => {
                    'role': m.role == 'assistant' ? 'model' : 'user',
                    'parts': [
                      {'text': m.content}
                    ],
                  })
              .toList(),
          if (system != null && system.trim().isNotEmpty)
            'systemInstruction': {
              'parts': [
                {'text': system}
              ]
            },
          'generationConfig': {
            if (p.temperature != null) 'temperature': p.temperature,
            if (p.maxTokens != null) 'maxOutputTokens': p.maxTokens,
          },
        });
    }
  }

  /// 从一帧 SSE 提取增量;协议级错误抛 AiException
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

  /// 非流式响应提取全文
  @visibleForTesting
  static String extractFullText(AiProviderType type, String body) {
    final j = _json(body);
    if (j == null) throw AiException('响应不是有效的 JSON: ${_clip(body)}');
    if (j['error'] != null) throw AiException(_errText(j['error']));
    switch (type) {
      case AiProviderType.openai:
        final choices = j['choices'];
        if (choices is List && choices.isNotEmpty) {
          final msg = choices[0]['message'];
          if (msg is Map && msg['content'] is String) return msg['content'] as String;
          if (choices[0]['text'] is String) return choices[0]['text'] as String;
        }
        throw AiException('响应缺少 choices: ${_clip(body)}');
      case AiProviderType.claude:
        final content = j['content'];
        if (content is List) {
          final buf = StringBuffer();
          for (final blk in content) {
            if (blk is Map && blk['type'] == 'text' && blk['text'] is String) {
              buf.write(blk['text'] as String);
            }
          }
          if (buf.isNotEmpty) return buf.toString();
        }
        throw AiException('响应缺少 content: ${_clip(body)}');
      case AiProviderType.gemini:
        final cands = j['candidates'];
        if (cands is List && cands.isNotEmpty) {
          final parts = cands[0]?['content']?['parts'];
          if (parts is List) {
            final buf = StringBuffer();
            for (final part in parts) {
              if (part is Map && part['text'] is String) buf.write(part['text'] as String);
            }
            if (buf.isNotEmpty) return buf.toString();
          }
        }
        throw AiException('响应缺少 candidates: ${_clip(body)}');
    }
  }

  // ═══ 对外 API ═══

  /// 流式对话:逐段 yield 文本增量
  Stream<String> stream(
    AiProviderConfig p, {
    required List<AiMessage> messages,
    String? system,
    String? model,
  }) async* {
    final client = http.Client();
    try {
      final req = http.Request('POST', buildUri(p, streaming: p.stream, model: model))
        ..headers.addAll(buildHeaders(p))
        ..body = buildBody(p, messages: messages, system: system, streaming: p.stream, model: model);
      final resp = await client.send(req).timeout(_connectTimeout);
      if (resp.statusCode != 200) {
        final body = await resp.stream.bytesToString();
        throw AiException(_errorFromResponse(resp.statusCode, body), statusCode: resp.statusCode);
      }
      if (!p.stream) {
        final full = await resp.stream.bytesToString();
        yield extractFullText(p.type, full);
        return;
      }
      final parser = AiSseParser();
      await for (final chunk in resp.stream.transform(utf8.decoder)) {
        for (final frame in parser.feed(chunk)) {
          final d = extractDelta(p.type, frame);
          if (d == null) continue;
          if (d.end) return;
          final t = d.text;
          if (t != null && t.isNotEmpty) yield t;
        }
      }
      for (final frame in parser.end()) {
        final d = extractDelta(p.type, frame);
        if (d == null || d.end) continue;
        final t = d.text;
        if (t != null && t.isNotEmpty) yield t;
      }
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
