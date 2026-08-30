import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scp_app/core/ai/ai_models.dart';
import 'package:scp_app/core/ai/ai_service.dart';
import 'package:scp_app/core/ai/article_text.dart';

void main() {
  group('AiSseParser', () {
    test('标准逐帧解析', () {
      final p = AiSseParser();
      var frames = p.feed('data: {"a":1}\n\ndata: [DONE]\n\n');
      expect(frames.length, 2);
      expect(frames[0].data, '{"a":1}');
      expect(frames[1].data, '[DONE]');
    });

    test('chunk 任意位置截断不丢数据', () {
      final p = AiSseParser();
      final src = 'data: {"choices":[{"delta":{"content":"你"}}]}\n\ndata: {"b":2}\n\n';
      final all = <AiSseFrame>[];
      for (var i = 0; i < src.length; i += 7) {
        final end = (i + 7).clamp(0, src.length);
        all.addAll(p.feed(src.substring(i, end)));
      }
      expect(all.length, 2);
      expect(jsonDecode(all[0].data)['choices'][0]['delta']['content'], '你');
      expect(all[1].data, '{"b":2}');
    });

    test('CRLF 换行与注释心跳', () {
      final p = AiSseParser();
      final frames = p.feed(': keep-alive\r\ndata: x\r\n\r\n');
      expect(frames.length, 1);
      expect(frames[0].data, 'x');
    });

    test('event 字段与多行 data', () {
      final p = AiSseParser();
      final frames = p.feed('event: content_block_delta\ndata: line1\ndata: line2\n\n');
      expect(frames.length, 1);
      expect(frames[0].event, 'content_block_delta');
      expect(frames[0].data, 'line1\nline2');
    });

    test('流结束冲出未收尾帧', () {
      final p = AiSseParser();
      expect(p.feed('data: tail'), isEmpty);
      final frames = p.end();
      expect(frames.length, 1);
      expect(frames[0].data, 'tail');
    });
  });

  group('extractDelta · OpenAI 兼容', () {
    const t = AiProviderType.openai;
    AiStreamDelta? d(String s) => AiService.extractDelta(t, AiSseFrame(s));

    test('delta.content', () {
      final r = d(jsonEncode({
        'choices': [{'delta': {'content': '你好'}}]
      }));
      expect(r!.text, '你好');
    });

    test('[DONE] 结束', () {
      expect(d('[DONE]')!.end, isTrue);
    });

    test('role 帧/空 delta 返回 null', () {
      expect(d(jsonEncode({'choices': [
        {'delta': {'role': 'assistant'}}
      ]})), isNull);
      expect(d(jsonEncode({'choices': []})), isNull);
    });

    test('协议错误抛出', () {
      expect(() => d(jsonEncode({'error': {'message': 'bad key'}})),
          throwsA(isA<AiException>().having((e) => e.message, 'msg', 'bad key')));
    });
  });

  group('extractDelta · Claude', () {
    const t = AiProviderType.claude;
    AiStreamDelta? d(String s) => AiService.extractDelta(t, AiSseFrame(s));

    test('content_block_delta / text_delta', () {
      final r = d(jsonEncode({
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': 'hi'}
      }));
      expect(r!.text, 'hi');
    });

    test('thinking_delta 忽略', () {
      expect(d(jsonEncode({
        'type': 'content_block_delta',
        'delta': {'type': 'thinking_delta', 'thinking': 'x'}
      })), isNull);
    });

    test('message_stop 结束', () {
      expect(d(jsonEncode({'type': 'message_stop'}))!.end, isTrue);
    });

    test('error 事件抛出', () {
      expect(() => d(jsonEncode({'type': 'error', 'error': {'message': 'overloaded'}})),
          throwsA(isA<AiException>()));
    });
  });

  group('extractDelta · Gemini', () {
    const t = AiProviderType.gemini;
    AiStreamDelta? d(String s) => AiService.extractDelta(t, AiSseFrame(s));

    test('candidates.parts.text 拼接', () {
      final r = d(jsonEncode({
        'candidates': [
          {'content': {'parts': [
            {'text': 'A'}, {'text': 'B'}
          ]}}
        ]
      }));
      expect(r!.text, 'AB');
    });

    test('空候选返回 null', () {
      expect(d(jsonEncode({'candidates': []})), isNull);
    });

    test('error 抛出', () {
      expect(() => d(jsonEncode({'error': {'message': 'quota'}})), throwsA(isA<AiException>()));
    });
  });

  group('extractFullText', () {
    test('OpenAI message.content', () {
      const body = '{"choices":[{"message":{"role":"assistant","content":"全文"}}]}';
      expect(AiService.extractFullText(AiProviderType.openai, body), '全文');
    });

    test('Claude content 数组拼 text', () {
      const body = '{"content":[{"type":"text","text":"a"},{"type":"tool_use","id":"x"},{"type":"text","text":"b"}]}';
      expect(AiService.extractFullText(AiProviderType.claude, body), 'ab');
    });

    test('Gemini candidates', () {
      const body = '{"candidates":[{"content":{"parts":[{"text":"gem"}]}}]}';
      expect(AiService.extractFullText(AiProviderType.gemini, body), 'gem');
    });
  });

  group('请求构造', () {
    AiProviderConfig p(AiProviderType t, {String customPath = ''}) => AiProviderConfig(
          id: 'x', name: 'n', type: t, baseUrl: 'https://api.example.com/v1/',
          apiKey: 'sk-test', model: 'm-1', temperature: 0.3, maxTokens: 100,
          customPath: customPath,
        );

    test('OpenAI 默认路径 + Bearer 头', () {
      final uri = AiService.buildUri(p(AiProviderType.openai), streaming: true);
      expect(uri.toString(), 'https://api.example.com/v1/chat/completions');
      final h = AiService.buildHeaders(p(AiProviderType.openai));
      expect(h['Authorization'], 'Bearer sk-test');
      final body = jsonDecode(AiService.buildBody(p(AiProviderType.openai),
          messages: const [AiMessage(role: 'user', content: 'hi')],
          system: 'sys', streaming: true)) as Map<String, dynamic>;
      expect(body['model'], 'm-1');
      expect(body['stream'], true);
      expect(body['messages'][0]['role'], 'system');
      expect(body['temperature'], 0.3);
      expect(body['max_tokens'], 100);
    });

    test('Claude 路径/头/max_tokens 兜底', () {
      final c = p(AiProviderType.claude)..maxTokens = null; // 未设置时才走 2048 兜底
      final uri = AiService.buildUri(c, streaming: true);
      expect(uri.toString(), 'https://api.example.com/v1/messages');
      final h = AiService.buildHeaders(c);
      expect(h['x-api-key'], 'sk-test');
      expect(h['anthropic-version'], '2023-06-01');
      final body = jsonDecode(AiService.buildBody(c,
          messages: const [AiMessage(role: 'user', content: 'hi')],
          streaming: true)) as Map<String, dynamic>;
      expect(body['max_tokens'], 2048); // claude 必填,未设置时兜底
      expect(body['messages'][0]['role'], 'user');
      expect(body.containsKey('system'), isFalse);
    });

    test('Gemini 路径含模型与 alt=sse,密钥走头', () {
      final g = p(AiProviderType.gemini);
      expect(AiService.buildUri(g, streaming: true).toString(),
          'https://api.example.com/v1/v1beta/models/m-1:streamGenerateContent?alt=sse');
      expect(AiService.buildUri(g, streaming: false).toString(),
          'https://api.example.com/v1/v1beta/models/m-1:generateContent');
      expect(AiService.buildHeaders(g)['x-goog-api-key'], 'sk-test');
      final body = jsonDecode(AiService.buildBody(g,
          messages: const [AiMessage(role: 'assistant', content: 'a'), AiMessage(role: 'user', content: 'b')],
          system: 'sys', streaming: true)) as Map<String, dynamic>;
      expect(body['contents'][0]['role'], 'model');
      expect(body['contents'][1]['role'], 'user');
      expect(body['systemInstruction']['parts'][0]['text'], 'sys');
      expect(body['generationConfig']['maxOutputTokens'], 100);
    });

    test('自定义路径 {model} 占位与绝对 URL', () {
      final c = p(AiProviderType.claude, customPath: '/proxy/{model}/chat');
      expect(AiService.buildUri(c, streaming: true).toString(),
          'https://api.example.com/v1/proxy/m-1/chat');
      final abs = p(AiProviderType.openai, customPath: 'https://gw.other.com/openai/v2?q=1');
      expect(AiService.buildUri(abs, streaming: true).toString(),
          'https://gw.other.com/openai/v2?q=1');
    });

    test('自定义请求头合并', () {
      final c = p(AiProviderType.claude)
        ..customHeaders['anthropic-beta'] = 'pdfs-2024-09-25';
      expect(AiService.buildHeaders(c)['anthropic-beta'], 'pdfs-2024-09-25');
    });

    test('功能模型覆盖传到 URI 与 body', () {
      final o = p(AiProviderType.openai);
      final uri = AiService.buildUri(o, streaming: false, model: 'override-m');
      expect(uri.toString(), 'https://api.example.com/v1/chat/completions');
      final body = jsonDecode(AiService.buildBody(o,
          messages: const [AiMessage(role: 'user', content: 'hi')],
          streaming: false, model: 'override-m')) as Map<String, dynamic>;
      expect(body['model'], 'override-m');
      expect(body.containsKey('stream'), isTrue);
      expect(body['stream'], false);
    });
  });

  group('AiSettings', () {
    test('出厂状态:总开关关、无供应商、功能全停用', () {
      final s = AiSettings.fresh();
      expect(s.masterEnabled, isFalse);
      expect(s.providers, isEmpty);
      expect(s.features.every((f) => !f.enabled), isTrue);
      expect(s.effectiveFeatures(), isEmpty);
      expect(AiSettingsStore.available(s), isFalse);
    });

    test('JSON 往返', () {
      final s = AiSettings.fresh();
      s.masterEnabled = true;
      s.providers.add(AiProviderConfig(
        id: 'p1', name: '测试', type: AiProviderType.claude,
        baseUrl: 'https://api.anthropic.com', apiKey: 'k', model: 'm',
        temperature: 0.5, maxTokens: 999, stream: false,
        customHeaders: {'X-A': 'B'},
      ));
      s.features.firstWhere((f) => f.id == 'summary')
        ..enabled = true
        ..providerId = 'p1';
      final s2 = AiSettings.fromJsonString(s.toJsonString());
      expect(s2.masterEnabled, isTrue);
      expect(s2.providers.length, 1);
      expect(s2.providers[0].type, AiProviderType.claude);
      expect(s2.providers[0].stream, isFalse);
      expect(s2.providers[0].customHeaders['X-A'], 'B');
      expect(s2.features.firstWhere((f) => f.id == 'summary').enabled, isTrue);
      expect(s2.features.firstWhere((f) => f.id == 'summary').providerId, 'p1');
    });

    test('旧数据缺内置功能时自动补齐;脏数据回退出厂', () {
      final s = AiSettings.fromJsonString(jsonEncode({
        'masterEnabled': true,
        'providers': [],
        'features': [
          {'id': 'custom_a', 'name': '我的功能', 'enabled': true}
        ],
      }));
      expect(s.features.any((f) => f.id == 'chat'), isTrue);
      expect(s.features.any((f) => f.id == 'custom_a'), isTrue);
      expect(AiSettings.fromJsonString('not json').masterEnabled, isFalse);
    });

    test('effectiveFeatures:需要总开关+已启用+供应商可用', () {
      final s = AiSettings.fresh()..masterEnabled = true;
      final sum = s.features.firstWhere((f) => f.id == 'summary')..enabled = true;
      expect(s.effectiveFeatures(), isEmpty); // 未绑供应商
      s.providers.add(AiProviderConfig(
          id: 'p1', name: 'x', type: AiProviderType.openai,
          baseUrl: 'https://a.com/v1', apiKey: 'k', model: 'm'));
      sum.providerId = 'p1';
      expect(s.effectiveFeatures().map((f) => f.id), contains('summary'));
      // 供应商停用 → 失效
      s.providers[0].enabled = false;
      expect(s.effectiveFeatures(), isEmpty);
      // 总开关关 → 全失效
      s.providers[0].enabled = true;
      s.masterEnabled = false;
      expect(s.effectiveFeatures(), isEmpty);
    });
  });

  group('ArticleText', () {
    test('取 #page-content 并剥离脚本/噪音', () {
      const html = '''
      <html><body>
        <script>alert(1)</script>
        <div id="page-content">
          <p>项目编号:SCP-1730</p>
          <div class="page-rate-widget-box">+ 999</div>
          <p>等级 <b>Keter</b></p>
          <ul><li>条款一</li><li>条款二</li></ul>
        </div>
        <div class="footer-wikiwalk-nav">上一页 下一页</div>
      </body></html>''';
      final text = ArticleText.extract(html);
      expect(text.contains('SCP-1730'), isTrue);
      expect(text.contains('Keter'), isTrue);
      expect(text.contains('alert'), isFalse);
      expect(text.contains('+ 999'), isFalse);
      expect(text.contains('上一页'), isFalse);
      expect(text.contains('条款一'), isTrue);
    });

    test('块级元素换行、无 page-content 时退回 body', () {
      final text = ArticleText.extract('<html><body><p>AAA</p><p>BBB</p><br>C</body></html>');
      expect(text, contains('AAA\nBBB'));
      expect(text, contains('\nC'));
    });

    test('模板渲染与截断', () {
      expect(ArticleText.renderPrompt('标题:{title}\n正文:{content}',
          title: 'T', content: 'C'), '标题:T\n正文:C');
      final long = 'x' * 1000;
      final cut = ArticleText.truncateMiddle(long, 200);
      expect(cut.length, 200);
      expect(cut, startsWith('x'));
      expect(cut, endsWith('x'));
      expect(cut, contains('已省略'));
      expect(ArticleText.truncateMiddle('short', 200), 'short');
    });
  });

  group('chatCapability(自由对话默认最顶部供应商)', () {
    AiProviderConfig mkProv(String id, {bool enabled = true}) => AiProviderConfig(
        id: id,
        name: id,
        type: AiProviderType.openai,
        baseUrl: 'https://a.com/v1',
        apiKey: 'k',
        model: 'm-$id',
        enabled: enabled);

    test('未单独绑定 → 默认最上方启用供应商', () {
      final s = AiSettings.fresh()..masterEnabled = true;
      s.providers.addAll([mkProv('a'), mkProv('b')]);
      expect(s.chatCapability()!.provider.id, 'a');
    });

    test('跳过未启用的供应商', () {
      final s = AiSettings.fresh()..masterEnabled = true;
      s.providers.addAll([mkProv('a', enabled: false), mkProv('b')]);
      expect(s.chatCapability()!.provider.id, 'b');
    });

    test('单独绑定的供应商优先', () {
      final s = AiSettings.fresh()..masterEnabled = true;
      s.providers.addAll([mkProv('a'), mkProv('b')]);
      s.features.firstWhere((f) => f.id == 'chat').providerId = 'b';
      expect(s.chatCapability()!.provider.id, 'b');
    });

    test('总开关关闭 / 无供应商 → null', () {
      final s = AiSettings.fresh()
        ..masterEnabled = false
        ..providers.add(mkProv('a'));
      expect(s.chatCapability(), isNull);
      expect(AiSettings.fresh().masterEnabled, isFalse);
      final s2 = AiSettings.fresh()..masterEnabled = true;
      expect(s2.chatCapability(), isNull);
    });

    test('isAvailable:有可用供应商即显示入口', () {
      final s = AiSettings.fresh()..masterEnabled = true;
      s.providers.add(mkProv('a'));
      expect(AiSettingsStore.available(s), isTrue);
      s.masterEnabled = false;
      expect(AiSettingsStore.available(s), isFalse);
    });
  });

  group('contextMode', () {
    test('旧数据无 contextMode → 默认 tool', () {
      final s = AiSettings.fromJsonString(jsonEncode({
        'masterEnabled': true,
        'providers': [],
        'features': [
          {'id': 'chat', 'name': '自由对话', 'builtin': true},
          {'id': 'summary', 'name': '摘要', 'builtin': true, 'enabled': false},
        ],
      }));
      expect(s.features.firstWhere((f) => f.id == 'chat').contextMode, 'tool');
      expect(s.features.firstWhere((f) => f.id == 'summary').contextMode, 'tool');
    });

    test('JSON 往返', () {
      final s = AiSettings.fresh();
      s.features.firstWhere((f) => f.id == 'summary').contextMode = 'tool';
      final s2 = AiSettings.fromJsonString(s.toJsonString());
      expect(s2.features.firstWhere((f) => f.id == 'summary').contextMode, 'tool');
    });

    test('effectiveFeatures 不含 chat', () {
      final s = AiSettings.fresh()..masterEnabled = true;
      s.providers.add(AiProviderConfig(
          id: 'p', name: 'x', type: AiProviderType.openai,
          baseUrl: 'https://a.com/v1', apiKey: 'k', model: 'm'));
      s.features.firstWhere((f) => f.id == 'chat')..enabled = true..providerId = 'p';
      expect(s.effectiveFeatures(), isEmpty);
    });

    test('功能未绑定供应商 → 回退最上方启用供应商', () {
      final s = AiSettings.fresh()..masterEnabled = true;
      s.providers.add(AiProviderConfig(
          id: 'p1', name: 'x', type: AiProviderType.openai,
          baseUrl: 'https://a.com/v1', apiKey: 'k', model: 'm'));
      final sum = s.features.firstWhere((f) => f.id == 'summary')..enabled = true;
      expect(sum.providerId, isEmpty);
      expect(s.resolveFeatureProvider(sum)!.id, 'p1');
      expect(s.effectiveFeatures().map((f) => f.id), contains('summary'));
      // 绑定不可解析的供应商 → 同样回退
      sum.providerId = 'ghost';
      expect(s.resolveFeatureProvider(sum)!.id, 'p1');
      // 无任何可用供应商 → null,功能不生效
      s.providers.clear();
      expect(s.resolveFeatureProvider(sum), isNull);
      expect(s.effectiveFeatures(), isEmpty);
    });
  });

  group('工具调用消息序列化', () {
    AiProviderConfig p(AiProviderType t) => AiProviderConfig(
        id: 'x', name: 'n', type: t, baseUrl: 'https://api.example.com/v1',
        apiKey: 'k', model: 'm-1');

    test('OpenAI: tool_calls / role:tool / tools 声明', () {
      final body = jsonDecode(AiService.buildBody(p(AiProviderType.openai),
          messages: [
            const AiMessage(role: 'assistant', content: '让我查一下',
                toolCalls: [AiToolCall(id: 'c1', name: 'read_document', arguments: '{"offset":0,"length":4000}')]),
            const AiMessage(role: 'tool', content: 'RESULT', toolCallId: 'c1', toolName: 'read_document'),
          ],
          streaming: false, includeTools: true)) as Map<String, dynamic>;
      final msgs = body['messages'] as List;
      expect(msgs[0]['tool_calls'][0]['function']['name'], 'read_document');
      expect(msgs[1]['role'], 'tool');
      expect(msgs[1]['tool_call_id'], 'c1');
      expect((body['tools'] as List)[0]['function']['name'], 'read_document');
      expect(body['tool_choice'], 'auto');
    });

    test('Claude: tool_use / tool_result', () {
      final body = jsonDecode(AiService.buildBody(p(AiProviderType.claude),
          messages: [
            const AiMessage(role: 'assistant', content: '',
                toolCalls: [AiToolCall(id: 'tu_1', name: 'read_document', arguments: '{}')]),
            const AiMessage(role: 'tool', content: 'R', toolCallId: 'tu_1', toolName: 'read_document'),
          ],
          streaming: false, includeTools: true)) as Map<String, dynamic>;
      final msgs = body['messages'] as List;
      expect(msgs[0]['content'][0]['type'], 'tool_use');
      expect(msgs[1]['content'][0]['type'], 'tool_result');
      expect(msgs[1]['content'][0]['tool_use_id'], 'tu_1');
      expect((body['tools'] as List)[0]['name'], 'read_document');
    });

    test('Gemini: functionCall / functionResponse', () {
      final body = jsonDecode(AiService.buildBody(p(AiProviderType.gemini),
          messages: [
            const AiMessage(role: 'assistant', content: '',
                toolCalls: [AiToolCall(id: 'fn0', name: 'read_document', arguments: '{"offset":10}')]),
            const AiMessage(role: 'tool', content: 'R', toolCallId: 'fn0', toolName: 'read_document'),
          ],
          streaming: false, includeTools: true)) as Map<String, dynamic>;
      final msgs = body['contents'] as List;
      expect(msgs[0]['role'], 'model');
      expect(msgs[0]['parts'][0]['functionCall']['name'], 'read_document');
      expect(msgs[1]['parts'][0]['functionResponse']['name'], 'read_document');
      expect((body['tools'] as List)[0]['functionDeclarations'][0]['name'], 'read_document');
    });

    test('不带工具时不生成 tools 字段', () {
      final body = jsonDecode(AiService.buildBody(p(AiProviderType.openai),
          messages: const [AiMessage(role: 'user', content: 'hi')],
          streaming: false)) as Map<String, dynamic>;
      expect(body.containsKey('tools'), isFalse);
    });
  });

  group('AiToolCallBuffer 流式累积', () {
    test('OpenAI 分片按 index 聚合', () {
      final b = AiToolCallBuffer();
      b.feed(AiProviderType.openai, AiSseFrame(
          '{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"read_document","arguments":"{\\"off"}}]}}]}'));
      b.feed(AiProviderType.openai, AiSseFrame(
          '{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"set\\":0}"}}]}}]}'));
      final calls = b.collect();
      expect(calls.length, 1);
      expect(calls[0].id, 'c1');
      expect(calls[0].name, 'read_document');
      expect(calls[0].arguments, '{"offset":0}');
    });

    test('Claude input_json_delta 累积', () {
      final b = AiToolCallBuffer();
      b.feed(AiProviderType.claude, AiSseFrame(
          '{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tu1","name":"read_document"}}'));
      b.feed(AiProviderType.claude, AiSseFrame(
          '{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"offset\\":"}}'));
      b.feed(AiProviderType.claude, AiSseFrame(
          '{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"100}"}}'));
      b.feed(AiProviderType.claude, AiSseFrame('{"type":"content_block_stop","index":1}'));
      final calls = b.collect();
      expect(calls.length, 1);
      expect(calls[0].arguments, '{"offset":100}');
    });

    test('Gemini functionCall 直接成帧', () {
      final b = AiToolCallBuffer();
      b.feed(AiProviderType.gemini, AiSseFrame(
          '{"candidates":[{"content":{"parts":[{"functionCall":{"name":"read_document","args":{"offset":5}}}]}}]}'));
      final calls = b.collect();
      expect(calls.length, 1);
      expect(calls[0].name, 'read_document');
      expect(jsonDecode(calls[0].arguments)['offset'], 5);
    });
  });

  group('extractResponse 非流式工具调用', () {
    test('OpenAI message.tool_calls', () {
      final (text, calls) = AiService.extractResponse(AiProviderType.openai,
          '{"choices":[{"message":{"content":"","tool_calls":[{"id":"c9","type":"function","function":{"name":"read_document","arguments":"{}"}}]}}]}');
      expect(text, '');
      expect(calls[0].id, 'c9');
    });

    test('Claude tool_use 块', () {
      final (text, calls) = AiService.extractResponse(AiProviderType.claude,
          '{"content":[{"type":"text","text":"hi"},{"type":"tool_use","id":"t1","name":"read_document","input":{"offset":3}}]}');
      expect(text, 'hi');
      expect(jsonDecode(calls[0].arguments)['offset'], 3);
    });

    test('Gemini functionCall', () {
      final (text, calls) = AiService.extractResponse(AiProviderType.gemini,
          '{"candidates":[{"content":{"parts":[{"functionCall":{"name":"read_document","args":{"length":8000}}}]}}]}');
      expect(text, '');
      expect(jsonDecode(calls[0].arguments)['length'], 8000);
    });
  });
  _reasoningTests();
  _contextModeMigrationTests();

}

