import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show protected;
import 'package:http/http.dart' as http;

import '../models/service_results.dart';
import 'llm_provider.dart';
import 'llm_request.dart';
import 'llm_stream_chunk.dart';

/// 解码一帧 SSE 事件的结果:[chunks] 为产出分片,[done] 表示请求终止。
class SseDecode {
  const SseDecode({this.chunks = const <LlmStreamChunk>[], this.done = false});

  final List<LlmStreamChunk> chunks;
  final bool done;
}

/// LLM HTTP 适配器统一基类(中间件层)。
///
/// 收口的横切逻辑(历史上四家适配器各自实现导致行为漂移):
///
/// - **流式失败契约**:任何传输层失败以 [LlmErrorChunk] 收场,绝不抛异常;
/// - **超时**:轻量 GET 12s / 补全握手 20s / SSE 空闲看门狗 120s;
/// - **真取消(A5)**:每条流使用独立 `http.Client`,在 generator 的
///   `finally` 中关闭——消费方 break 取消订阅时连接被硬性拆除,
///   服务端生成随之中断;
/// - **SSE 规范**:event/data 帧、多行 data 拼接、注释行跳过;
/// - **能力矩阵(B1)**:reasoning 系模型(o1/o3/gpt-5/reasoner/qwq/r1 等)
///   自动省略 temperature/penalty 类采样参数;
/// - **端点规则(B2)**:baseUrl 以 `#` 结尾 = 显式"原样使用";
///   路径已含 vX 版本段(如 Gemini 的 v1beta/openai)不再补 /v1;
/// - **错误文案提取**:`error.message` > `message` > 字符串 error > 截断正文。
abstract class LlmServiceBase implements LlmProvider {
  LlmServiceBase({http.Client? client, http.Client? streamClient})
      : client = client ?? http.Client(),
        injectedStreamClient = streamClient;

  /// 共享 HTTP 客户端(用于轻量 GET 与非流式补全);测试可注入替身。
  ///
  /// 流式补全不使用它:每条流创建独立客户端并在 finally 中关闭,
  /// 保证取消订阅时连接被真正拆除而非归还连接池继续跑完服务端生成。
  @protected
  final http.Client client;

  /// 流式专用客户端的测试注入口;null 时由 [createStreamClient] 新建。
  @protected
  final http.Client? injectedStreamClient;

  /// 轻量 GET(连通性校验 / 模型列表)的统一总时长上限。
  @protected
  static const Duration validateTimeout = Duration(seconds: 12);

  /// 补全请求的统一超时。
  ///
  /// 流式场景下仅守护到「响应头到达」为止(http 包语义),body/SSE 阶段由
  /// [streamIdleTimeout] 看护;非流式场景挂在整个请求上,即总时长上限。
  @protected
  static const Duration completionTimeout = Duration(seconds: 20);

  /// SSE body 的空闲看门狗:连续这么久没有任何数据行即判定断流,
  /// 以 [LlmErrorChunk] 结束本次生成,避免消费方无限挂起。
  /// 取值需宽于推理模型的合法静默期;子类可覆写,null 关闭(不建议)。
  @protected
  Duration? get streamIdleTimeout => const Duration(seconds: 120);

  /// 释放共享连接。App 生命周期内通常无需调用。
  void close() => client.close();

  /// 创建流式补全专用的 HTTP 客户端。生产环境返回全新实例;
  /// 测试可覆写以注入假客户端。
  @protected
  http.Client createStreamClient() =>
      injectedStreamClient ?? http.Client();

  // ---------------- 能力矩阵(B1) ----------------

  /// 采样参数被服务端锁死(只接受默认值)的模型族。
  /// 命中即不发 temperature/frequency_penalty/presence_penalty/top_p/...
  static final RegExp _samplingLockedModelPattern = RegExp(
    r'(?:^|[^a-z0-9])(o[134](?:-|\.|$)|gpt-5|reasoner|qwq|deepseek-r1|glm-z)',
    caseSensitive: false,
  );

  /// 该模型是否接受自定义采样参数。o1/o3/gpt-5/deepseek-reasoner/
  /// qwq/r1/glm-z 系端点对非默认采样直接报 400。
  static bool supportsSamplingControls(String model) {
    return !_samplingLockedModelPattern.hasMatch(model.trim().toLowerCase());
  }

  // ---------------- 模板方法:厂商差异点 ----------------

  /// GET /models 端点(完整 URL)。
  @protected
  String modelsEndpoint(String baseUrl);

  /// Chat 补全端点(完整 URL;流式与非流式共用)。
  @protected
  String chatEndpoint(String baseUrl);

