import 'package:dna/island_app/api/client.dart';

/// 社区热门标签，给世界卡编辑器的标签候选用。
///
/// **只允许社区页面调用**。本体（主应用）的世界/角色卡编辑器不得请求它：
/// 那会让「打开本地编辑器」变成一次社区请求 —— 既破坏本体离线可用的前提，
/// 也不受「关闭社区」开关的约束。
Future<List<String>> loadWorldTagSuggestions() async {
  try {
    final tags = await ApiClient.instance.getWorldTags();
    return tags.map((t) => t.tag).toList();
  } catch (_) {
    // 拉不到就不给候选，不影响填写与发布。
    return const <String>[];
  }
}
