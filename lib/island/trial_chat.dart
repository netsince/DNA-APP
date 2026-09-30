import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:dna/models/conversation.dart';

import 'island_card.dart';

/// 「试聊」：把一张角色卡**先聊两句**，再决定要不要收进「我家」。
///
/// 规则（与用户确认）：
/// * 默认走**设置里选定的模型** —— 与正常聊天同一套服务，不额外配置；
/// * 记录**暂存本地**（SharedPreferences）：退出页面再回来还在，但**不会**
///   进「我家」的会话列表，也不算正式数据；
/// * 最多 [maxMessages] 条（用户 + 助手合计）；满了必须二选一：
///   「导入角色卡接着聊」或「返回」（丢弃）；
/// * 导入时把这段记录**原样带进新会话** —— 试聊的内容不白聊。
class TrialChat {
  const TrialChat({required this.card, required this.messages});

  /// 试聊上限（用户 + 助手合计）。改这一个常量即可调整。
  static const int maxMessages = 10;

  final IslandCard card;
  final List<ConversationMessage> messages;

  bool get isFull => messages.length >= maxMessages;

  /// 还能再聊几条。
  int get remaining => maxMessages - messages.length;

  bool get canContinue => !isFull;

  /// 用户消息条数（用于界面显示"第几轮"）。
  int get userTurns =>
      messages.where((ConversationMessage m) => m.role == 'user').length;

  TrialChat copyWith({List<ConversationMessage>? messages}) =>
      TrialChat(card: card, messages: messages ?? this.messages);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'card': <String, dynamic>{
      'id': card.id,
      'name': card.name,
      'gender': card.gender,
      'persona': card.persona,
      'intro': card.intro,
      'opening': card.opening,
      'original_link': card.originalLink,
      'status': card.status,
      'tags': card.tags,
      'author_note': card.authorNote,
      'author_note_interval': card.authorNoteInterval,
      'seed': card.seed,
      'images': card.images,
      'author': <String, dynamic>{
        'nickname': card.authorName,
        'username': card.authorUsername,
      },
      'dialogue': <Map<String, String>>[
        for (final dynamic turn in card.dialogue)
          <String, String>{'user': turn.user, 'assistant': turn.assistant},
      ],
    },
    'messages': <Map<String, dynamic>>[
      for (final ConversationMessage m in messages) m.toJson(),
    ],
  };

  factory TrialChat.fromJson(Map<String, dynamic> json) => TrialChat(
    card: IslandCard.fromJson(
      (json['card'] as Map?)?.map(
            (dynamic k, dynamic v) => MapEntry(k.toString(), v),
          ) ??
          <String, dynamic>{},
    ),
    messages: <ConversationMessage>[
      for (final dynamic m in (json['messages'] as List<dynamic>? ?? <dynamic>[]))
        if (m is Map)
          ConversationMessage.fromJson(
            m.map((dynamic k, dynamic v) => MapEntry(k.toString(), v)),
          ),
    ],
  );
}

/// 试聊记录的本地暂存。
///
/// 刻意用 SharedPreferences 而不是 Hive 会话库：试聊**不是**正式会话，
/// 不该出现在「我家」的会话列表里，也不该进备份 —— 它只是一张临时便签。
class TrialChatStore {
  TrialChatStore._();

  static const String _prefix = 'island_trial_';

  static String _key(String cardId) => '$_prefix$cardId';

  static Future<TrialChat?> load(String cardId) async {
    if (cardId.isEmpty) {
      return null;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key(cardId));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return TrialChat.fromJson(decoded);
    } catch (_) {
      // 记录损坏就当没有，别让一张坏便签挡住功能。
      return null;
    }
  }

  static Future<void> save(TrialChat chat) async {
    if (chat.card.id.isEmpty) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(chat.card.id), jsonEncode(chat.toJson()));
  }

  /// 丢弃这次试聊（「返回」时调用）。
  static Future<void> clear(String cardId) async {
    if (cardId.isEmpty) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(cardId));
  }

  /// 还有哪些卡片的试聊没结束（用于列表上打标）。
  static Future<List<String>> pendingCardIds() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return <String>[
      for (final String key in prefs.getKeys())
        if (key.startsWith(_prefix) && key.length > _prefix.length)
          key.substring(_prefix.length),
    ];
  }
}
