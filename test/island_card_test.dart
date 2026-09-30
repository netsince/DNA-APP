import 'dart:convert';

import 'package:dna/island/island_card.dart';
import 'package:dna/island/trial_chat.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/services/ta_export_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 岛 ↔ 主项目 角色卡互通的契约。
///
/// 关键前提：两边的角色 schema **本来就是同一套**（同一个生态），差异只在
/// 命名风格（岛 snake_case / 主项目 camelCase）。所以这里的测试盯的是
/// **键名映射**与**归一化后能否被现有导入器吃下去**。
void main() {
  /// 岛卡片详情接口返回的形状（author 是嵌套对象、images 是槽位→路径）。
  Map<String, dynamic> cardDetailJson() => <String, dynamic>{
    'id': 'card-123',
    'name': '爱丽丝',
    'gender': '女',
    'persona': '冷静、话少。',
    'intro': '来自北境的旅人。',
    'opening': '「你终于来了。」',
    'original_link': 'https://dnaisland.nb6.ltd/cards/123',
    'cover_focus': '50% 20%',
    'status': 'approved',
    'tags': <String>['北境', '旅人'],
    'dialogue': <Map<String, String>>[
      <String, String>{'user': '你好', 'assistant': '「嗯。」'},
    ],
    'images': <String, String>{
      'square': '/uploads/cards/123/square.png',
      'portrait': 'https://cdn.example.com/p.png',
    },
    'author': <String, dynamic>{'nickname': '星野', 'username': 'hoshino'},
    'author_note': '写给自己看的备注',
    'author_note_interval': 3,
    'seed': 12345,
  };

  group('岛卡片解析', () {
    test('详情形状:嵌套作者、dialogue、images 槽位', () {
      final IslandCard card = IslandCard.fromJson(cardDetailJson());
      expect(card.id, 'card-123');
      expect(card.name, '爱丽丝');
      expect(card.tags, <String>['北境', '旅人']);
      expect(card.dialogue.single.user, '你好');
      expect(card.dialogue.single.assistant, '「嗯。」');
      expect(card.images['square'], '/uploads/cards/123/square.png');
      expect(card.authorName, '星野');
      expect(card.authorUsername, 'hoshino');
      expect(card.authorNote, '写给自己看的备注');
      expect(card.authorNoteInterval, 3);
      expect(card.seed, 12345);
      expect(card.coverFocus, '50% 20%');
    });

    test('映射成 TA:字段一一对应,槽位换成本地路径', () {
      final IslandCard card = IslandCard.fromJson(cardDetailJson());
      final TA ta = card.toTa(
        id: 'ta-1',
        localImages: <String, String>{'square': '/local/square.png'},
      );
      expect(ta.id, 'ta-1');
      expect(ta.name, '爱丽丝');
      expect(ta.gender, '女');
      expect(ta.persona, '冷静、话少。');
      expect(ta.intro, '来自北境的旅人。');
      expect(ta.opening, '「你终于来了。」');
      expect(ta.tags, <String>['北境', '旅人']);
      expect(ta.dialogueStyle.single.assistant, '「嗯。」');
      expect(ta.voiceSeed, 12345, reason: '岛的 seed 就是主项目的 voiceSeed');
      expect(ta.authorNote, '写给自己看的备注');
      expect(ta.authorNoteInterval, 3);
      expect(ta.originalLink, 'https://dnaisland.nb6.ltd/cards/123');
      expect(ta.images['square'], '/local/square.png');
      expect(ta.archived, isFalse);
    });

    test('没有图片也能成 TA(试聊不需要图)', () {
      final IslandCard card = IslandCard.fromJson(
        cardDetailJson()..remove('images'),
      );
      final TA ta = card.toTa(id: 'ta-2');
      expect(ta.images, isEmpty);
      expect(ta.name, '爱丽丝');
    });
  });

  group('发布到岛', () {
    test('TA → payload:键名换成岛要的 snake_case', () {
      const TA ta = TA(
        id: 'ta-1',
        name: '爱丽丝',
        gender: '女',
        persona: '冷静',
        intro: '旅人',
        opening: '「你来了。」',
        tags: <String>['北境'],
        images: <String, String>{'square': '/local/s.png'},
        dialogueStyle: <DialogueTurn>[
          DialogueTurn(user: '你好', assistant: '「嗯。」'),
        ],
        voiceSeed: 999,
        authorNote: '备注',
        authorNoteInterval: 2,
        originalLink: 'https://example.com/c/1',
      );
      final Map<String, dynamic> payload = islandPublishPayload(
        ta,
        imageDataUris: <String, String>{
          'square': 'data:image/png;base64,AAAA',
        },
        authorUsername: 'hoshino',
      );
      expect(payload['name'], '爱丽丝');
      expect(payload['dialogue_style'], <Map<String, String>>[
        <String, String>{'user': '你好', 'assistant': '「嗯。」'},
      ]);
      expect(payload['seed'], 999);
      expect(payload['author_note'], '备注');
      expect(payload['author_note_interval'], 2);
      expect(payload['original_link'], 'https://example.com/c/1');
      expect(payload['user'], 'hoshino');
      expect(payload['images'], <String, String>{
        'square': 'data:image/png;base64,AAAA',
      });
      // 不能把主项目本地才有的字段发上去
      expect(payload.containsKey('musicPath'), isFalse);
      expect(payload.containsKey('protection'), isFalse);
    });
  });

  group('导入到我家(归一化)', () {
    test('扁平 snake_case 卡片 → 现有导入器可直接吃下', () {
      final Map<String, dynamic> normalized = normalizeIslandPackage(
        cardDetailJson(),
      );
      // 补上了主项目导入器认的外壳
      expect(normalized['exportType'], 'character');
      final Map<String, dynamic> character =
          normalized['character'] as Map<String, dynamic>;
      // 键名已转成 camelCase
      expect(character['dialogueStyle'], isA<List<dynamic>>());
      expect(character['voiceSeed'], 12345);
      expect(character['authorNote'], '写给自己看的备注');
      expect(character['authorNoteInterval'], 3);
      expect(character['originalLink'], 'https://dnaisland.nb6.ltd/cards/123');

      final result = TaExportImportService.importCharacter(
        jsonEncode(normalized),
      );
      expect(result.success, isTrue, reason: result.message);
      final TA ta = result.data!.ta;
      expect(ta.name, '爱丽丝');
      expect(ta.gender, '女');
      expect(ta.persona, '冷静、话少。');
      expect(ta.intro, '来自北境的旅人。');
      expect(ta.opening, '「你终于来了。」');
      expect(ta.tags, <String>['北境', '旅人']);
      expect(ta.dialogueStyle.single.user, '你好');
      expect(ta.dialogueStyle.single.assistant, '「嗯。」');
      expect(ta.voiceSeed, 12345);
      expect(ta.authorNote, '写给自己看的备注');
      expect(ta.authorNoteInterval, 3);
      expect(ta.originalLink, 'https://dnaisland.nb6.ltd/cards/123');
    });

    test('已经是主项目外壳的包:原样通过,不重复包一层', () {
      final Map<String, dynamic> already = <String, dynamic>{
        'exportType': 'character',
        'version': 1,
        'character': <String, dynamic>{'id': 'x', 'name': '鲍勃'},
      };
      final Map<String, dynamic> normalized = normalizeIslandPackage(already);
      expect(normalized['exportType'], 'character');
      final Map<String, dynamic> character =
          normalized['character'] as Map<String, dynamic>;
      expect(character['name'], '鲍勃');
      expect(character['id'], 'x');
    });
  });

  group('试聊', () {
    ConversationMessage msg(String role, String text, int at) =>
        ConversationMessage(
          id: 'm$at',
          role: role,
          text: text,
          timestamp: at,
        );

    test('上限 10 条(用户+助手合计),满了必须做选择', () {
      final IslandCard card = IslandCard.fromJson(cardDetailJson());
      TrialChat chat = TrialChat(card: card, messages: <ConversationMessage>[]);
      expect(TrialChat.maxMessages, 10);
      expect(chat.canContinue, isTrue);
      expect(chat.remaining, 10);

      for (int i = 0; i < 5; i++) {
        chat = chat.copyWith(
          messages: <ConversationMessage>[
            ...chat.messages,
            msg('user', '问 $i', i * 2),
            msg('assistant', '答 $i', i * 2 + 1),
          ],
        );
      }
      expect(chat.messages.length, 10);
      expect(chat.isFull, isTrue);
      expect(chat.canContinue, isFalse, reason: '满 10 条后不能再聊,必须选导入或返回');
      expect(chat.remaining, 0);
      expect(chat.userTurns, 5);
    });

    test('暂存本地:存得下、读得回、丢得掉', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final IslandCard card = IslandCard.fromJson(cardDetailJson());
      final TrialChat chat = TrialChat(
        card: card,
        messages: <ConversationMessage>[
          msg('user', '你好', 1000),
          msg('assistant', '「嗯。」', 1001),
        ],
      );

      await TrialChatStore.save(chat);
      final TrialChat? loaded = await TrialChatStore.load('card-123');
      expect(loaded, isNotNull);
      expect(loaded!.messages.length, 2);
      expect(loaded.messages.first.text, '你好');
      expect(loaded.messages.last.role, 'assistant');
      // 卡片本身也跟着存下来了 —— 离线也能接着试聊
      expect(loaded.card.name, '爱丽丝');
      expect(loaded.card.dialogue.single.assistant, '「嗯。」');
      expect(await TrialChatStore.pendingCardIds(), <String>['card-123']);

      await TrialChatStore.clear('card-123');
      expect(await TrialChatStore.load('card-123'), isNull);
      expect(await TrialChatStore.pendingCardIds(), isEmpty);
    });

    test('坏记录不炸:当作没有', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'island_trial_card-123': '{这不是 json',
      });
      expect(await TrialChatStore.load('card-123'), isNull);
    });
  });
}
