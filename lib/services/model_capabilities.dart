import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

/// 一个模型的能力快照（数据源 models.dev，MIT，见 tools/update_model_capabilities.mjs）。
///
/// 用途只有一个：**给「这个模型能不能吃图片/音频/视频/PDF」一个默认值**。
/// 它不构成判定 —— 用户配置的 baseUrl 后面是什么服务、中转有没有剥掉
/// `image_url`，只有运行时的真实请求知道。所以这里的任何结论都可以被
/// 用户设置覆盖，也必须允许被一次失败请求推翻。
class ModelCapability {
  const ModelCapability({
    required this.image,
    required this.audio,
    required this.video,
    required this.pdf,
    required this.contextWindow,
    required this.toolCall,
    required this.reasoning,
    required this.fromSnapshot,
  });

  final bool image;
  final bool audio;
  final bool video;
  final bool pdf;

  /// 上下文窗口（0 表示快照没给）。
  final int contextWindow;

  final bool toolCall;
  final bool reasoning;

  /// 是否来自内置快照（false = 名字启发式的猜测，可信度更低）。
  final bool fromSnapshot;

  @override
  String toString() =>
      'ModelCapability(image: $image, ctx: $contextWindow, snapshot: $fromSnapshot)';
}

/// 模型能力快照：懒加载 assets/data/model_capabilities.json.gz（约 70KB）。
///
/// 只在需要判断「能否传图」时读一次，之后常驻内存；资产缺失或解析失败时
/// 退化成纯启发式，不抛异常（宁可保守，也不能让聊天页打不开）。
class ModelCapabilities {
  ModelCapabilities._();

  static final ModelCapabilities instance = ModelCapabilities._();

  Map<String, ModelCapability>? _byId;
  bool _loaded = false;

  /// 注入内存快照（测试用；传 null 表示卸载）。
  void debugLoadFrom(Map<String, ModelCapability>? table) {
    _byId = table;
    _loaded = true;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final ByteData data =
          await rootBundle.load('assets/data/model_capabilities.json.gz');
      final List<int> raw = GZipDecoder().decodeBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      _byId = _parse(utf8.decode(raw));
    } catch (_) {
      // 资产缺失/损坏：留空表，查不到就走启发式。
      _byId = <String, ModelCapability>{};
    }
  }

  /// 同步查表（未加载时返回 null，调用方应先 [ensureLoaded]）。
  ///
  /// 匹配顺序：精确 id → 去 provider 前缀 → 归一化（去日期/版本后缀）。
  ModelCapability? lookup(String modelName) {
    final Map<String, ModelCapability>? table = _byId;
    if (table == null || table.isEmpty) return null;
    final String raw = modelName.trim().toLowerCase();
    if (raw.isEmpty) return null;
    final ModelCapability? exact = table[raw];
    if (exact != null) return exact;
    final String bare = stripProvider(raw);
    final ModelCapability? bareHit = table[bare];
    if (bareHit != null) return bareHit;
    final String normalized = normalizeModelId(raw);
    return table[normalized] ?? table[normalizeModelId(bare)];
  }

  /// 完整查询：快照优先，查不到用名字启发式兜底。
  ModelCapability resolve(String modelName) {
    return lookup(modelName) ?? heuristicCapability(modelName);
  }

  static Map<String, ModelCapability> _parse(String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) return <String, ModelCapability>{};
    final Object? models = decoded['models'];
    if (models is! Map<String, dynamic>) return <String, ModelCapability>{};
    final Map<String, ModelCapability> out = <String, ModelCapability>{};
    models.forEach((String id, Object? value) {
      if (value is! List || value.length < 7) return;
      int at(int i) => value[i] is num ? (value[i] as num).toInt() : 0;
      out[id] = ModelCapability(
        image: at(0) == 1,
        audio: at(1) == 1,
        video: at(2) == 1,
        pdf: at(3) == 1,
        contextWindow: at(4),
        toolCall: at(5) == 1,
        reasoning: at(6) == 1,
        fromSnapshot: true,
      );
    });
    return out;
  }
}

/// 去掉 `provider/` 前缀（`openai/gpt-4o` → `gpt-4o`）。
String stripProvider(String id) {
  final int slash = id.indexOf('/');
  return slash < 0 ? id : id.substring(slash + 1);
}

/// 归一化模型 id：小写、去 provider 前缀、去日期后缀、去 -latest/preview。
///
/// 必须与 tools/update_model_capabilities.mjs 里的同名函数保持一致，
/// 否则快照里的 key 与运行时查的 key 对不上（有测试守着）。
String normalizeModelId(String raw) {
  String id = raw.trim().toLowerCase();
  if (id.isEmpty) return '';
  id = stripProvider(id);
  id = id.replaceAll(
    RegExp(r'[-@](?:20\d{2}-?\d{2}-?\d{2}|20\d{6})$'),
    '',
  );
  id = id.replaceAll(RegExp(r'-(?:latest|preview|stable)$'), '');
  return id;
}

/// 名字启发式：仅在没有快照命中时用，**只用于给默认值**。
///
/// 判据是"名字里带视觉家族特征"，宁可漏判也不能误判（误判会让用户点上传
/// 才发现模型不收图）。命中返回 image=true 且 [ModelCapability.fromSnapshot]
/// 为 false，界面据此显示"（推断）"这类弱提示。
ModelCapability heuristicCapability(String modelName) {
  final String id = modelName.toLowerCase();
  bool has(List<String> needles) => needles.any(id.contains);
  final bool vision = has(<String>[
    'gpt-4o', 'gpt-4.1', 'gpt-5', 'o3', 'o4-mini',
    'claude-3', 'claude-4', 'claude-sonnet', 'claude-opus', 'claude-haiku',
    'gemini', 'gemma-3',
    'qwen-vl', 'qwen2-vl', 'qwen2.5-vl', 'qwen3-vl', 'qvq',
    'glm-4v', 'glm-4.5v', 'glm-4.1v',
    'llava', 'pixtral', 'internvl', 'minicpm-v', 'vision', 'multimodal',
    'step-1v', 'yi-vl', 'doubao-vision', 'moonshot-v1-vision',
  ]);
  return ModelCapability(
    image: vision,
    audio: false,
    video: false,
    pdf: false,
    contextWindow: 0,
    toolCall: false,
    reasoning: false,
    fromSnapshot: false,
  );
}
