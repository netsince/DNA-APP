import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/conversation.dart';
import 'package:dna/pages/chat/chat_message_builder.dart';
import 'package:dna/pages/chat/chat_system_prompt.dart';

ConversationMessage _msg(String id, String role, String text) {
  return ConversationMessage(
    id: id,
    role: role,
    text: text,
    timestamp: 0,
  );
}

void main() {
  group('ChatMessageBuilder.buildMessagesFrom', () {
    test('基础布局：system -> 摘要 -> 历史', () {
      final payload = ChatMessageBuilder.buildMessagesFrom(
        systemPrompt: '你是TA。',
        messages: <ConversationMessage>[
          _msg('u1', 'user', '你好'),
          _msg('a1', 'assistant', '嗨！'),
        ],
        summaryText: '简短摘要',
        summaryPrefix: '对话摘要：\n',
      );
      expect(payload, <Map<String, String>>[
        <String, String>{'role': 'system', 'content': '你是TA。'},
        <String, String>{'role': 'system', 'content': '对话摘要：\n简短摘要'},
        <String, String>{'role': 'user', 'content': '你好'},
        <String, String>{'role': 'assistant', 'content': '嗨！'},
      ]);
    });

    test('缓存友好：Lorebook 追加在历史之后，不污染前缀', () {
      final payload = ChatMessageBuilder.buildMessagesFrom(
        systemPrompt: '你是TA。',
        messages: <ConversationMessage>[
          _msg('u1', 'user', '你好'),
          _msg('a1', 'assistant', '嗨！'),
        ],
        loreText: '当前激活的世界知识：城堡位于北方。',
      );
      // 前两条必须与无 Lorebook 时完全一致，保证前缀稳定。
      expect(payload.take(2), <Map<String, String>>[
        <String, String>{'role': 'system', 'content': '你是TA。'},
        <String, String>{'role': 'user', 'content': '你好'},
      ]);
      expect(payload.last, <String, String>{
        'role': 'system',
        'content': '当前激活的世界知识：城堡位于北方。',
      });
    });

    test('缓存友好：Author\'s Note 以固定位置追加在历史之后', () {
      final payload = ChatMessageBuilder.buildMessagesFrom(
        systemPrompt: '你是TA。',
        messages: <ConversationMessage>[
          _msg('u1', 'user', '你好'),
          _msg('a1', 'assistant', '嗨！'),
          _msg('u2', 'user', '再说点什么'),
          _msg('a2', 'assistant', '好的！'),
        ],
        authorNote: '记住：我们约定的暗号是"月亮"。',
        authorNoteInterval: 2,
      );
      // 历史必须连续无插入。
      final roles = payload.map((m) => m['role']).toList();
      expect(roles.sublist(0, 4), <String>['system', 'user', 'assistant', 'user']);
      // 作者注释只出现在历史之后的一条固定 system。
      final notes = payload
          .where((m) => m['role'] == 'system' && m['content']!.contains('暗号'))
          .toList();
      expect(notes.length, 1);
      expect(payload.last['content'], contains('暗号'));
    });

    test('Author\'s Note interval 为 0 时不注入', () {
      final payload = ChatMessageBuilder.buildMessagesFrom(
        systemPrompt: '你是TA。',
        messages: <ConversationMessage>[
          _msg('u1', 'user', '你好'),
          _msg('a1', 'assistant', '嗨！'),
        ],
        authorNote: '应该被忽略。',
        authorNoteInterval: 0,
      );
      expect(payload.any((m) => m['content']!.contains('应该被忽略')), isFalse);
    });

    test('loreSystemMessage 空文本返回 null', () {
      expect(ChatMessageBuilder.loreSystemMessage(''), isNull);
      expect(ChatMessageBuilder.loreSystemMessage('   '), isNull);
      expect(ChatMessageBuilder.loreSystemMessage('有内容'), isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // 摘要的说话人标签与注入前缀。
  //
  // 用户反馈：「一生成摘要就角色错乱 —— 它把自己该扮的角色甩给我，又把我扮的角色安到
  // 它自己头上；不生成摘要就没事。」
  //
  // 根因：摘要是一段纯文本，说话人只能用**名字**表达，而这里以前一律写「助手」。
  // 模型被教过的约定却是「assistant 通道 = 我自己」（见 chat_system_prompt 的群聊规则
  // 与 historyEntryFor），于是摘要里的「助手：」被读成它自己的台词；群聊里更糟 ——
  // 所有 AI 成员都被糊成同一个「助手」。加上摘要会顶掉被总结的那段历史
  // （ChatMessageSlice），模型对那段的唯一记录就是这份错标签的摘要。
  // ---------------------------------------------------------------------------
  group('摘要说话人标签', () {
    ConversationMessage member(String id, String text, String? taId) {
      return ConversationMessage(
        id: id,
        role: 'assistant',
        text: text,
        timestamp: 0,
        speakerTaId: taId,
      );
    }

    test('群聊：每个 AI 成员用各自角色名，绝不出现泛称「助手」', () {
      final transcript = ChatMessageBuilder.buildSummaryTranscript(
        <ConversationMessage>[
          _msg('u1', 'user', '你们好'),
          member('a1', '我是艾莉', 'ta-eli'),
          member('a2', '我是小雪', 'ta-xue'),
        ],
        fallbackAssistantName: '艾莉',
        speakerNameResolver: (String? id) =>
            <String, String>{'ta-eli': '艾莉', 'ta-xue': '小雪'}[id],
      );

      expect(transcript, '用户：你们好\n艾莉：我是艾莉\n小雪：我是小雪');
      expect(
        transcript.contains('助手'),
        isFalse,
        reason: '「助手」会和 assistant 通道约定打架，把所有 AI 成员糊成一个人',
      );
    });

    test('单聊：人类是「用户」，AI 用角色名', () {
      final transcript = ChatMessageBuilder.buildSummaryTranscript(
        <ConversationMessage>[
          _msg('u1', 'user', '你好'),
          member('a1', '你好呀', 'ta-eli'),
        ],
        fallbackAssistantName: '艾莉',
        speakerNameResolver: (String? id) => id == 'ta-eli' ? '艾莉' : null,
      );
      expect(transcript, '用户：你好\n艾莉：你好呀');
    });

    test('存量数据没有 speakerTaId：退回当前角色名', () {
      final transcript = ChatMessageBuilder.buildSummaryTranscript(
        <ConversationMessage>[
          _msg('u1', 'user', '你好'),
          member('a1', '老消息没有说话人', null),
        ],
        fallbackAssistantName: '艾莉',
        speakerNameResolver: (String? id) => null,
      );
      expect(transcript, '用户：你好\n艾莉：老消息没有说话人');
    });

    test('连角色名都没有时兜底为「成员」，不崩也不写成「助手」', () {
      final transcript = ChatMessageBuilder.buildSummaryTranscript(
        <ConversationMessage>[member('a1', '无名', 'ta-?')],
        speakerNameResolver: (String? id) => null,
      );
      expect(transcript, '成员：无名');
    });
  });

  group('摘要注入与提示词', () {
    test('注入前缀明确「不代表你的身份」，避免模型把摘要当自己的经历', () {
      expect(ChatMessageBuilder.summarySystemPrefix, contains('不代表你的身份'));
      final payload = ChatMessageBuilder.buildMessagesFrom(
        systemPrompt: '你是艾莉。',
        messages: <ConversationMessage>[_msg('u1', 'user', '你好')],
        summaryText: '用户与艾莉在酒馆相遇。',
        summaryPrefix: ChatMessageBuilder.summarySystemPrefix,
      );
      expect(payload[1]['role'], 'system');
      expect(payload[1]['content'], startsWith(ChatMessageBuilder.summarySystemPrefix));
      expect(payload[1]['content'], contains('用户与艾莉在酒馆相遇。'));
    });

    test('摘要提示词强制第三人称、用角色名指代双方', () {
      for (final String prompt in <String>[
        ChatSystemPrompt.summaryInstruction,
        ChatSystemPrompt.summaryInstructionExtend,
      ]) {
        expect(prompt, contains('第三人称'));
        expect(prompt, contains('用户'));
        expect(prompt, contains('角色名'));
        expect(prompt, contains('不要使用「我」「你」'));
      }
    });
  });
}
