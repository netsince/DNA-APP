import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/conversation.dart';
import 'package:dna/pages/chat/chat_message_builder.dart';

/// 请求 payload 的**金标准**（golden）。
///
/// 为什么要有它：`_assembleRequestPayload` 现在被「发送 / 重说候选 / 群聊点名」
/// 三个入口共用，但这条链路上真正决定请求长相的是 `buildMessagesFrom` —— 顺序、
/// 摘要插在哪、群聊是否合并、`extraUserText`（"继续"的指令）落在尾部还是历史前，
/// 任何一处挪动都会让 KV cache 的公共前缀失效（表现为首字延迟变长），
/// 但功能测试完全看不出来。
///
/// 这些断言是**顺序与形状**的锁：改布局时这里必须先红，然后由人决定要不要改。
ConversationMessage _msg(
  String role,
  String text, {
  String? speaker,
  String kind = 'message',
  int ts = 1,
}) {
  return ConversationMessage(
    id: 'm_${role}_$ts',
    role: role,
    text: text,
    timestamp: ts,
    kind: kind,
    speakerTaId: speaker,
  );
}

void main() {
  test('单聊完整 payload：system → 摘要 → 历史 → lore → 作者注', () {
    final List<Map<String, dynamic>> payload =
        ChatMessageBuilder.buildMessagesFrom(
          systemPrompt: 'SYS',
          messages: <ConversationMessage>[
            _msg('user', '你好', ts: 1),
            _msg('assistant', '你好呀', ts: 2),
            _msg('user', '在吗', ts: 3),
          ],
          summaryText: '之前聊过天气',
          summaryPrefix: ChatMessageBuilder.summarySystemPrefix,
          loreText: 'LORE',
          authorNote: 'NOTE',
          authorNoteInterval: 2,
        );

    expect(payload, <Map<String, dynamic>>[
      <String, dynamic>{'role': 'system', 'content': 'SYS'},
      <String, dynamic>{
        'role': 'system',
        'content': '${ChatMessageBuilder.summarySystemPrefix}之前聊过天气',
      },
      <String, dynamic>{'role': 'user', 'content': '你好'},
      <String, dynamic>{'role': 'assistant', 'content': '你好呀'},
      <String, dynamic>{'role': 'user', 'content': '在吗'},
      <String, dynamic>{'role': 'system', 'content': 'LORE'},
      <String, dynamic>{'role': 'system', 'content': 'NOTE'},
    ]);
  });

  test('摘要只有正文、没有前缀时**不插入**（避免脏 system 段）', () {
    final List<Map<String, dynamic>> payload =
        ChatMessageBuilder.buildMessagesFrom(
          systemPrompt: 'SYS',
          messages: <ConversationMessage>[_msg('user', 'hi')],
          summaryText: '摘要正文',
        );
    expect(payload.length, 2);
    expect(payload[0]['content'], 'SYS');
    expect(payload[1]['content'], 'hi');
  });

  test('非 message 类型的行不进历史（摘要提示气泡不污染请求）', () {
    final List<Map<String, dynamic>> payload =
        ChatMessageBuilder.buildMessagesFrom(
          systemPrompt: 'SYS',
          messages: <ConversationMessage>[
            _msg('user', 'A', ts: 1),
            _msg('assistant', 'B', ts: 2),
            _msg('user', '摘要提示', kind: MessageKind.summaryPrompt.value, ts: 3),
            _msg('assistant', '摘要正文', kind: MessageKind.summary.value, ts: 4),
          ],
        );
    expect(payload.map((Map<String, dynamic> m) => m['content']).toList(),
        <String>['SYS', 'A', 'B']);
  });

  test('extraUserText 追加在**最后**（"继续"的指令位置，KV cache 敏感）', () {
    final List<Map<String, dynamic>> payload =
        ChatMessageBuilder.buildMessagesFrom(
          systemPrompt: 'SYS',
          messages: <ConversationMessage>[_msg('user', 'A')],
          loreText: 'LORE',
          extraUserText: '请继续',
        );
    expect(payload.last, <String, dynamic>{'role': 'user', 'content': '请继续'});
    expect(payload[payload.length - 2]['content'], 'LORE');
  });

  test('群聊视角：他人发言走 user 通道并加方括号标注，自己的不加', () {
    final List<Map<String, dynamic>> payload =
        ChatMessageBuilder.buildMessagesFrom(
          systemPrompt: 'SYS',
          messages: <ConversationMessage>[
            _msg('user', '大家好', ts: 1),
            _msg('assistant', '我是小明', speaker: 'ta_m', ts: 2),
            _msg('assistant', '我是小红', speaker: 'ta_f', ts: 3),
            _msg('assistant', '我是主角', speaker: 'ta_me', ts: 4),
          ],
          groupPerspective: true,
          perspectiveTaId: 'ta_me',
          speakerNameResolver: (String? id) =>
              <String, String>{'ta_m': '小明', 'ta_f': '小红'}[id],
        );

    // 注意这里锁的是一个**语义**而不是实现细节：群聊视角下，真人发言与他人发言
    // 都会映射到 user 通道，于是连续三条被 mergeAdjacentSameRole 合成**一段**
    // user 内容（换行拼接），直到出现自己的 assistant 发言才断开。
    expect(payload, <Map<String, dynamic>>[
      <String, dynamic>{'role': 'system', 'content': 'SYS'},
      <String, dynamic>{
        'role': 'user',
        'content': '[用户] 大家好\n[小明] 我是小明\n[小红] 我是小红',
      },
      <String, dynamic>{'role': 'assistant', 'content': '我是主角'},
    ]);
  });

  test('单聊不合并同角色（保持原样映射，不做任何加工）', () {
    final List<Map<String, dynamic>> payload =
        ChatMessageBuilder.buildMessagesFrom(
          systemPrompt: 'SYS',
          messages: <ConversationMessage>[
            _msg('user', 'A1', ts: 1),
            _msg('user', 'A2', ts: 2),
          ],
        );
    expect(payload.length, 3);
    expect(payload[1]['content'], 'A1');
    expect(payload[2]['content'], 'A2');
  });

  test('空 system prompt 不产生空 system 段', () {
    final List<Map<String, dynamic>> payload =
        ChatMessageBuilder.buildMessagesFrom(
          systemPrompt: '   ',
          messages: <ConversationMessage>[_msg('user', 'A')],
        );
    expect(payload, <Map<String, dynamic>>[
      <String, dynamic>{'role': 'user', 'content': 'A'},
    ]);
  });
}
