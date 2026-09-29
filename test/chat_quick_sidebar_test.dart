import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/pages/chat_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/ta_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 聊天「快速切换侧栏」的组件契约。
///
/// 结构:左列角色(按「我家」顺序) → 右列该角色的聊天(注释)。
/// 两级选择:点角色只换右列,**点聊天才切会话**。
class _FakeHive extends HiveService {
  _FakeHive({required this.tas, required this.conversations});

  final List<TA> tas;
  final List<Conversation> conversations;

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
}

TA _ta(String id, String name) => TA(
  id: id,
  name: name,
  gender: '',
  persona: '',
  intro: '',
  opening: '',
  tags: <String>[],
  images: <String, String>{},
  dialogueStyle: <DialogueTurn>[],
  archived: false,
);

ConversationMessage _msg(String role, String text, int at) =>
    ConversationMessage(id: '$role-$at', role: role, text: text, timestamp: at);

Conversation _conv({
  required String id,
  required String taId,
  String note = '',
  List<ConversationMessage> messages = const <ConversationMessage>[],
  bool isGroup = false,
  String groupName = '',
  List<String> memberTaIds = const <String>[],
  bool archived = false,
  bool pinned = false,
}) => Conversation(
  id: id,
  taId: taId,
  worldId: null,
  note: note,
  messages: messages,
  backgroundMode: 'color',
  summaries: <ConversationSummary>[],
  archived: archived,
  isGroup: isGroup,
  groupName: groupName,
  groupPrompt: '',
  memberTaIds: memberTaIds,
  activeTaId: taId,
  pinned: pinned,
);

