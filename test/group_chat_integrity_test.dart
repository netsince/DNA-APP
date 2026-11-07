import 'dart:io';

import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/chat_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 群聊的**身份不变量**与删除侧清理。
///
/// 守三个真实踩过的坑：
/// 1. 群聊被当成单聊写回（成员 / 群设定 / 说话人标注全丢，且不报错）；
/// 2. 自动续玩只查单聊列表，群聊永远恢复不了，还会把指针一并清掉；
/// 3. 删角色不摘群成员，留下的死 id 让群聊再也发不了言。
class _RecordingHive extends HiveService {
  _RecordingHive({required this.tas, required this.conversations});

  final List<TA> tas;
  final List<Conversation> conversations;

  /// 所有写回过的会话（按调用顺序），用来断言「有没有多写盘」。
  final List<Conversation> saved = <Conversation>[];

  @override
  Future<void> init() async {}

  @override
  Future<List<TA>> getTas() async => tas;

  @override
  Future<List<UserIdentity>> getIdentities() async => <UserIdentity>[];

  @override
  Future<List<World>> getWorlds() async => <World>[];

  @override
  Future<List<Conversation>> getConversations() async => conversations;

  @override
  Future<void> upsertConversation(Conversation conversation) async {
    saved.add(conversation);
  }

  @override
  Future<void> deleteTa(String id) async {}
}

TA _ta(String id) => TA(
      id: id,
      name: '角色 $id',
      gender: '',
      persona: '',
      intro: '',
      opening: '',
      tags: <String>[],
      images: <String, String>{},
      dialogueStyle: <DialogueTurn>[],
    );

Conversation _group(String id) => Conversation(
      id: id,
      taId: 'a',
      worldId: null,
      note: '',
      messages: <ConversationMessage>[
        ConversationMessage(id: 'm1', role: 'user', text: '在吗', timestamp: 1),
      ],
      backgroundMode: 'none',
      summaries: <ConversationSummary>[],
      archived: false,
      isGroup: true,
      groupName: '测试群',
      groupPrompt: '群设定',
      memberTaIds: <String>['a', 'b'],
      activeTaId: 'a',
    );

/// 单聊形态的「空壳」：id 相同、isGroup 为 false、群字段全空。
/// 这正是「调用方没传 isGroup、聊天页查不到会话」时构造出来的东西。
Conversation _shell(String id) => Conversation(
      id: id,
      taId: '',
      worldId: null,
      note: '',
      messages: <ConversationMessage>[],
      backgroundMode: 'none',
      summaries: <ConversationSummary>[],
      archived: false,
      isGroup: false,
      groupName: '',
      groupPrompt: '',
      memberTaIds: <String>[],
      activeTaId: null,
    );

Conversation _single(String id) => Conversation(
      id: id,
      taId: 'a',
      worldId: null,
      note: '',
      messages: <ConversationMessage>[],
      backgroundMode: 'none',
      summaries: <ConversationSummary>[],
      archived: false,
      isGroup: false,
      groupName: '',
      groupPrompt: '',
      memberTaIds: <String>['a'],
      activeTaId: 'a',
    );

Future<AppController> _boot(_RecordingHive hive) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'completed_oobe': true,
    'show_splash_animation': false,
  });
  final AppController controller = AppController(
    settingsService: SettingsService(),
    openAiService: OpenAiService(),
    taService: TaService(),
    hiveService: hive,
  );
  await controller.initialize();
  return controller;
}