void _reasoningTests() {
  group('extractReasoningDelta · 思考增量', () {
    test('OpenAI 兼容:reasoning_content(DeepSeek-R1)', () {
      final r = AiService.extractReasoningDelta(
          AiProviderType.openai, AiSseFrame('{"choices":[{"delta":{"reasoning_content":"让我想想"}}]}'));
      expect(r, '让我想想');
    });
    test('OpenAI 兼容:reasoning(OpenRouter 风格)', () {
      final r = AiService.extractReasoningDelta(
          AiProviderType.openai, AiSseFrame('{"choices":[{"delta":{"reasoning":"step 1"}}]}'));
      expect(r, 'step 1');
    });
    test('OpenAI 兼容:正文 delta 不是思考', () {
      expect(
          AiService.extractReasoningDelta(
              AiProviderType.openai, AiSseFrame('{"choices":[{"delta":{"content":"正文"}}]}')),
          isNull);
    });
    test('Claude:thinking_delta', () {
      final r = AiService.extractReasoningDelta(AiProviderType.claude,
          AiSseFrame('{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"推演中"}}'));
      expect(r, '推演中');
    });
    test('Claude:text_delta 不是思考', () {
      expect(
          AiService.extractReasoningDelta(AiProviderType.claude,
              AiSseFrame('{"type":"content_block_delta","delta":{"type":"text_delta","text":"正文"}}')),
          isNull);
    });
    test('Gemini:part.thought=true', () {
      final r = AiService.extractReasoningDelta(AiProviderType.gemini,
          AiSseFrame('{"candidates":[{"content":{"parts":[{"thought":true,"text":"内部推演"}]}}]}'));
      expect(r, '内部推演');
    });
    test('Gemini:普通 part 不是思考', () {
      expect(
          AiService.extractReasoningDelta(AiProviderType.gemini,
              AiSseFrame('{"candidates":[{"content":{"parts":[{"text":"正文"}]}}]}')),
          isNull);
    });
    test('脏 JSON 返回 null', () {
      expect(AiService.extractReasoningDelta(AiProviderType.openai, AiSseFrame('not json')), isNull);
    });
  });

  group('extractReasoningFull · 思考全文(非流式)', () {
    test('OpenAI 兼容:message.reasoning_content', () {
      expect(
          AiService.extractReasoningFull(AiProviderType.openai,
              '{"choices":[{"message":{"role":"assistant","reasoning_content":"全文思考","content":"答案"}}]}'),
          '全文思考');
    });
    test('Claude:thinking 块', () {
      expect(
          AiService.extractReasoningFull(AiProviderType.claude,
              '{"content":[{"type":"thinking","thinking":"块一"},{"type":"text","text":"答案"}]}'),
          '块一');
    });
    test('Gemini:thought parts 拼接', () {
      expect(
          AiService.extractReasoningFull(AiProviderType.gemini,
              '{"candidates":[{"content":{"parts":[{"thought":true,"text":"思"},{"thought":true,"text":"考"},{"text":"答"}]}}]}'),
          '思考');
    });
    test('无思考内容返回空串', () {
      expect(
          AiService.extractReasoningFull(
              AiProviderType.openai, '{"choices":[{"message":{"role":"assistant","content":"hi"}}]}'),
          '');
      expect(AiService.extractReasoningFull(AiProviderType.openai, 'not json'), '');
    });
  });
}

