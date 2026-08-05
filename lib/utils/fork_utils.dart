import '../models/conversation.dart';
import 'id_utils.dart';

/// 以 [source] 会话为基底，在 [index] 处构建一个「分叉」会话。
///
/// 分叉会话保留到该消息为止的内容，另起新 ID；备注前追加「分叉的.」前缀；
/// 只保留分叉点之前已生成的摘要。索引越界时返回 null。
Conversation? buildForkConversation(
  Conversation source,
  int index, {
  required Set<String> existingIds,
}) {
  if (index < 0 || index >= source.messages.length) {
    return null;
  }
  final List<ConversationMessage> kept =
      source.messages.take(index + 1).toList();
  final Set<String> keptIds =
      kept.map((ConversationMessage m) => m.id).toSet();
  final List<ConversationSummary> keptSummaries = source.summaries
      .where((ConversationSummary s) => keptIds.contains(s.endMessageId))
      .toList();

  String forkId = newId();
  while (existingIds.contains(forkId)) {
    forkId = newId();
  }

  return Conversation(
    id: forkId,
    taId: source.taId,
    worldId: source.worldId,
    identityId: source.identityId,
    note: '分叉的.${source.note}',
    messages: kept,
    backgroundMode: source.backgroundMode,
    summaries: keptSummaries,
    archived: false,
    isGroup: source.isGroup,
    groupName: source.groupName,
    groupPrompt: source.groupPrompt,
    memberTaIds: source.memberTaIds,
    activeTaId: source.activeTaId,
  );
}