void main() {
  group('会话类型由数据决定', () {
    test('getConversationById 单聊与群聊都能查到', () async {
      final AppController controller = await _boot(_RecordingHive(
        tas: <TA>[_ta('a'), _ta('b')],
        conversations: <Conversation>[_single('c1'), _group('g1')],
      ));

      expect(controller.getConversationById('c1')?.isGroup, isFalse);
      expect(controller.getConversationById('g1')?.isGroup, isTrue);
      expect(controller.getConversationById('没有这个'), isNull);
    });

    test('单聊 payload 写回群聊 id：不降级、不丢成员与群设定', () async {
      final AppController controller = await _boot(_RecordingHive(
        tas: <TA>[_ta('a'), _ta('b')],
        conversations: <Conversation>[_group('g1')],
      ));

      await controller.upsertConversation(_shell('g1'));

      expect(
        controller.conversations.where((Conversation c) => c.id == 'g1'),
        isEmpty,
        reason: '群聊不能被塞进单聊列表 —— 那正是「搜索页打开群聊」的损坏路径',
      );
      final List<Conversation> groups = controller.groupConversations
          .where((Conversation c) => c.id == 'g1')
          .toList();
      expect(groups, hasLength(1));
      expect(groups.single.isGroup, isTrue);
      expect(groups.single.memberTaIds, <String>['a', 'b'],
          reason: '单聊 payload 对群成员没有主张，不能拿空表覆盖');
      expect(groups.single.groupName, '测试群');
      expect(groups.single.groupPrompt, '群设定');
      expect(groups.single.activeTaId, 'a');
    });
  });

  testWidgets('调用方漏传 isGroup 时，按数据渲染成群聊', (WidgetTester tester) async {
    final AppController controller = await _boot(_RecordingHive(
      tas: <TA>[_ta('a'), _ta('b')],
      conversations: <Conversation>[_group('g1')],
    ));

    // 刻意不传 isGroup —— 正是搜索页 / 深链进来时的样子。
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(controller: controller, conversationId: 'g1'),
      ),
    );
    // 不能 pumpAndSettle：聊天页有光标闪烁等持续动画。
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('发言控制'), findsWidgets,
        reason: '群聊的发言控制条必须出现 —— 说明真的按群聊渲染了');
    expect(
      controller.conversations.where((Conversation c) => c.id == 'g1'),
      isEmpty,
      reason: '不能在单聊列表里造一个同 id 的空壳',
    );
  });

  group('删除角色时清理群成员', () {
    test('摘掉成员，并把主角色 / 当前发言人挪到剩下的成员', () async {
      final AppController controller = await _boot(_RecordingHive(
        tas: <TA>[_ta('a'), _ta('b')],
        conversations: <Conversation>[_group('g1')],
      ));

      await controller.deleteTa('a');

      final Conversation group = controller.groupConversations.single;
      expect(group.memberTaIds, <String>['b']);
      expect(group.taId, 'b', reason: '主角色被删后要指向还活着的人');
      expect(group.activeTaId, 'b', reason: '当前发言人指着死 id 就再也发不了言');
    });

    test('成员被删光的群聊：成员表清空、会话本身保留', () async {
      final AppController controller = await _boot(_RecordingHive(
        tas: <TA>[_ta('a')],
        conversations: <Conversation>[
          _group('g1').copyWith(memberTaIds: <String>['a'], activeTaId: 'a'),
        ],
      ));

      await controller.deleteTa('a');

      expect(controller.groupConversations, hasLength(1), reason: '历史记录不能被连坐删掉');
      final Conversation group = controller.groupConversations.single;
      expect(group.memberTaIds, isEmpty);
      expect(group.activeTaId, '', reason: '没有成员时不能留着一个死的发言人');
    });

    test('与该角色无关的群聊不受影响，也不触发写盘', () async {
      final _RecordingHive hive = _RecordingHive(
        tas: <TA>[_ta('a'), _ta('b'), _ta('c')],
        conversations: <Conversation>[_group('g1')],
      );
      final AppController controller = await _boot(hive);

      await controller.deleteTa('c');

      expect(hive.saved, isEmpty, reason: '没变就不要写盘');
      expect(controller.groupConversations.single.memberTaIds, <String>['a', 'b']);
    });
  });

  group('自动续玩的接线', () {
    test('main.dart 必须把「全部会话」交给 resolveResumeTarget', () {
      final String src = File('lib/main.dart').readAsStringSync();
      final int at = src.indexOf('resolveResumeTarget(');
      expect(at, greaterThanOrEqualTo(0));
      final String call = src.substring(at, at + 360);
      expect(call, contains('allConversations'),
          reason: '只传单聊列表的话，群聊永远解析不到，还会把指针一并清掉');
    });
  });

}