  /// 通用请求头(鉴权 + Content-Type)。
  @protected
  Map<String, String> buildHeaders(String apiKey);

  // ---------------- 统一实现:错误提取 ----------------

  /// 从错误响应体提取人类可读信息,统一带 `HTTP <code>:` 前缀。
  ///
  /// 策略:`error.message` > 顶层 `message` > 字符串型 `error`
  /// > 原始正文兜底(截断到 300 字符,避免长 HTML 刷屏)。
  @protected
  String extractErrorMessage(String responseBody, int statusCode) {
    String? message;
    try {
      final Object? decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final Object? errorNode = decoded['error'];
        if (errorNode is Map<String, dynamic>) {
          final Object? m = errorNode['message'];
          if (m is String && m.trim().isNotEmpty) {
            message = m.trim();
          }
        }
        if (message == null && decoded['message'] is String) {
          final String m = decoded['message'] as String;
          if (m.trim().isNotEmpty) {
            message = m.trim();
          }
        }
        if (message == null && errorNode is String && errorNode.trim().isNotEmpty) {
          message = errorNode.trim();
        }
      }
    } catch (_) {
      // 非 JSON 正文,走原始文本兜底。
    }
    message ??= responseBody.trim();
    if (message.isEmpty) {
      message = '请求失败。';
    }
    if (message.length > 300) {
      message = '${message.substring(0, 300)}…';
    }
    return 'HTTP $statusCode: $message';
  }

  // ---------------- 统一实现:轻量 GET 与探针解释(B3/B4) ----------------

  /// 带 [validateTimeout] 的 GET(连通性校验 / 模型列表共用)。
  @protected
  Future<http.Response> getWithTimeout(Uri uri, Map<String, String> headers) {
    return client.get(uri, headers: headers).timeout(validateTimeout);
  }

  /// 解释「GET /models」探测结果(B3):
  /// 200 = 成功;404/405 = 服务端不提供列表但连通正常 → 放行并注明;
  /// 其余按错误处理(401/403 仍能拦住填错 Key 的用户)。
  @protected
  ApiCheckResult interpretModelsProbe(http.Response response) {
    if (response.statusCode == 200) {
      return const ApiCheckResult(success: true, message: '连接验证成功。');
    }
    if (response.statusCode == 404 || response.statusCode == 405) {
      return const ApiCheckResult(
        success: true,
        message: '连接成功(服务端未提供 /models 列表,已跳过该项校验)。',
      );
    }
    return ApiCheckResult(
      success: false,
      message: extractErrorMessage(response.body, response.statusCode),
    );
  }

  /// 从模型列表响应中容忍多种形状地提取 id 列表(B4):
  /// `[{"id":..}]` 裸数组、`{"data":[{"id":..}]}`(OpenAI 形)、
  /// `{"models":[{"id":..}]}`(部分网关形)。空列表表示无法提取。
  @protected
  List<String> extractModelIds(Object? decoded) {
    List<dynamic>? raw;
    if (decoded is List<dynamic>) {
      raw = decoded;
    } else if (decoded is Map<String, dynamic>) {
      raw = (decoded['data'] ?? decoded['models']) as List<dynamic>?;
    }
    if (raw == null) {
      return const <String>[];
    }
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> e) => e['id'])
        .whereType<String>()
        .where((String s) => s.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  // ---------------- 统一实现:OpenAI 非流式响应解析(C3/E-usage) ----------------

  /// 解析 OpenAI 兼容的非流式 chat 响应(OpenAI/智谱/DeepSeek 共用)。
  /// 同时捕获 usage.total_tokens([ChatCompletionResult.totalTokens],E)。
  @protected
  ChatCompletionResult parseOpenAiChatResponse(http.Response response) {
    if (response.statusCode != 200) {
      return ChatCompletionResult(
        success: false,
        errorMessage: extractErrorMessage(response.body, response.statusCode),
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      return const ChatCompletionResult(success: false, errorMessage: '返回格式无效。');
    }
    if (decoded is! Map<String, dynamic>) {
      return const ChatCompletionResult(success: false, errorMessage: '返回格式无效。');
    }
    final Object? choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      return const ChatCompletionResult(success: false, errorMessage: '模型未返回内容。');
    }
    final Object? message = (choices.first as Map<String, dynamic>)['message'];
    if (message is! Map<String, dynamic>) {
      return const ChatCompletionResult(success: false, errorMessage: '返回内容缺失。');
    }
    final String? content = message['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      return const ChatCompletionResult(success: false, errorMessage: '返回内容为空。');
    }
    int? totalTokens;
    final Object? usage = decoded['usage'];
    if (usage is Map<String, dynamic>) {
      final Object? t = usage['total_tokens'];
      if (t is int) {
        totalTokens = t;
      } else if (t is num) {
        totalTokens = t.toInt();
      }
    }
    return ChatCompletionResult(
      success: true,
      content: content.trim(),
      totalTokens: totalTokens,
    );
  }

  // ---------------- 统一实现:SSE 流式管线(A3/A5/C1) ----------------

  /// 打开一条 SSE 流并按 [decodeEvent] 解码为类型化分片。
  ///
  /// 传输保障(全部收口在此):
  /// 1. 每流独立 `http.Client`,`finally` 中关闭 → 消费方取消订阅即硬断连(A5);
  /// 2. 握手超时([completionTimeout]);
  /// 3. 非 200 → 读出错误体产出 [LlmErrorChunk];
  /// 4. 空闲看门狗([streamIdleTimeout])→ 断流产 [LlmErrorChunk] 而非永挂;
  /// 5. 任何异常 → [LlmErrorChunk] 兜底。
  ///
  /// SSE 规范细节:event 行记名;data 行可多行(以 \n 拼);空行派发事件;
  /// `:` 开头注释行跳过;[SseDecode.done] 为真时立即终止读取。
  @protected
  Stream<LlmStreamChunk> pumpSse({
    required http.Request request,
    required SseDecode Function(String? event, String data) decodeEvent,
  }) async* {
    final http.Client streamClient = createStreamClient();
    try {
      final http.StreamedResponse response =
          await streamClient.send(request).timeout(completionTimeout);
      if (response.statusCode != 200) {
        final String body = await response.stream.bytesToString();
        yield LlmErrorChunk(extractErrorMessage(body, response.statusCode));
        return;
      }
      Stream<String> lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final Duration? idle = streamIdleTimeout;
      if (idle != null) {
        lines = lines.timeout(idle);
      }

      String? eventName;
      final StringBuffer dataBuf = StringBuffer();
      try {
        await for (final String line in lines) {
          if (line.isEmpty) {
            if (dataBuf.isNotEmpty) {
              final String data = dataBuf.toString();
              final String? ev = eventName;
              dataBuf.clear();
              eventName = null;
              final SseDecode result = decodeEvent(ev, data);
              for (final LlmStreamChunk c in result.chunks) {
                yield c;
              }
              if (result.done) {
                return;
              }
            }
            continue;
          }
          if (line.startsWith(':')) {
            continue; // SSE 注释/心跳行
          }
          if (line.startsWith('event:')) {
            eventName = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            if (dataBuf.isNotEmpty) {
              dataBuf.write('\n'); // 多行 data 按规范拼接
            }
            dataBuf.write(line.substring(5).trimLeft());
          }
        }
        // 流结束但缓冲里还有未派发的事件。
        if (dataBuf.isNotEmpty) {
          final SseDecode result = decodeEvent(eventName, dataBuf.toString());
          for (final LlmStreamChunk c in result.chunks) {
            yield c;
          }
        }
      } catch (error) {
        // 含空闲看门狗触发的 TimeoutException:断流按错误收场而非无限挂起。
        yield LlmErrorChunk('连接中断:$error');
      }
    } catch (error) {
      yield LlmErrorChunk('请求失败:$error');
    } finally {
      // 无论正常结束还是被消费方取消订阅,都硬关闭这条流的独立连接。
      streamClient.close();
    }
  }

  /// OpenAI 兼容 SSE 事件的通用解码:data=[DONE] 终止;
  /// delta.content → 正文;delta.reasoning_content → 思考分片;
  /// finish_reason=length → 追加长度上限提示(E);
  /// 畸形 JSON 静默忽略(与既有行为一致)。
  @protected
  SseDecode decodeOpenAiEvent(String? event, String data) {
    if (data == '[DONE]') {
      return const SseDecode(done: true);
    }
    try {
      final Object? decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        return const SseDecode();
      }
      final Object? choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        return const SseDecode();
      }
      final Map<String, dynamic> first = choices.first as Map<String, dynamic>;
      final Object? delta = first['delta'];
      final List<LlmStreamChunk> chunks = <LlmStreamChunk>[];
      if (delta is Map<String, dynamic>) {
        final Object? reasoning = delta['reasoning_content'];
        if (reasoning is String && reasoning.isNotEmpty) {
          chunks.add(LlmReasoningChunk(reasoning));
        }
        final Object? content = delta['content'];
        if (content is String && content.isNotEmpty) {
          chunks.add(LlmContentChunk(content));
        }
      }
      final Object? finishReason = first['finish_reason'];
      if (finishReason == 'length') {
        chunks.add(const LlmNoticeChunk('回复因达到 max_tokens 上限被截断。'));
      }
      return SseDecode(chunks: chunks);
    } catch (_) {
      return const SseDecode();
    }
  }

  /// OpenAI 兼容补全的公共请求体(流式/非流式共用):
  /// 采样参数仅在模型支持时携带(B1 能力矩阵),高级参数仅非默认值携带,
  /// DeepSeek 思考字段仅在显式传入时携带,max_tokens 仅在配置时发送(B5)。
  @protected
  Map<String, dynamic> buildOpenAiCompatibleBody(
    LlmRequest request, {
    bool stream = false,
    bool includeSampling = true,
  }) {
    final bool samplingAllowed =
        includeSampling && supportsSamplingControls(request.model);
    return <String, dynamic>{
      'model': request.model,
      'messages': request.messages,
      if (samplingAllowed) ...<String, dynamic>{
        'temperature': request.temperature,
        'frequency_penalty': request.frequencyPenalty,
        'presence_penalty': request.presencePenalty,
        ..._openAiSamplingBody(request),
      },
      if (request.maxTokens != null) 'max_tokens': request.maxTokens,
      if (stream) 'stream': true,
      ...deepSeekThinkingBody(
        thinkingType: request.thinkingType,
        reasoningEffort: request.reasoningEffort,
      ),
    };
  }

  /// 组装 DeepSeek 思考模式相关字段(仅显式传入时携带)。
  @protected
  Map<String, dynamic> deepSeekThinkingBody({
    required String? thinkingType,
    required String? reasoningEffort,
  }) {
    return <String, dynamic>{
      if (thinkingType != null) 'thinking': <String, dynamic>{'type': thinkingType},
      if (reasoningEffort != null && reasoningEffort.isNotEmpty)
        'reasoning_effort': reasoningEffort,
    };
  }

  /// 高级采样参数:仅非默认值时携带(top_p/top_k/min_p/rep/slope)。
  Map<String, dynamic> _openAiSamplingBody(LlmRequest r) {
    return <String, dynamic>{
      if (r.topP != 1.0) 'top_p': r.topP,
      if (r.topK > 0) 'top_k': r.topK,
      if (r.minP > 0) 'min_p': r.minP,
      if (r.repetitionPenalty != 1.0) 'repetition_penalty': r.repetitionPenalty,
      if (r.repetitionPenaltySlope != 0.0)
        'repetition_penalty_slope': r.repetitionPenaltySlope,
    };
  }

  /// OpenAI 兼容端点的标准流式泵。
  /// OpenAI / 智谱 / DeepSeek(继承 OpenAI 实现)共用。
  @protected
  Stream<LlmStreamChunk> streamOpenAiCompatible(LlmRequest request) {
    final Uri endpoint = Uri.parse(chatEndpoint(request.baseUrl));
    final http.Request req = http.Request('POST', endpoint)
      ..headers.addAll(buildHeaders(request.apiKey))
      ..body = jsonEncode(buildOpenAiCompatibleBody(request, stream: true));
    return pumpSse(request: req, decodeEvent: decodeOpenAiEvent);
  }

  // ---------------- 统一实现:端点规则(B2) ----------------

  /// 解析 baseUrl:返回是否为 `#` 显式模式以及去尾斜杠后的根地址。
  ({String root, bool explicitRoot}) _splitBase(String baseUrl) {
    String s = baseUrl.trim();
    final bool explicitRoot = s.endsWith('#');
    if (explicitRoot) {
      s = s.substring(0, s.length - 1);
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return (root: s, explicitRoot: explicitRoot);
  }

  /// 路径中是否已含版本段(v+数字开头,如 v1/v2/v4/v1beta)。
  bool _hasVersionSegment(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    final RegExp pattern = RegExp(r'^v\d+');
    for (final String segment in uri.pathSegments) {
      if (pattern.hasMatch(segment.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// OpenAI 兼容端点拼接规则:
  /// - `#` 结尾:整个 URL 原样使用(去掉 #),适合任意非标准路径;
  /// - 路径已含 vX 版本段(Gemini `/v1beta/openai`、自建 `/v2` 等):原样拼接;
  /// - 其余:自动补 `/v1`(经典 OpenAI 兼容语义)。
  @protected
  String joinOpenAiEndpoint(String baseUrl, String suffix) {
    final (:root, :explicitRoot) = _splitBase(baseUrl);
    if (explicitRoot || _hasVersionSegment(root)) {
      return '$root$suffix';
    }
    return '$root/v1$suffix';
  }
}
