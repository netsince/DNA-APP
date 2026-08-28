import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:dna/models/service_results.dart';
import 'package:dna/services/anthropic_service.dart';
import 'package:dna/services/llm_request.dart';
import 'package:dna/services/llm_service_base.dart';
import 'package:dna/services/llm_stream_chunk.dart';
import 'package:dna/services/openai_service.dart';

/// C1/C5:LLM 传输管线单测。
/// 覆盖:SSE 事件级泵(多行 data / 注释行 / [DONE] 终止)、
/// 类型化分片契约(content/reasoning/error/notice)、非 200 → LlmErrorChunk
/// (A1 回归)、空闲看门狗(A3)、错误文案提取、端点拼接规则(B2)、
/// 能力矩阵请求体(B1)、max_tokens 透传(B5),以及 Anthropic event/data 解析。
void main() {
  LlmRequest openAiRequest({String model = 'gpt-4o', int? maxTokens}) =>
      LlmRequest(
        baseUrl: 'https://example.test/v1',
        apiKey: 'key',
        model: model,
        messages: const <Map<String, String>>[
          <String, String>{'role': 'user', 'content': 'hi'}
        ],
        maxTokens: maxTokens,
      );

  String sse(List<Map<String, dynamic>> deltas) {
    final StringBuffer buf = StringBuffer();
    for (final Map<String, dynamic> d in deltas) {
      buf.write('data: ${jsonEncode(<String, dynamic>{'choices': <dynamic>[
            <String, dynamic>{'delta': d}
          ]})}\n\n');
    }
    buf.write('data: [DONE]\n\n');
    return buf.toString();
  }

  group('LlmServiceBase 流式管线(OpenAI 兼容泵)', () {
    test('content 与 reasoning_content 按序产出为类型化分片(C1)', () async {
      final body = sse(<Map<String, dynamic>>[
        <String, dynamic>{'content': '你'},
        <String, dynamic>{'reasoning_content': '思考中'},
        <String, dynamic>{'content': '好'},
      ]);
      final _RecordingClient client =
          _RecordingClient(utf8.encode(body));
      final provider = _ExposedOpenAi(streamClient: client);

      final List<LlmStreamChunk> chunks = await provider
          .streamChatCompletion(openAiRequest())
          .toList();

      expect(chunks, hasLength(3));
      expect((chunks[0] as LlmContentChunk).text, '你');
      expect(chunks[1], isA<LlmReasoningChunk>());
      expect((chunks[1] as LlmReasoningChunk).text, '思考中');
      expect((chunks[2] as LlmContentChunk).text, '好');
    });

    test('data: [DONE] 立即终止读取,后续帧不再产出', () async {
      // [DONE] 之后服务端继续发帧且连接保持打开:
      // 泵必须在 DONE 处返回,而不是等流自然关闭。
      final controller = StreamController<List<int>>();
      final client = _HoldOpenClient(controller);
      final provider = _ExposedOpenAi(streamClient: client);
      controller.add(utf8.encode(
          'data: {"choices":[{"delta":{"content":"前"}}]}\n\n'
          'data: [DONE]\n\n'
          'data: {"choices":[{"delta":{"content":"不该出现"}}]}\n\n'));

      final List<LlmStreamChunk> chunks = await provider
          .streamChatCompletion(openAiRequest())
          .toList()
          .timeout(const Duration(seconds: 3),
              onTimeout: () => fail('[DONE] 未终止流'));
      await controller.close();

      expect(chunks, hasLength(1));
      expect((chunks.single as LlmContentChunk).text, '前');
    });

    test('SSE 规范:注释行跳过、多行 data 按规范以 \\n 拼接后解码', () async {
      const body = ': keep-alive ping\n\n'
          'data: {"choices":[{"delta":{"content":\n'
          'data: "hi"}}]}\n\n'
          'data: [DONE]\n\n';
      final provider = _ExposedOpenAi(
        streamClient: _RecordingClient(utf8.encode(body)),
      );

      final List<LlmStreamChunk> chunks = await provider
          .streamChatCompletion(openAiRequest())
          .toList();

      expect(chunks, hasLength(1));
      expect((chunks.single as LlmContentChunk).text, 'hi');
    });

    test('finish_reason=length 追加长度上限提示分片(E)', () async {
      const body = 'data: {"choices":[{"delta":{"content":"截断"}}]}\n\n'
          'data: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\n'
          'data: [DONE]\n\n';
      final provider = _ExposedOpenAi(
        streamClient: _RecordingClient(utf8.encode(body)),
      );

      final List<LlmStreamChunk> chunks = await provider
          .streamChatCompletion(openAiRequest())
          .toList();

      final LlmNoticeChunk notice =
          chunks.whereType<LlmNoticeChunk>().single;
      expect(notice.message, contains('上限'));
      expect((chunks.first as LlmContentChunk).text, '截断');
    });

    test('非 200 → 单个 LlmErrorChunk,绝不抛异常(A1 错误契约)', () async {
      final provider = _ExposedOpenAi(
        streamClient: _RecordingClient(
          utf8.encode(jsonEncode(<String, dynamic>{
            'error': <String, dynamic>{'message': 'Incorrect API key'},
          })),
          statusCode: 401,
        ),
      );

      final List<LlmStreamChunk> chunks = await provider
          .streamChatCompletion(openAiRequest())
          .toList();

      expect(chunks, hasLength(1));
      final LlmErrorChunk error = chunks.single as LlmErrorChunk;
      expect(error.message, contains('HTTP 401'));
      expect(error.message, contains('Incorrect API key'));
    });

    test('畸形 JSON 行静默跳过,不中断流', () async {
      const body = 'data: {broken json\n\n'
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
          'data: [DONE]\n\n';
      final provider = _ExposedOpenAi(
        streamClient: _RecordingClient(utf8.encode(body)),
      );

      final List<LlmStreamChunk> chunks = await provider
          .streamChatCompletion(openAiRequest())
          .toList();

      expect(chunks, hasLength(1));
      expect((chunks.single as LlmContentChunk).text, 'ok');
    });

    test('空闲看门狗:body 长时间无数据 → 连接中断错误而非永久挂起(A3)', () async {
      final provider = _ExposedOpenAi(streamClient: _NeverBodyClient());

      final List<LlmStreamChunk> chunks = await provider
          .streamChatCompletion(openAiRequest())
          .toList()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail('空闲看门狗未生效:流在 5s 内未结束'),
          );

      expect(chunks, hasLength(1));
      final LlmErrorChunk error = chunks.single as LlmErrorChunk;
      expect(error.message, startsWith('连接中断'));
      expect(error.message, contains('TimeoutException'));
    });

    test('decodeOpenAiEvent:空 delta / 缺 choices / 非 JSON 均安全', () {
      final provider = _ExposedOpenAi(streamClient: _RecordingClient(<int>[]));
      expect(provider.decodeEvent('{}').chunks, isEmpty);
      expect(provider.decodeEvent('{"choices":[]}').chunks, isEmpty);
      expect(provider.decodeEvent('not-json').chunks, isEmpty);
      final SseDecode hit = provider.decodeEvent(
          '{"choices":[{"delta":{"content":"x"}}]}');
      expect(hit.chunks.single, isA<LlmContentChunk>());
    });
  });

  group('B1 能力矩阵 / B5 max_tokens:请求体组装', () {
    test('reasoning 系模型(o3-mini)省略全部采样参数', () async {
      final client = _RecordingClient(utf8.encode('data: [DONE]\n\n'));
      final provider = _ExposedOpenAi(streamClient: client);

      await provider
          .streamChatCompletion(
            openAiRequest(model: 'o3-mini')
                .copyWith(temperature: 0.3, frequencyPenalty: 0.5),
          )
          .drain<void>();

      final Map<String, dynamic> body =
          jsonDecode(utf8.decode((client.sent.single as http.Request).bodyBytes))
              as Map<String, dynamic>;
      expect(body.containsKey('temperature'), isFalse);
      expect(body.containsKey('frequency_penalty'), isFalse);
      expect(body.containsKey('top_p'), isFalse);
      expect(body['model'], 'o3-mini');
    });

    test('普通模型按需携带采样与 max_tokens', () async {
      final client = _RecordingClient(utf8.encode('data: [DONE]\n\n'));
      final provider = _ExposedOpenAi(streamClient: client);

      await provider
          .streamChatCompletion(
            openAiRequest().copyWith(topP: 0.9, maxTokens: 512),
          )
          .drain<void>();

      final Map<String, dynamic> body =
          jsonDecode(utf8.decode((client.sent.single as http.Request).bodyBytes))
              as Map<String, dynamic>;
      expect(body['temperature'], isA<num>());
      expect(body['top_p'], 0.9);
      expect(body['max_tokens'], 512);
      // temperature/penalty 与旧实现保持一致:普通模型无条件携带(值可为默认 0)。
      expect(body['frequency_penalty'], 0);
      // 高级采样仅非默认值携带。
      expect(body.containsKey('min_p'), isFalse);
    });
  });

  group('B2 端点拼接规则', () {
    final provider = _ExposedOpenAi(streamClient: _RecordingClient(<int>[]));

    test('裸域名自动补 /v1', () {
      expect(provider.chatEndpointOf('https://api.x.com'),
          'https://api.x.com/v1/chat/completions');
      expect(provider.modelsEndpointOf('https://api.x.com'),
          'https://api.x.com/v1/models');
    });

    test('尾部斜杠归一', () {
      expect(provider.chatEndpointOf('https://api.x.com/v1/'),
          'https://api.x.com/v1/chat/completions');
    });

    test('路径已含 vX 版本段则不再补(Gemini v1beta / 自建 v2)', () {
      expect(
        provider.chatEndpointOf('https://host/v1beta/openai/'),
        'https://host/v1beta/openai/chat/completions',
      );
      expect(
        provider.chatEndpointOf('https://host/api/v2'),
        'https://host/api/v2/chat/completions',
      );
    });

    test('# 结尾 = 显式原样使用(逃生口)', () {
      expect(
        provider.chatEndpointOf('https://host/weird/path#'),
        'https://host/weird/path/chat/completions',
      );
    });
  });

  group('extractErrorMessage 统一策略', () {
    final provider = _ExposedOpenAi(streamClient: _RecordingClient(<int>[]));

    test('error.message 优先', () {
      expect(
        provider.extractError('{"error":{"message":"boom"}}', 429),
        'HTTP 429: boom',
      );
    });

    test('顶层 message 兜底', () {
      expect(
        provider.extractError('{"message":"top"}', 500),
        'HTTP 500: top',
      );
    });

    test('字符串型 error 节点兜底', () {
      expect(provider.extractError('{"error":"plain"}', 418), 'HTTP 418: plain');
    });

    test('非 JSON 正文截断到 300 字符', () {
      final String long = 'x' * 400;
      final String out = provider.extractError(long, 502);
      expect(out, startsWith('HTTP 502: '));
      expect(out.length, lessThan('HTTP 502: '.length + 301 + 2));
    });
  });

  group('parseOpenAiChatResponse 非流式解析(C3/E-usage)', () {
    final provider = _ExposedOpenAi(streamClient: _RecordingClient(<int>[]));

    ChatCompletionResult parse(String body, {int status = 200}) {
      return provider.parseResponse(
        http.Response(body, status,
            headers: <String, String>{
          'content-type': 'application/json; charset=utf-8'
        }),
      );
    }

    test('成功路径提取 content 与 usage.total_tokens', () {
      final ChatCompletionResult r = parse(jsonEncode(<String, dynamic>{
        'choices': <dynamic>[
          <String, dynamic>{
            'message': <String, dynamic>{'content': ' hello '}
          }
        ],
        'usage': <String, dynamic>{'total_tokens': 42},
      }));
      expect(r.success, isTrue);
      expect(r.content, 'hello');
      expect(r.totalTokens, 42);
    });

    test('错误状态码 → extractErrorMessage', () {
      final ChatCompletionResult r =
          parse('{"error":{"message":"nope"}}', status: 403);
      expect(r.success, isFalse);
      expect(r.errorMessage, 'HTTP 403: nope');
    });

    test('空 choices / 空 content 的中文错误文案', () {
      expect(parse('{"choices":[]}').errorMessage, '模型未返回内容。');
      expect(
        parse(jsonEncode(<String, dynamic>{
          'choices': <dynamic>[
            <String, dynamic>{'message': <String, dynamic>{'content': '  '}}
          ]
        })).errorMessage,
        '返回内容为空。',
      );
    });
  });

  group('AnthropicProvider', () {
    LlmRequest req({int? maxTokens}) => LlmRequest(
          baseUrl: 'https://example.test',
          apiKey: 'key',
          model: 'claude-test',
          messages: const <Map<String, String>>[
            <String, String>{'role': 'user', 'content': 'hi'}
          ],
          maxTokens: maxTokens,
        );

    test('event/data 帧解析:text_delta → 正文,thinking_delta → 思考分片', () async {
      const body = 'event: content_block_delta\n'
          'data: {"delta":{"type":"thinking_delta","thinking":"想"}}\n\n'
          'event: content_block_delta\n'
          'data: {"delta":{"type":"text_delta","text":"Hi"}}\n\n'
          'event: message_stop\n'
          'data: {}\n\n';
      final client = _RecordingClient(utf8.encode(body));
      final provider = AnthropicProvider(streamClient: client);

      final List<LlmStreamChunk> chunks =
          await provider.streamChatCompletion(req()).toList();

      expect(chunks, hasLength(2));
      expect((chunks[0] as LlmReasoningChunk).text, '想');
      expect((chunks[1] as LlmContentChunk).text, 'Hi');

      // 请求体形状:x-api-key / anthropic-version / system 拆出 / 默认 max_tokens。
      final http.Request sent = client.sent.single as http.Request;
      expect(sent.headers['x-api-key'], 'key');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      final Map<String, dynamic> bodyJson =
          jsonDecode(utf8.decode(sent.bodyBytes)) as Map<String, dynamic>;
      expect(bodyJson['max_tokens'], AnthropicProvider.defaultMaxTokens);
      expect(bodyJson['messages'], hasLength(1));
      expect(bodyJson.containsKey('system'), isFalse);
    });

    test('max_tokens 可由 LlmRequest 覆盖(B5/E)', () async {
      final client =
          _RecordingClient(utf8.encode('event: message_stop\ndata: {}\n\n'));
      final provider = AnthropicProvider(streamClient: client);

      await provider.streamChatCompletion(req(maxTokens: 123)).drain<void>();

      final Map<String, dynamic> bodyJson = jsonDecode(
              utf8.decode((client.sent.single as http.Request).bodyBytes))
          as Map<String, dynamic>;
      expect(bodyJson['max_tokens'], 123);
    });

    test('A1 回归:HTTP 非 200 必须以 LlmErrorChunk 收场,而不是 throw', () async {
      final provider = AnthropicProvider(
        streamClient: _RecordingClient(
            utf8.encode('{"error":{"message":"overloaded"}}'),
            statusCode: 500),
      );

      // 旧实现此处直接 throw Exception,导致聊天页 _sending 永久卡死。
      final List<LlmStreamChunk> chunks =
          await provider.streamChatCompletion(req()).toList();

      expect(chunks, hasLength(1));
      expect((chunks.single as LlmErrorChunk).message, contains('overloaded'));
    });

    test('SSE error 事件 → LlmErrorChunk', () async {
      const body = 'event: error\n'
          'data: {"type":"error","error":{"type":"overloaded_error",'
          '"message":"Overloaded"}}\n\n';
      final provider = AnthropicProvider(
        streamClient: _RecordingClient(utf8.encode(body)),
      );

      final List<LlmStreamChunk> chunks =
          await provider.streamChatCompletion(req()).toList();

      expect(chunks.single, isA<LlmErrorChunk>());
      expect((chunks.single as LlmErrorChunk).message, 'Overloaded');
    });
  });
}

