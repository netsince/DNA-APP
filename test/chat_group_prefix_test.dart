import 'package:flutter_test/flutter_test.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/pages/chat/chat_message_builder.dart';

/// 群聊提示词架构 v2(角色通道映射)回归:
/// 说话人由消息角色承载——当前角色的历史走 assistant 且无标注,
/// 其余所有人带「[名字]」标注走 user;相邻同角色合并;
/// 「名字：」前缀剥离仅作为输出侧安全网保留。
void main() {
  ConversationMessage assistant(String text, String? speakerId) =>
      ConversationMessage(
        id: 'm-$speakerId-$text.hashCode',
        role: 'assistant',
        text: text,
        timestamp: 0,
        speakerTaId: speakerId,
      );

  ConversationMessage user(String text) => ConversationMessage(
        id: 'm-u-${text.hashCode}',
        role: 'user',
        text: text,
        timestamp: 0,
      );

  String? resolver(String? id) => switch (id) {
        'ta-a' => '小明',
        'ta-b' => '小红',
        _ => null,
      };

  Map<String, String> map(
    ConversationMessage m, {
    String perspective = 'ta-a',
    bool group = true,
  }) {
    return ChatMessageBuilder.historyEntryFor(
      message: m,
      groupPerspective: group,
      perspectiveTaId: perspective,
      speakerNameResolver: resolver,
    );
  }

  group('historyEntryFor 角色通道映射', () {
    test('当前角色自己的发言 → assistant 且无任何标注', () {
      final out = map(assistant('你好呀', 'ta-a'));
      expect(out['role'], 'assistant');
      expect(out['content'], '你好呀');
    });

    test('其他成员的发言 → user + 方括号名字标注', () {
      final out = map(assistant('轮到我说啦', 'ta-b'));
      expect(out['role'], 'user');
      expect(out['content'], '[小红] 轮到我说啦');
    });

    test('人类用户发言 → user + [用户] 标注', () {
      final out = map(user('大家好'));
      expect(out['role'], 'user');
      expect(out['content'], '[用户] 大家好');
    });

    test('speakerTaId 为空的存量 AI 发言回退归入当前角色(不加标注)', () {
      final out = map(assistant('老消息', null));
      expect(out['role'], 'assistant');
      expect(out['content'], '老消息');
    });

    test('未知成员 id 标注为 [成员] 而非裸文本', () {
      final out = map(assistant('咦', 'ta-ghost'));
      expect(out['content'], '[成员] 咦');
    });

    test('思考标签在映射前剥除,不进入任一通道', () {
      const open = '<thi' 'nk>';
      const close = '</thi' 'nk>';
      final out = map(assistant('$open盘算$close台词', 'ta-a'));
      expect(out['content'], '台词');
    });

    test('单聊(group=false)保持原样:user 行不加标注', () {
      final out = map(user('嗨'), group: false);
      expect(out, <String, String>{'role': 'user', 'content': '嗨'});
    });
  });

  group('mergeAdjacentSameRole 相邻合并', () {
    test('连续 user 合并为一条(\\n 连接),assistant 交替处不合并', () {
      final payload = <Map<String, String>>[
        <String, String>{'role': 'system', 'content': 'sys'},
        <String, String>{'role': 'user', 'content': '[小红] a'},
        <String, String>{'role': 'user', 'content': '[用户] b'},
        <String, String>{'role': 'assistant', 'content': 'c'},
        <String, String>{'role': 'user', 'content': '[用户] d'},
      ];
      ChatMessageBuilder.mergeAdjacentSameRole(payload);
      expect(payload, hasLength(4));
      expect(payload[1]['content'], '[小红] a\n[用户] b');
      expect(payload[2]['role'], 'assistant');
      expect(payload[3]['content'], '[用户] d');
    });

    test('顺序严格保持(自后向前并入前一条)', () {
      final payload = <Map<String, String>>[
        <String, String>{'role': 'user', 'content': '1'},
        <String, String>{'role': 'user', 'content': '2'},
        <String, String>{'role': 'user', 'content': '3'},
      ];
      ChatMessageBuilder.mergeAdjacentSameRole(payload);
      expect(payload.single['content'], '1\n2\n3');
    });
  });

  group('buildMessagesFrom 群聊整体拼装', () {
    test('端到端:历史按视角映射并合并,extraUserText 不被并入历史', () {
      final payload = ChatMessageBuilder.buildMessagesFrom(
        systemPrompt: 'SYS',
        messages: <ConversationMessage>[
          user('开场'),
          assistant('A 的话', 'ta-a'),
          assistant('B 的话', 'ta-b'),
          user('追问'),
        ],
        groupPerspective: true,
        perspectiveTaId: 'ta-a',
        speakerNameResolver: resolver,
        extraUserText: '本轮新输入',
      );

      // system / 历史([用户]+assistant 合并? 不相邻不并)/ [小红] / [用户]追问→与谁相邻?
      // 序列: sys, [用户]开场(user), A(assistant), [小红](user), [用户]追问(user), 本轮新输入(user)
      // 合并后: sys, [用户]开场, A, [小红]\n[用户]追问\n本轮新输入 ← 错!extra 在 merge 之后追加才对。
      expect(payload[0], <String, String>{'role': 'system', 'content': 'SYS'});
      expect(payload[1]['content'], '[用户] 开场');
      expect(payload[2], <String, String>{'role': 'assistant', 'content': 'A 的话'});
      expect(payload[3]['content'], contains('[小红]'));
      expect(payload.last['content'], '本轮新输入');
      expect(payload.where((m) => m['role'] == 'assistant'), hasLength(1));
    });

    test('单聊拼装不受影响', () {
      final payload = ChatMessageBuilder.buildMessagesFrom(
        systemPrompt: 'S',
        messages: <ConversationMessage>[user('hi'), assistant('yo', 'ta-a')],
      );
      expect(payload[1]['content'], 'hi');
      expect(payload[2]['content'], 'yo');
    });
  });

  group('stripOwnSpeakerPrefix 输出侧安全网(兜底保留)', () {
    test('剥自身全角/半角前缀', () {
      expect(ChatMessageBuilder.stripOwnSpeakerPrefix('小明：台词', '小明'), '台词');
      expect(ChatMessageBuilder.stripOwnSpeakerPrefix('小明: 台词', '小明'), '台词');
    });
    test('他人前缀/无名/无前缀透传', () {
      expect(ChatMessageBuilder.stripOwnSpeakerPrefix('小红：x', '小明'), '小红：x');
      expect(ChatMessageBuilder.stripOwnSpeakerPrefix('小明：x', null), '小明：x');
      expect(ChatMessageBuilder.stripOwnSpeakerPrefix('正文', '小明'), '正文');
    });
    test('仅剥一层', () {
      expect(ChatMessageBuilder.stripOwnSpeakerPrefix('小明：小明：x', '小明'), '小明：x');
    });
  });
}
