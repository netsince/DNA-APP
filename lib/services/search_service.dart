import '../models/conversation.dart';
import '../models/search_result.dart';
import '../models/ta.dart';
import '../models/world.dart';

/// 全局检索：跨角色、世界、会话与消息正文匹配。
///
/// [query] 为空时返回空列表；匹配忽略大小写。
/// [conversations] 应同时包含单聊与群聊。
List<SearchResult> searchGlobal({
  required String query,
  required List<TA> tas,
  required List<World> worlds,
  required List<Conversation> conversations,
}) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return const <SearchResult>[];
  }

  final Map<String, TA> taById = <String, TA>{for (final TA t in tas) t.id: t};
  final Map<String, World> worldById =
      <String, World>{for (final World w in worlds) w.id: w};

  final List<SearchResult> results = <SearchResult>[];

  // 角色：匹配名称、人设、简介、开场白、标签
  for (final TA ta in tas) {
    final String hay = <String>[
      ta.name,
      ta.persona,
      ta.intro,
      ta.opening,
      ...ta.tags,
    ].join('\n').toLowerCase();
    if (hay.contains(q)) {
      results.add(SearchResult(
        kind: SearchResultKind.ta,
        id: ta.id,
        title: ta.name.isEmpty ? '未命名TA' : ta.name,
        subtitle: ta.intro.isEmpty ? '暂无介绍' : ta.intro,
        taId: ta.id,
      ));
    }
  }

  // 世界：匹配名称、简介、描述、标签、词条名与词条描述
  for (final World w in worlds) {
    final String entries =
        w.entries.map((WorldEntry e) => '${e.name}\n${e.description}').join('\n');
    final String hay = <String>[
      w.name,
      w.summary,
      w.description,
      ...w.tags,
      entries,
    ].join('\n').toLowerCase();
    if (hay.contains(q)) {
      results.add(SearchResult(
        kind: SearchResultKind.world,
        id: w.id,
        title: w.name.isEmpty ? '未命名世界' : w.name,
        subtitle: w.summary.isEmpty ? '暂无简介' : w.summary,
        worldId: w.id,
      ));
    }
  }

  // 会话与消息
  for (final Conversation c in conversations) {
    final TA? ta = c.taId.isNotEmpty ? taById[c.taId] : null;
    final World? world = worldById[c.worldId ?? ''];
    final String title = c.note.isNotEmpty
        ? c.note
        : (c.isGroup
            ? (c.groupName.isNotEmpty ? c.groupName : '未命名群聊')
            : (ta?.name.isNotEmpty == true ? ta!.name : '未命名会话'));
    final String sub = world == null
        ? 'TA：${ta?.name.isNotEmpty == true ? ta!.name : '未命名TA'}'
        : 'TA：${ta?.name.isNotEmpty == true ? ta!.name : '未命名TA'} · 世界：${world.name}';

    final bool titleHit =
        title.toLowerCase().contains(q) || c.note.toLowerCase().contains(q);

    if (titleHit) {
      results.add(SearchResult(
        kind: SearchResultKind.conversation,
        id: c.id,
        title: title,
        subtitle: sub,
        conversationId: c.id,
      ));
    }

    // 消息正文命中：每条生成一个消息结果（带片段），单会话最多取前 5 条
    final List<ConversationMessage> hits =
        c.messages.where((ConversationMessage m) => m.text.toLowerCase().contains(q)).toList();
    for (final ConversationMessage m in hits.take(5)) {
      results.add(SearchResult(
        kind: SearchResultKind.message,
        id: '${c.id}#${m.id}',
        title: title,
        subtitle: sub,
        snippet: _snippet(m.text, q),
        conversationId: c.id,
      ));
    }
  }

  return results;
}

/// 生成命中片段：以匹配位置为中心截取，前后各约 20 字，超出则加省略号。
String _snippet(String text, String q) {
  final String lower = text.toLowerCase();
  final int idx = lower.indexOf(q);
  if (idx < 0) {
    return text;
  }
  final int start = (idx - 20).clamp(0, text.length);
  final int end = (idx + q.length + 20).clamp(0, text.length);
  final String prefix = start > 0 ? '…' : '';
  final String suffix = end < text.length ? '…' : '';
  return '$prefix${text.substring(start, end)}$suffix';
}
