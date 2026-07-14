import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/search_result.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

TA _ta(String id, {String name = '', String persona = '', String intro = '', List<String> tags = const <String>[]}) {
  return TA(
    id: id,
    name: name,
    gender: '女',
    persona: persona,
    intro: intro,
    opening: '',
    tags: tags,
    images: const <String, String>{},
    dialogueStyle: const <DialogueTurn>[],
  );
}

World _world(String id, {String name = '', String summary = '', List<String> tags = const <String>[]}) {
  return World(
    id: id,
    name: name,
    summary: summary,
    description: '',
    tags: tags,
    forbiddenWords: const <String>[],
    entries: const <WorldEntry>[],
  );
}

Conversation _conv(String id, {String taId = '', String note = '', List<ConversationMessage> messages = const <ConversationMessage>[]}) {
  return Conversation(
    id: id,
    taId: taId,
    worldId: null,
    note: note,
    messages: messages,
    backgroundMode: 'none',
    summaries: const <ConversationSummary>[],
    archived: false,
    isGroup: false,
    groupName: '',
    groupPrompt: '',
    memberTaIds: const <String>[],
    activeTaId: null,
  );
}

void main() {
  group('searchGlobal', () {
    final List<TA> tas = <TA>[
      _ta('t1', name: '艾莉', persona: '温柔的少女', tags: <String>['猫娘']),
      _ta('t2', name: '鲍勃', intro: '来自北方的旅人'),
      _ta('t3', name: 'Alice', intro: 'latin name'),
    ];
    final List<World> worlds = <World>[
      _world('w1', name: '星界', summary: '魔法与机械并存'),
    ];
    final List<Conversation> conversations = <List<Conversation>>[
      <Conversation>[
        _conv('c1', taId: 't1', note: '日常', messages: <ConversationMessage>[
          ConversationMessage(id: 'm1', role: 'user', text: '今天天气真好', timestamp: 1),
          ConversationMessage(id: 'm2', role: 'assistant', text: '我们一起去散步吧', timestamp: 2),
        ]),
        _conv('c2', taId: 't2', note: '', messages: <ConversationMessage>[
          ConversationMessage(id: 'm3', role: 'user', text: '讲讲北方的故事', timestamp: 3),
        ]),
      ],
    ].expand((List<Conversation> e) => e).toList();

    test('空查询返回空', () {
      expect(
        searchGlobal(query: '   ', tas: tas, worlds: worlds, conversations: conversations),
        isEmpty,
      );
    });

    test('按角色名命中', () {
      final List<SearchResult> r =
          searchGlobal(query: '艾莉', tas: tas, worlds: worlds, conversations: conversations);
      expect(r.where((SearchResult x) => x.kind == SearchResultKind.ta && x.taId == 't1'), hasLength(1));
    });

    test('按标签命中', () {
      final List<SearchResult> r =
          searchGlobal(query: '猫娘', tas: tas, worlds: worlds, conversations: conversations);
      expect(r.any((SearchResult x) => x.kind == SearchResultKind.ta && x.taId == 't1'), isTrue);
    });

    test('按世界简介命中', () {
      final List<SearchResult> r =
          searchGlobal(query: '机械', tas: tas, worlds: worlds, conversations: conversations);
      expect(r.any((SearchResult x) => x.kind == SearchResultKind.world && x.worldId == 'w1'), isTrue);
    });

    test('按会话备注命中为 conversation 类型', () {
      final List<SearchResult> r =
          searchGlobal(query: '日常', tas: tas, worlds: worlds, conversations: conversations);
      expect(r.any((SearchResult x) => x.kind == SearchResultKind.conversation && x.conversationId == 'c1'), isTrue);
    });

    test('按消息正文命中为 message 类型且带片段', () {
      final List<SearchResult> r =
          searchGlobal(query: '散步', tas: tas, worlds: worlds, conversations: conversations);
      final List<SearchResult> msgs =
          r.where((SearchResult x) => x.kind == SearchResultKind.message).toList();
      expect(msgs, hasLength(1));
      expect(msgs.first.conversationId, 'c1');
      expect(msgs.first.snippet, contains('散步'));
    });

    test('单会话消息命中最多取 5 条', () {
      final List<ConversationMessage> many = <ConversationMessage>[
        for (int i = 0; i < 8; i++)
          ConversationMessage(id: 'mx$i', role: 'user', text: '重复关键词 apple', timestamp: i),
      ];
      final List<Conversation> convs = <Conversation>[_conv('c9', taId: 't1', messages: many)];
      final List<SearchResult> r =
          searchGlobal(query: 'apple', tas: tas, worlds: worlds, conversations: convs);
      expect(
        r.where((SearchResult x) => x.kind == SearchResultKind.message).length,
        5,
      );
    });

    test('大小写不敏感', () {
      final List<SearchResult> upper =
          searchGlobal(query: 'ALICE', tas: tas, worlds: worlds, conversations: conversations);
      final List<SearchResult> lower =
          searchGlobal(query: 'alice', tas: tas, worlds: worlds, conversations: conversations);
      // 大小写都应命中 t3
      expect(upper.any((SearchResult x) => x.taId == 't3'), isTrue);
      expect(lower.any((SearchResult x) => x.taId == 't3'), isTrue);
    });
  });
}