void main() {
  group('注释规则', () {
    test('备注优先', () {
      expect(
        chatSidebarAnnotation(
          _conv(
            id: 'c',
            taId: 't',
            note: '初遇',
            messages: <ConversationMessage>[_msg('user', '你好呀', 1)],
          ),
        ),
        '初遇',
      );
    });

    test('无备注 → 最后一条用户消息前 5 字 + 省略号', () {
      expect(
        chatSidebarAnnotation(
          _conv(
            id: 'c',
            taId: 't',
            messages: <ConversationMessage>[_msg('user', '今天天气真不错啊', 1)],
          ),
        ),
        '今天天气真…',
      );
    });

    test('不足 5 字不加省略号', () {
      expect(
        chatSidebarAnnotation(
          _conv(
            id: 'c',
            taId: 't',
            messages: <ConversationMessage>[_msg('user', '在吗', 1)],
          ),
        ),
        '在吗',
      );
    });

    test('取的是最后一条**用户**消息(AI 消息不算)', () {
      expect(
        chatSidebarAnnotation(
          _conv(
            id: 'c',
            taId: 't',
            messages: <ConversationMessage>[
              _msg('user', '第一句用户话', 1),
              _msg('assistant', 'AI 的回复内容', 2),
            ],
          ),
        ),
        '第一句用户…',
      );
    });

    test('换行与连续空白压成单空格', () {
      expect(
        chatSidebarAnnotation(
          _conv(
            id: 'c',
            taId: 't',
            messages: <ConversationMessage>[_msg('user', '你好\n\n   世界', 1)],
          ),
        ),
        '你好 世界',
      );
    });

    test('没有任何用户消息 → 新对话', () {
      expect(
        chatSidebarAnnotation(
          _conv(
            id: 'c',
            taId: 't',
            messages: <ConversationMessage>[_msg('assistant', '开场白', 1)],
          ),
        ),
        '新对话',
      );
    });

    test('只有空白的备注视为没有备注', () {
      expect(
        chatSidebarAnnotation(
          _conv(
            id: 'c',
            taId: 't',
            note: '   ',
            messages: <ConversationMessage>[_msg('user', '回退到这里', 1)],
          ),
        ),
        '回退到这里',
      );
    });
  });

  group('角色头像首字兜底', () {
    test('取名字首字', () {
      expect(TaAvatar.initialOf('爱丽丝'), '爱');
      expect(TaAvatar.initialOf(' 鲍勃 '), '鲍');
    });

    test('空名字给 ?', () {
      expect(TaAvatar.initialOf(''), '?');
      expect(TaAvatar.initialOf('   '), '?');
      expect(TaAvatar.initialOf(null), '?');
    });

    test('代理对(emoji)不会被拆坏', () {
      expect(TaAvatar.initialOf('😀小丑'), '😀');
    });
  });

  group('侧栏两级选择', () {
    Future<AppController> boot() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppController c = AppController(
        settingsService: SettingsService(),
        openAiService: OpenAiService(),
        taService: TaService(),
        hiveService: _FakeHive(
          tas: <TA>[_ta('taA', '爱丽丝'), _ta('taB', '鲍勃'), _ta('taC', '卡罗尔')],
          conversations: <Conversation>[
            _conv(
              id: 'c1',
              taId: 'taA',
              note: '初遇',
              messages: <ConversationMessage>[_msg('user', '你好', 1)],
            ),
            _conv(
              id: 'c2',
              taId: 'taA',
              messages: <ConversationMessage>[_msg('user', '今天天气真不错啊', 2)],
            ),
            _conv(
              id: 'c3',
              taId: 'taB',
              messages: <ConversationMessage>[_msg('user', '在吗', 3)],
            ),
            // 群聊:不进侧栏
            _conv(
              id: 'g1',
              taId: 'taC',
              isGroup: true,
              groupName: '三人行',
              memberTaIds: <String>['taC'],
            ),
            // 归档:不进侧栏
            _conv(id: 'c9', taId: 'taA', archived: true, note: '旧账'),
          ],
        ),
      );
      await c.initialize();
      return c;
    }

    Future<void> pumpSidebar(
      WidgetTester tester, {
      required AppController controller,
      required String currentId,
      required List<String> selected,
      bool collapsed = false,
      VoidCallback? onToggle,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: <Widget>[
                ChatQuickSidebar(
                  controller: controller,
                  currentConversationId: currentId,
                  onSelectConversation: selected.add,
                  collapsed: collapsed,
                  onToggleCollapsed: onToggle ?? () {},
                ),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('左列只列有 1:1 会话的角色(群聊/归档不算)', (WidgetTester tester) async {
      final AppController c = await boot();
      await pumpSidebar(
        tester,
        controller: c,
        currentId: 'c1',
        selected: <String>[],
      );

      expect(find.byTooltip('爱丽丝'), findsOneWidget);
      expect(find.byTooltip('鲍勃'), findsOneWidget);
      // 卡罗尔只有群聊 → 不该出现在侧栏
      expect(find.byTooltip('卡罗尔'), findsNothing);
    });

    testWidgets('进入时自动定位当前路径:选中当前角色并列出它的聊天', (WidgetTester tester) async {
      final AppController c = await boot();
      await pumpSidebar(
        tester,
        controller: c,
        currentId: 'c3', // 鲍勃的聊天
        selected: <String>[],
      );

      // 右列应是鲍勃的聊天(而不是爱丽丝的)
      expect(find.byTooltip('在吗'), findsOneWidget);
      expect(find.byTooltip('初遇'), findsNothing);
    });

    testWidgets('点角色只换右列,点聊天才回调切换', (WidgetTester tester) async {
      final AppController c = await boot();
      final List<String> selected = <String>[];
      await pumpSidebar(
        tester,
        controller: c,
        currentId: 'c1',
        selected: selected,
      );

      // 初始:爱丽丝的两个聊天(备注 / 最后用户消息截断),归档的不出现
      expect(find.byTooltip('初遇'), findsOneWidget);
      expect(find.byTooltip('今天天气真…'), findsOneWidget);
      expect(find.byTooltip('旧账'), findsNothing);

      // 第一步:点鲍勃 —— 只换右列,不切会话
      await tester.tap(find.byTooltip('鲍勃'));
      await tester.pumpAndSettle();
      expect(selected, isEmpty, reason: '点角色不该直接切聊天');
      expect(find.byTooltip('在吗'), findsOneWidget);
      expect(find.byTooltip('初遇'), findsNothing);

      // 第二步:点聊天 —— 才回调切换
      await tester.tap(find.byTooltip('在吗'));
      await tester.pumpAndSettle();
      expect(selected, <String>['c3']);
    });

    testWidgets('当前聊天高亮,其它不高亮', (WidgetTester tester) async {
      final AppController c = await boot();
      await pumpSidebar(
        tester,
        controller: c,
        currentId: 'c1',
        selected: <String>[],
      );

      Color rowColor(String label) {
        final Finder material = find
            .ancestor(of: find.byTooltip(label), matching: find.byType(Material))
            .first;
        return tester.widget<Material>(material).color ?? Colors.transparent;
      }

      expect(rowColor('初遇'), isNot(Colors.transparent), reason: '当前聊天应高亮');
      expect(rowColor('今天天气真…'), Colors.transparent, reason: '非当前聊天不该高亮');
    });

    testWidgets('收起后两列消失,把手仍在(可再展开)', (WidgetTester tester) async {
      final AppController c = await boot();
      bool toggled = false;
      await pumpSidebar(
        tester,
        controller: c,
        currentId: 'c1',
        selected: <String>[],
        collapsed: true,
        onToggle: () => toggled = true,
      );

      expect(find.byTooltip('爱丽丝'), findsNothing);
      expect(find.byTooltip('初遇'), findsNothing);
      final Finder handle = find.byTooltip('展开快速切换栏');
      expect(handle, findsOneWidget);

      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(toggled, isTrue);
    });
  });
}
