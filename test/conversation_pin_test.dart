import 'package:dna/models/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _conversation() => Conversation(
      id: 'c1',
      taId: 'ta-1',
      worldId: null,
      note: '备注',
      messages: <ConversationMessage>[],
      backgroundMode: 'none',
      summaries: <ConversationSummary>[],
      archived: false,
      isGroup: false,
      groupName: '',
      groupPrompt: '',
      memberTaIds: <String>['ta-1'],
      activeTaId: 'ta-1',
    );

void main() {
  group('Conversation 置顶', () {
    test('pinned 默认 false', () {
      expect(_conversation().pinned, isFalse);
    });

    test('copyWith 可设置置顶', () {
      expect(_conversation().copyWith(pinned: true).pinned, isTrue);
    });

    test('toJson / fromJson 往返一致', () {
      final Conversation c = _conversation().copyWith(pinned: true);
      final Conversation back = Conversation.fromJson(c.toJson());
      expect(back.pinned, isTrue);
    });

    test('缺失 pinned 字段回退默认 false', () {
      final Map<String, dynamic> json = _conversation().toJson();
      json.remove('pinned');
      final Conversation back = Conversation.fromJson(json);
      expect(back.pinned, isFalse);
    });
  });
}
