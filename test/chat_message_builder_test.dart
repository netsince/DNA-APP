import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/conversation.dart';
import 'package:dna/pages/chat/chat_message_builder.dart';

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
}