/// 记录发出的请求并回放固定字节的假客户端。
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.bytes, {this.statusCode = 200});

  final List<int> bytes;
  final int statusCode;
  final List<http.BaseRequest> sent = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[bytes]),
      statusCode,
    );
  }
}

/// 先推入预置字节、然后保持连接打开的假客户端(验证 [DONE] 早停)。
class _HoldOpenClient extends http.BaseClient {
  _HoldOpenClient(this.controller);

  final StreamController<List<int>> controller;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(controller.stream, 200);
  }
}

/// 只回响应头、body 永不输出也永不关闭的假客户端(模拟断流黑洞)。
class _NeverBodyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final StreamController<List<int>> controller = StreamController<List<int>>();
    // 故意不 close:连接黑洞。
    return http.StreamedResponse(controller.stream, 200);
  }
}

/// 暴露受保护成员供测试;流式客户端经基类构造注入,空闲看门狗调快。
class _ExposedOpenAi extends OpenAiService {
  _ExposedOpenAi({super.streamClient});

  @override
  Duration? get streamIdleTimeout => const Duration(milliseconds: 80);

  SseDecode decodeEvent(String data) => decodeOpenAiEvent(null, data);
  String extractError(String body, int code) => extractErrorMessage(body, code);
  ChatCompletionResult parseResponse(http.Response response) =>
      parseOpenAiChatResponse(response);
  String chatEndpointOf(String base) => chatEndpoint(base);
  String modelsEndpointOf(String base) => modelsEndpoint(base);
}
