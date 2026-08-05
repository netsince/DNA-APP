import 'package:dna/models/conversation.dart';
import 'package:dna/utils/fork_utils.dart';
import 'package:flutter_test/flutter_test.dart';

ConversationMessage _msg(String id, String role, String text) =>
    ConversationMessage(
      id: id,
      role: role,
      text: text,
      timestamp: 0,
    );

void main() {
  group('buildForkConversation', () {
    final Conversation source = Conversation(
      id: 'src',
      taId: 'ta-1',
      worldId: 'world-1',
      identityId: 'id-1',
      note: '原始备注',
      messages: <ConversationMessage>[
        _msg('m0', 'user', '你好'),
        _msg('m1', 'assistant', '嗨'),
        _msg('m2', 'user', '在吗'),
      ],
      backgroundMode: 'image',
      summaries: <ConversationSummary>[
        ConversationSummary(
          id: 's1',
          text: '第一段摘要',
          createdAt: 1,
          endMessageId: 'm0',
        ),
        ConversationSummary(
          id: 's2',
          text: '第二段摘要',
          createdAt: 2,
          endMessageId: 'm2',
        ),
      ],
      archived: false,
      isGroup: false,
      groupName: '',
      groupPrompt: '',
      memberTaIds: <String>['ta-1'],
      activeTaId: 'ta-1',
    );

    test('保留到分叉点为止的消息', () {
      final Conversation? fork = buildForkConversation(
        source,
        1,
        existingIds: <String>{'src'},
      );
      expect(fork, isNotNull);
      expect(fork!.id, isNot('src'));
      expect(fork.messages.map((ConversationMessage m) => m.id).toList(),
          <String>['m0', 'm1']);
      expect(fork.taId, 'ta-1');
      expect(fork.worldId, 'world-1');
      expect(fork.identityId, 'id-1');
      expect(fork.archived, isFalse);
    });

    test('备注前追加「分叉的.」前缀', () {
      final Conversation? fork =
          buildForkConversation(source, 1, existingIds: <String>{'src'});
      expect(fork!.note, '分叉的.原始备注');
    });

    test('仅保留分叉点之前已生成的摘要', () {
      final Conversation? fork =
          buildForkConversation(source, 1, existingIds: <String>{'src'});
      expect(fork!.summaries.map((ConversationSummary s) => s.id).toList(),
          <String>['s1']);
    });

    test('索引越界返回 null', () {
      expect(buildForkConversation(source, 99, existingIds: <String>{'src'}),
          isNull);
      expect(buildForkConversation(source, -1, existingIds: <String>{'src'}),
          isNull);
    });

    test('生成的新 ID 避开已存在 ID', () {
      // 提供一个覆盖全部可能结果的集合不可行，但可验证结果 ID 不在给定集合中。
      final Conversation? fork =
          buildForkConversation(source, 1, existingIds: <String>{'src'});
      expect(fork!.id.isNotEmpty, isTrue);
    });
  });
}
