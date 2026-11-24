import 'package:flutter/widgets.dart';
import '../models/ta.dart';

import 'package:dna/models/conversation.dart';
import 'package:dna/state/app_controller.dart';

/// 一条聊天的「标签」文案。
///
/// 规则:备注优先;没有备注就用该会话里**最后一条用户消息的前 5 个字 +
/// 省略号**(不足 5 个字不加省略号);一条用户消息都没有时给「新对话」。
///
/// 侧栏与角色展示页共用这一份 —— 同一条聊天在两处长得一样。
String conversationLabel(Conversation conversation) {
  final String note = conversation.note.trim();
  if (note.isNotEmpty) {
    return note;
  }
  for (int i = conversation.messages.length - 1; i >= 0; i--) {
    final ConversationMessage message = conversation.messages[i];
    if (message.role != 'user') {
      continue;
    }
    // 换行/连续空白压成单空格,免得标签里出现折行空洞。
    final String text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) {
      continue;
    }
    final Characters chars = text.characters;
    final String head = chars.take(5).toString();
    return chars.length > 5 ? '$head…' : head;
  }
  return '新对话';
}

/// 最后一条消息的时间(毫秒);没有消息返回 0。
int lastMessageAt(Conversation conversation) =>
    conversation.messages.isEmpty ? 0 : conversation.messages.last.timestamp;

/// 某个角色的非归档 1:1 聊天:置顶优先,其余按最近消息在前。
///
/// 会话模型没有"更新时间"字段,只能从消息列表末条取时间;老数据该字段
/// 可能被反序列化成 0,所以取最大值比较,全为 0 时退化成列表顺序。
List<Conversation> conversationsOfTa(AppController controller, String taId) {
  final List<Conversation> chats = <Conversation>[
    for (final Conversation conversation in controller.conversations)
      if (!conversation.isGroup &&
          !conversation.archived &&
          conversation.taId == taId)
        conversation,
  ];
  chats.sort((Conversation a, Conversation b) {
    if (a.pinned != b.pinned) {
      return a.pinned ? -1 : 1;
    }
    return lastMessageAt(b).compareTo(lastMessageAt(a));
  });
  return chats;
}

/// 有聊天的角色：按 [AppController.tas] 的顺序，只保留有**非归档 1:1 会话**的角色。
///
/// 群聊不算：左右滑动与侧栏左列都只按「角色」组织，群聊另有入口。
/// 聊天页的左右滑动与侧栏左列原本各写一遍这段（逐字相同）。
List<TA> charactersWithChats(AppController controller) {
  final Set<String> withChats = <String>{
    for (final Conversation conversation in controller.conversations)
      if (!conversation.isGroup && !conversation.archived) conversation.taId,
  };
  return <TA>[
    for (final TA ta in controller.tas)
      if (withChats.contains(ta.id)) ta,
  ];
}

/// 该角色**时间上最近**的非归档 1:1 会话；没有则 null。
///
/// 与 [conversationsOfTa] 的区别（别合并）：那个是「置顶优先 + 最近在前」的
/// 列表，给侧栏右列用；这里只回答「左右滑动切到这个人时该落到哪个会话」，
/// 语义是「刚聊完的那个」，所以**不看置顶**。
///
/// 消息时间是真实发送时刻（毫秒）；老数据缺字段会被反序列化成 0，
/// 全为 0 时退化成列表顺序。
Conversation? mostRecentConversationOf(AppController controller, String taId) {
  Conversation? best;
  int bestAt = -1;
  for (final Conversation conversation in controller.conversations) {
    if (conversation.isGroup ||
        conversation.archived ||
        conversation.taId != taId) {
      continue;
    }
    final int at = conversation.messages.isEmpty
        ? 0
        : conversation.messages.last.timestamp;
    if (at > bestAt) {
      bestAt = at;
      best = conversation;
    }
  }
  return best;
}
