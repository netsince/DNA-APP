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


    test('全角/半角等价：搜 ＡＬＩＣＥ 能找到 alice', () {
      final List<SearchResult> r = searchGlobal(
        query: 'ＡＬＩＣＥ',
        tas: tas,
        worlds: worlds,
        conversations: conversations,
      );
      expect(r.any((SearchResult x) => x.taId == 't3'), isTrue);
    });

    test('语料侧同样归一：卡名是全角，搜半角也命中', () {
      final List<TA> fullWidth = <TA>[_ta('t9', name: 'ＡＢＣ')];
      final List<SearchResult> r = searchGlobal(
        query: 'abc',
        tas: fullWidth,
        worlds: const <World>[],
        conversations: const <Conversation>[],
      );
      expect(r.any((SearchResult x) => x.taId == 't9'), isTrue);
    });

    test('多关键词：全部命中才算命中（AND）', () {
      expect(
        searchGlobal(query: '艾莉 猫娘', tas: tas, worlds: worlds, conversations: conversations)
            .any((SearchResult x) => x.taId == 't1'),
        isTrue,
      );
      expect(
        searchGlobal(query: '艾莉 不存在的词', tas: tas, worlds: worlds, conversations: conversations),
        isEmpty,
        reason: '有一个词没命中就不该返回',
      );
    });

    test('多个空格/全角空格都当分隔符', () {
      expect(
        searchGlobal(query: '  艾莉　猫娘  ', tas: tas, worlds: worlds, conversations: conversations)
            .any((SearchResult x) => x.taId == 't1'),
        isTrue,
      );
    });

    test('消息命中取最新的，而不是最早的 5 条', () {
      final List<ConversationMessage> many = <ConversationMessage>[
        for (int i = 0; i < 8; i++)
          ConversationMessage(id: 'm$i', role: 'user', text: 'apple 第$i条', timestamp: i),
      ];
      final List<Conversation> convs = <Conversation>[
        _conv('c9', taId: 't1', messages: many),
      ];
      final List<SearchResult> msgs = searchGlobal(
        query: 'apple',
        tas: tas,
        worlds: worlds,
        conversations: convs,
      ).where((SearchResult x) => x.kind == SearchResultKind.message).toList();

      expect(msgs, hasLength(5));
      expect(msgs.first.snippet, contains('第7条'), reason: '最新那条必须最先出现');
      expect(msgs.last.snippet, contains('第3条'), reason: '按时间倒序取满 5 条');
    });

    test('卡名命中排在「人设里提了一句」之前（字段权重）', () {
      final List<TA> list = <TA>[
        _ta('byPersona', name: '无名旅人', persona: '她曾在酒馆听人提起辞安这个名字。'),
        _ta('byName', name: '辞安', persona: ''),
      ];
      final List<SearchResult> r = searchGlobal(
        query: '辞安',
        tas: list,
        worlds: const <World>[],
        conversations: const <Conversation>[],
      );
      expect(r.first.taId, 'byName');
    });

    test('头部命中排在深处命中之前（位置加分）', () {
      final String padding = '很长的背景铺垫。' * 6; // 48 字，远超头部窗口
      final List<TA> list = <TA>[
        _ta('deep', name: '甲', persona: '$padding辞安出现。'),
        _ta('head', name: '乙', persona: '辞安出现。'),
      ];
      final List<SearchResult> r = searchGlobal(
        query: '辞安',
        tas: list,
        worlds: const <World>[],
        conversations: const <Conversation>[],
      );
      expect(r.first.taId, 'head');
    });

    test('整名精确命中压过同名前缀', () {
      final List<TA> list = <TA>[
        _ta('prefix', name: '辞安的旅人', persona: ''),
        _ta('exact', name: '辞安', persona: ''),
      ];
      final List<SearchResult> r = searchGlobal(
        query: '辞安',
        tas: list,
        worlds: const <World>[],
        conversations: const <Conversation>[],
      );
      expect(r.first.taId, 'exact');
    });

    test('世界：词条名命中比词条描述命中更靠前', () {
      final List<World> list = <World>[
        _world('byBody', name: '甲世界', summary: '').copyWith(
          entries: <WorldEntry>[
            WorldEntry(
              id: 'e1',
              name: '无关词条',
              description: '王都的城墙很高。',
              type: WorldEntryType.noun,
            ),
          ],
        ),
        _world('byName', name: '乙世界', summary: '').copyWith(
          entries: <WorldEntry>[
            WorldEntry(
              id: 'e2',
              name: '王都',
              description: '',
              type: WorldEntryType.noun,
            ),
          ],
        ),
      ];
      final List<SearchResult> r = searchGlobal(
        query: '王都',
        tas: const <TA>[],
        worlds: list,
        conversations: const <Conversation>[],
      );
      expect(r.first.worldId, 'byName');
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
