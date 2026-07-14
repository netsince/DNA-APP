/// 全局检索结果类型
enum SearchResultKind {
  /// 角色（TA）
  ta,

  /// 世界背景
  world,

  /// 会话（按标题/备注命中）
  conversation,

  /// 消息（消息正文命中，带片段）
  message,
}

/// 全局检索结果项
class SearchResult {
  const SearchResult({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    this.snippet,
    this.taId,
    this.worldId,
    this.conversationId,
  });

  final SearchResultKind kind;

  /// 唯一标识（消息为「会话id#消息id」）
  final String id;

  /// 主标题（角色名 / 世界名 / 会话标题）
  final String title;

  /// 副标题（简介 / TA·世界）
  final String subtitle;

  /// 命中片段（仅消息类型有值）
  final String? snippet;

  final String? taId;
  final String? worldId;
  final String? conversationId;
}
