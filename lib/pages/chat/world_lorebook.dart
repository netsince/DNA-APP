import '../../models/world.dart';

/// Lorebook（世界信息动态激活）：
/// 把世界里的词条当作"知识条目"，根据当前对话文本中是否出现词条名来决定
/// 是否把该词条的描述注入提示词。这样世界背景从"一次性静态背景"变成
/// "按剧情动态召回的活知识库"。
class WorldLorebook {
  /// 从 [world] 中召回命中的词条：
  /// 词条 [WorldEntry.name] 出现在 [text]（最近对话文本）中即视为命中。
  /// 返回按原顺序排列的命中列表，去重，最多 [maxEntries] 条，防止撑爆上下文。
  static List<WorldEntry> match(World? world, String text, {int maxEntries = 5}) {
    if (world == null || world.entries.isEmpty || text.trim().isEmpty) {
      return <WorldEntry>[];
    }
    final String lowerText = text.toLowerCase();
    final List<WorldEntry> hits = <WorldEntry>[];
    for (final WorldEntry entry in world.entries) {
      final String name = entry.name.trim();
      if (name.isEmpty) {
        continue;
      }
      if (lowerText.contains(name.toLowerCase())) {
        hits.add(entry);
        if (hits.length >= maxEntries) {
          break;
        }
      }
    }
    return hits;
  }

  /// 把命中的词条格式化为注入提示词的文本。无有效描述时返回空串。
  static String format(List<WorldEntry> entries) {
    final List<WorldEntry> withContent = entries
        .where((WorldEntry e) => e.description.trim().isNotEmpty)
        .toList();
    if (withContent.isEmpty) {
      return '';
    }
    final StringBuffer sb = StringBuffer('当前激活的世界知识（与当前对话场景相关，供参考，请勿复述）：');
    for (final WorldEntry e in withContent) {
      sb.write('\n- ${e.name}：${e.description.trim()}');
    }
    return sb.toString();
  }
}
