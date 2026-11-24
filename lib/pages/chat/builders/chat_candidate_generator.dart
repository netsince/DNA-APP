import 'package:dna/models/service_results.dart';
import 'package:dna/state/app_controller.dart';

/// 生成一批「候选回复」。
///
/// 四个调用点（重说并发 / 重说串行 / 灵感并发 / 灵感串行）原本各写一遍同样的
/// 循环与失败处理，差别只有三处：条数、要不要错峰、结果怎么清洗。
///
/// 统一后的语义：
/// * **失败一律吞掉**：候选不是关键路径，某一条挂了就是少一条，不影响其他；
/// * **空串过滤**（只含空白的也算空）；
/// * [transform] 由调用方给：「重说」剥模型自带「名字：」前缀，「灵感」剥思考标签；
/// * [stagger] 只在并发模式生效：第 i 条先等 i × stagger，降低同时触发的限流概率。
///
/// 注意 [transform] **不给默认值**：两种清洗混用会让灵感里出现「名字：」，
/// 或让群聊候选带着思考标签入库，滚成「名字：名字：」。
Future<List<String>> generateChatCandidates({
  required AppController controller,
  required List<Map<String, dynamic>> payload,
  required bool sequential,
  int count = 3,
  Duration stagger = const Duration(milliseconds: 300),
  String Function(String raw)? transform,
}) async {
  String cleaned(String raw) => transform == null ? raw : transform(raw);

  Future<String?> fetchOnce() async {
    final ChatCompletionResult result =
        await controller.llmProvider.createChatCompletion(
      controller.buildLlmRequest(messages: payload),
    );
    if (!result.success || result.content == null) {
      return null;
    }
    final String value = cleaned(result.content!);
    return value.trim().isEmpty ? null : value;
  }

  if (sequential) {
    final List<String> results = <String>[];
    for (int i = 0; i < count; i++) {
      try {
        final String? value = await fetchOnce();
        if (value != null) {
          results.add(value);
        }
      } catch (_) {
        // 单条失败不影响后面的候选。
      }
    }
    return results;
  }

  try {
    final List<Future<String?>> tasks = List<Future<String?>>.generate(
      count,
      (int i) async {
        if (i > 0 && stagger > Duration.zero) {
          await Future<void>.delayed(stagger * i);
        }
        try {
          return await fetchOnce();
        } catch (_) {
          return null;
        }
      },
    );
    final List<String?> settled = await Future.wait(tasks);
    return settled.whereType<String>().toList();
  } catch (_) {
    return <String>[];
  }
}
