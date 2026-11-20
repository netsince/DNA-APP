import 'package:dna/models/conversation.dart';
import 'package:dna/models/message_attachment.dart';
import 'package:dna/pages/chat/chat_message_builder.dart';
import 'package:dna/pages/chat/chat_message_slice.dart';
import 'package:dna/pages/chat/chat_models.dart';
import 'package:dna/pages/chat/chat_token_counter.dart';
import 'package:dna/services/attachment_gc.dart';
import 'package:flutter_test/flutter_test.dart';

MessageAttachment _att(String ref, {
  String kind = 'text',
  String? preview,
  int textChars = 0,
}) =>
    MessageAttachment(
      ref: ref,
      name: 'f.txt',
      mime: 'text/plain',
      size: 100,
      kind: kind,
      textPreview: preview,
      textChars: textChars,
    );

void main() {
  group('孤儿判定', () {
    test('被引用的不算孤儿', () {
      final List<String> orphans = AttachmentGc.orphansOf(
        allRefs: <String>['a', 'b', 'c'],
        liveRefs: <String>{'b'}.cast<String>(),
      );
      expect(orphans, <String>['a', 'c']);
    });

    test('全都被引用时一个都不删', () {
      expect(
        AttachmentGc.orphansOf(
          allRefs: <String>['a', 'b'],
          liveRefs: <String>{'a', 'b'}.cast<String>(),
        ),
        isEmpty,
      );
    });

    test('引用集合为空时全部算孤儿，但不会凭空多出东西', () {
      expect(
        AttachmentGc.orphansOf(
          allRefs: <String>['a'],
          liveRefs: <String>{}.cast<String>(),
        ),
        <String>['a'],
      );
      expect(
        AttachmentGc.orphansOf(
          allRefs: const <String>[],
          liveRefs: <String>{}.cast<String>(),
        ),
        isEmpty,
      );
    });
  });

  group('附件进入上下文预算', () {
    final ChatTokenCounter counter = ChatTokenCounter();

    ConversationMessage msg(String id, String text, {List<MessageAttachment> atts = const <MessageAttachment>[]}) =>
        ConversationMessage(
          id: id,
          role: 'user',
          text: text,
          timestamp: 0,
          attachments: atts,
        );

    test('大附件会把更早的消息挤出预算', () {
      final String longText = '设定' * 3000; // 6000 字
      final Conversation conv = Conversation(
        id: 'c',
        taId: 'ta',
        worldId: '',
        note: '',
        messages: <ConversationMessage>[
          msg('m1', '很早的一条消息'),
          msg('m2', '看看这个', atts: <MessageAttachment>[
            _att('r1', preview: longText, textChars: longText.length),
          ]),
        ],
        backgroundMode: 'color',
        summaries: const <ConversationSummary>[],
        archived: false,
        isGroup: false,
        groupName: '',
        groupPrompt: '',
        memberTaIds: const <String>[],
        activeTaId: '',
      );
      final MessageSlice slice = ChatMessageSlice.sliceForPayload(
        conv,
        maxTokens: 2000,
        tokenCounter: counter,
        tokenModel: 'gpt-4o',
      );
      expect(slice.messages.length, 1, reason: '带附件那条吃掉了预算，老消息该被裁掉');
      expect(slice.messages.single.id, 'm2');
    });

    test('没有附件时预算与原来一致（不误伤）', () {
      final Conversation conv = Conversation(
        id: 'c',
        taId: 'ta',
        worldId: '',
        note: '',
        messages: <ConversationMessage>[
          msg('m1', '第一句'),
          msg('m2', '第二句'),
        ],
        backgroundMode: 'color',
        summaries: const <ConversationSummary>[],
        archived: false,
        isGroup: false,
        groupName: '',
        groupPrompt: '',
        memberTaIds: const <String>[],
        activeTaId: '',
      );
      final MessageSlice slice = ChatMessageSlice.sliceForPayload(
        conv,
        maxTokens: 2000,
        tokenCounter: counter,
        tokenModel: 'gpt-4o',
      );
      expect(slice.messages.length, 2);
    });
  });

  group('附件文本拼接', () {
    test('被截断的文本附件会写明「只给前 N 字」', () {
      final Map<String, dynamic> entry = ChatMessageBuilder.historyEntryFor(
        message: ConversationMessage(
          id: 'm',
          role: 'user',
          text: '看附件',
          timestamp: 0,
          attachments: <MessageAttachment>[
            _att('r1', preview: '前两千字', textChars: 99999),
          ],
        ),
        groupPerspective: false,
      );
      expect(entry['content'], contains('只给前'));
      expect(entry['content'], contains('99999'));
    });

    test('没被截断就不加那句（避免每条都啰嗦）', () {
      final Map<String, dynamic> entry = ChatMessageBuilder.historyEntryFor(
        message: ConversationMessage(
          id: 'm',
          role: 'user',
          text: '看附件',
          timestamp: 0,
          attachments: <MessageAttachment>[
            _att('r1', preview: '全文', textChars: 2),
          ],
        ),
        groupPerspective: false,
      );
      expect(entry['content'], isNot(contains('只给前')));
    });
  });
}