void _contextModeMigrationTests() {
  Map<String, dynamic> legacyJson({bool? migrated}) => {
        'masterEnabled': true,
        'providers': <Map<String, dynamic>>[],
        'features': [
          {
            'id': 'summary', 'name': '内容摘要', 'builtin': true, 'enabled': true,
            'providerId': '', 'model': '', 'useArticleContext': true,
            'contextMode': 'inject', 'systemPrompt': '', 'userPromptTemplate': '',
          },
          {
            'id': 'mycustom', 'name': '自定义功能', 'builtin': false, 'enabled': true,
            'providerId': '', 'model': '', 'useArticleContext': false,
            'contextMode': 'inject', 'systemPrompt': '', 'userPromptTemplate': '',
          },
        ],
        'contextMaxChars': 6000,
        'includeTitle': true,
        if (migrated != null) 'ctxToolMigrated': migrated,
      };

  group('contextMode 一次性迁移(inject → tool)', () {
    test('旧存档显式 inject 全部迁为 tool 并置迁移标记', () {
      final s = AiSettings.fromJsonString(jsonEncode(legacyJson()));
      expect(s.ctxToolMigrated, isTrue);
      expect(s.features.map((f) => f.contextMode), everyElement('tool'));
    });

    test('已迁移存档(带标记):inject 保留,不再翻回', () {
      final s = AiSettings.fromJsonString(jsonEncode(legacyJson(migrated: true)));
      expect(s.features.firstWhere((f) => f.id == 'summary').contextMode, 'inject');
      expect(s.features.firstWhere((f) => f.id == 'mycustom').contextMode, 'inject');
    });

    test('新建功能默认 contextMode == tool', () {
      expect(AiFeatureConfig(id: 'x', name: 'X').contextMode, 'tool');
    });

    test('迁移标记随 toJsonString 持久化并可往返', () {
      final s = AiSettings.fromJsonString(jsonEncode(legacyJson()));
      final back = AiSettings.fromJsonString(s.toJsonString());
      expect(back.ctxToolMigrated, isTrue);
      expect(back.features.map((f) => f.contextMode), everyElement('tool'));
    });
  });
}
