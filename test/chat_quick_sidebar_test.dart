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
import 'package:dna/theme/tokens.dart';
import 'package:dna/utils/conversation_labels.dart';
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

  // 渲染群聊时聊天页会补默认值并落盘;测试里没有 Hive,写成空实现。
  @override
  Future<void> upsertConversation(Conversation conversation) async {}
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
        conversationLabel(
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
        conversationLabel(
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
        conversationLabel(
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
        conversationLabel(
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
        conversationLabel(
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
        conversationLabel(
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
        conversationLabel(
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
                  width: collapsed
                      ? AppSize.chatSidebarHandle
                      : kChatSidebarFullWidth,
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
        final Finder container = find
            .ancestor(
              of: find.byTooltip(label),
              matching: find.byType(AnimatedContainer),
            )
            .first;
        final Decoration? decoration = tester
            .widget<AnimatedContainer>(container)
            .decoration;
        return (decoration as BoxDecoration?)?.color ?? Colors.transparent;
      }

      expect(rowColor('初遇'), isNot(Colors.transparent), reason: '当前聊天应高亮');
      expect(rowColor('今天天气真…'), Colors.transparent, reason: '非当前聊天不该高亮');
    });

    testWidgets('收起后只剩把手宽,把手仍在(可再展开)', (WidgetTester tester) async {
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

      // 收起 = 只剩把手宽(内容被 ClipRect 裁掉,是"滑出去"而不是移除)
      expect(
        tester.getSize(find.byType(ChatQuickSidebar)).width,
        AppSize.chatSidebarHandle,
      );
      final Finder handle = find.byTooltip('展开快速切换栏');
      expect(handle, findsOneWidget);

      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(toggled, isTrue);
    });
  });
  group('聊天页接入(原地换会话)', () {
    Future<AppController> boot() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppController c = AppController(
        settingsService: SettingsService(),
        openAiService: OpenAiService(),
        taService: TaService(),
        hiveService: _FakeHive(
          tas: <TA>[_ta('taA', '爱丽丝'), _ta('taB', '鲍勃')],
          conversations: <Conversation>[
            _conv(
              id: 'c1',
              taId: 'taA',
              note: '初遇',
              messages: <ConversationMessage>[_msg('user', '你好', 1)],
            ),
            _conv(
              id: 'c3',
              taId: 'taB',
              messages: <ConversationMessage>[_msg('user', '在吗', 3)],
            ),
          ],
        ),
      );
      await c.initialize();
      return c;
    }

    /// 不用 pumpAndSettle:聊天页里有光标闪烁等持续动画,settle 会超时。
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    String currentId(WidgetTester tester) => tester
        .widget<ChatConversationView>(find.byType(ChatConversationView))
        .conversationId;

    testWidgets('宽窗口:侧栏可见;两级点击后原地换会话(不新增路由)', (WidgetTester tester) async {
      final AppController c = await boot();
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: ChatPage(controller: c, conversationId: 'c1')),
      );
      await settle(tester);

      expect(find.byType(ChatQuickSidebar), findsOneWidget);
      expect(currentId(tester), 'c1');
      final State shellState = tester.state(find.byType(ChatPage));
      final State viewStateBefore = tester.state(
        find.byType(ChatConversationView),
      );

      // 第一步:点鲍勃(只换右列)
      await tester.tap(find.byTooltip('鲍勃'));
      await settle(tester);
      expect(currentId(tester), 'c1', reason: '点角色不该切会话');
      expect(find.byTooltip('在吗'), findsOneWidget);

      // 第二步:点聊天 → 原地换会话
      await tester.tap(find.byTooltip('在吗'));
      await settle(tester);

      expect(currentId(tester), 'c3');
      // 壳的 State 没变 ⇒ 没有新路由、没有重建整页
      expect(
        identical(tester.state(find.byType(ChatPage)), shellState),
        isTrue,
        reason: '换会话不该重建聊天页(那会堆路由)',
      );
      // 会话视图的 State 换了 ⇒ 该重置的状态确实重置了
      expect(
        identical(tester.state(find.byType(ChatConversationView)), viewStateBefore),
        isFalse,
        reason: '会话视图应随会话 id 重建,避免残留上一会话的状态',
      );
      expect(find.byType(ChatConversationView), findsOneWidget);
    });

    testWidgets('窄窗口(竖屏):不显示侧栏', (WidgetTester tester) async {
      final AppController c = await boot();
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: ChatPage(controller: c, conversationId: 'c1')),
      );
      await settle(tester);

      expect(find.byType(ChatQuickSidebar), findsNothing);
      expect(find.byType(ChatConversationView), findsOneWidget);
    });

    testWidgets('设置里关掉:宽窗口也不显示侧栏', (WidgetTester tester) async {
      final AppController c = await boot();
      await c.saveChatQuickSidebar(false);
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: ChatPage(controller: c, conversationId: 'c1')),
      );
      await settle(tester);

      expect(find.byType(ChatQuickSidebar), findsNothing);
    });
  });
  group('折叠状态与动画', () {
    Future<AppController> boot() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppController c = AppController(
        settingsService: SettingsService(),
        openAiService: OpenAiService(),
        taService: TaService(),
        hiveService: _FakeHive(
          tas: <TA>[_ta('taA', '爱丽丝'), _ta('taB', '鲍勃')],
          conversations: <Conversation>[
            _conv(
              id: 'c1',
              taId: 'taA',
              note: '初遇',
              messages: <ConversationMessage>[_msg('user', '你好', 1)],
            ),
            _conv(
              id: 'c3',
              taId: 'taB',
              messages: <ConversationMessage>[_msg('user', '在吗', 3)],
            ),
          ],
        ),
      );
      await c.initialize();
      return c;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    double sidebarWidth(WidgetTester tester) =>
        tester.getSize(find.byType(ChatQuickSidebar)).width;

    testWidgets('进入页面时按上次的折叠状态就位(不需要手动点一下)', (
      WidgetTester tester,
    ) async {
      final AppController c = await boot();
      await c.saveChatQuickSidebarCollapsed(true);
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: ChatPage(controller: c, conversationId: 'c1')),
      );
      await settle(tester);

      expect(find.byType(ChatQuickSidebar), findsOneWidget);
      expect(sidebarWidth(tester), AppSize.chatSidebarHandle);
    });

    testWidgets('点把手:有动画地展开,并把状态写回设置', (WidgetTester tester) async {
      final AppController c = await boot();
      await c.saveChatQuickSidebarCollapsed(true);
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: ChatPage(controller: c, conversationId: 'c1')),
      );
      await settle(tester);
      expect(sidebarWidth(tester), AppSize.chatSidebarHandle);

      await tester.tap(find.byTooltip('展开快速切换栏'));
      await tester.pump(); // 动画开始
      await tester.pump(const Duration(milliseconds: 100)); // 动画中段

      // 中段宽度介于"收起"与"展开"之间 ⇒ 是动画,不是硬切
      final double mid = sidebarWidth(tester);
      expect(mid, greaterThan(AppSize.chatSidebarHandle));
      expect(mid, lessThan(kChatSidebarFullWidth));

      await settle(tester);
      expect(sidebarWidth(tester), closeTo(kChatSidebarFullWidth, 0.5));
      expect(c.settings.chatQuickSidebarCollapsed, isFalse);
    });

    testWidgets('换会话时信息页淡入淡出(切换过程中新旧并存)', (WidgetTester tester) async {
      final AppController c = await boot();
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: ChatPage(controller: c, conversationId: 'c1')),
      );
      await settle(tester);
      expect(find.byType(ChatConversationView), findsOneWidget);

      await tester.tap(find.byTooltip('鲍勃'));
      await settle(tester);
      await tester.tap(find.byTooltip('在吗'));
      await tester.pump(); // 切换开始
      await tester.pump(const Duration(milliseconds: 80));

      // 淡入淡出中:旧会话视图尚未移除,与新的一起在场
      expect(find.byType(ChatConversationView), findsNWidgets(2));

      await settle(tester);
      expect(find.byType(ChatConversationView), findsOneWidget);
    });

    testWidgets('侧栏是磨砂浮层:底下有模糊,且换会话时原地不动', (
      WidgetTester tester,
    ) async {
      final AppController c = await boot();
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: ChatPage(controller: c, conversationId: 'c1')),
      );
      await settle(tester);

      // 模糊层(透出底下的角色立绘)
      expect(
        find.descendant(
          of: find.byType(ChatQuickSidebar),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      // 换会话时侧栏**原地不动**:退场动画只作用在会话视图那一层,
      // 侧栏是同级浮层,不会跟着滑/闪。
      final Rect railBefore = tester.getRect(find.byType(ChatQuickSidebar));
      await tester.tap(find.byTooltip('鲍勃'));
      await settle(tester);
      await tester.tap(find.byTooltip('在吗'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80)); // 退场动画中
      expect(find.byType(ChatQuickSidebar), findsOneWidget);
      expect(tester.getRect(find.byType(ChatQuickSidebar)), railBefore);
      // 退场中:旧会话还在(滑出/淡出),新会话已在下面就位
      expect(find.byType(ChatConversationView), findsNWidgets(2));
      await settle(tester);
      expect(find.byType(ChatConversationView), findsOneWidget);
      // 换角色时右列整列淡入(单列表淡入:不保留旧列表,避免两个列表
      // 共用同一个 ScrollController)。此时当前会话已是鲍勃的,
      // 点爱丽丝验证右列切换。
      await tester.tap(find.byTooltip('爱丽丝'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final Iterable<Opacity> fading = tester.widgetList<Opacity>(
        find.descendant(
          of: find.byType(ChatQuickSidebar),
          matching: find.byType(Opacity),
        ),
      );
      expect(
        fading.any((Opacity o) => o.opacity > 0 && o.opacity < 1),
        isTrue,
        reason: '换角色应有淡入过渡,而不是硬切',
      );
      await settle(tester);
    });
    testWidgets('底部提示不会被侧栏遮挡(Scaffold 的"家具"一起内缩)', (
      WidgetTester tester,
    ) async {
      final AppController c = await boot();
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: ChatPage(controller: c, conversationId: 'c1')),
      );
      await settle(tester);

      final Rect rail = tester.getRect(find.byType(ChatQuickSidebar));
      expect(rail.width, closeTo(kChatSidebarFullWidth, 0.5));

      // 弹一条底部提示(应用里到处都在用这条路径)
      ScaffoldMessenger.of(
        tester.element(find.byType(ChatConversationView)),
      ).showSnackBar(const SnackBar(content: Text('测试提示')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final Rect snack = tester.getRect(find.byType(SnackBar));
      expect(
        snack.left,
        greaterThanOrEqualTo(rail.right - 0.5),
        reason: '提示条的左缘落在侧栏底下了 —— 会被侧栏压住',
      );
      expect(snack.width, lessThanOrEqualTo(1400 - rail.width + 0.5));
    });
  });
  group('左右滑动切换角色', () {
    /// 爱丽丝有两个会话:c1 较旧、c2 较新(用来验证"固定会话不漂移")。
    Future<AppController> boot({bool swipe = true}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppController c = AppController(
        settingsService: SettingsService(),
        openAiService: OpenAiService(),
        taService: TaService(),
        hiveService: _FakeHive(
          tas: <TA>[_ta('taA', '爱丽丝'), _ta('taB', '鲍勃')],
          conversations: <Conversation>[
            _conv(
              id: 'c1',
              taId: 'taA',
              note: '初遇',
              messages: <ConversationMessage>[_msg('user', '你好', 1000)],
            ),
            _conv(
              id: 'c2',
              taId: 'taA',
              messages: <ConversationMessage>[_msg('user', '最近一句', 2000)],
            ),
            _conv(
              id: 'c3',
              taId: 'taB',
              messages: <ConversationMessage>[_msg('user', '在吗', 3000)],
            ),
            // 群聊:不参与左右滑动
            _conv(
              id: 'g1',
              taId: 'taA',
              isGroup: true,
              groupName: '三人行',
              memberTaIds: <String>['taA'],
              messages: <ConversationMessage>[_msg('user', '群里的消息', 4000)],
            ),
          ],
        ),
      );
      await c.initialize();
      if (!swipe) {
        await c.saveChatSwipeSwitch(false);
      }
      return c;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    String currentId(WidgetTester tester) => tester
        .widget<ChatConversationView>(find.byType(ChatConversationView))
        .conversationId;

    Future<void> swipeBy(WidgetTester tester, double dx) async {
      // 在聊天视图中心横向拖动 = 落在消息区(手势只覆盖消息区)
      await tester.drag(find.byType(ChatConversationView), Offset(dx, 0));
      await settle(tester);
    }

    Future<void> pump(
      WidgetTester tester,
      AppController c, {
      required String conversationId,
      bool isGroup = false,
    }) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(
            controller: c,
            conversationId: conversationId,
            isGroup: isGroup,
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('左滑下一个角色、右滑回上一个,且**回到原会话不漂移**', (
      WidgetTester tester,
    ) async {
      final AppController c = await boot();
      // 从爱丽丝的**旧**会话进入(c2 才是她最近的)
      await pump(tester, c, conversationId: 'c1');
      expect(currentId(tester), 'c1');

      await swipeBy(tester, -300); // 左滑 → 下一个角色
      expect(currentId(tester), 'c3', reason: '应切到鲍勃的会话');

      await swipeBy(tester, 300); // 右滑 → 上一个角色
      expect(
        currentId(tester),
        'c1',
        reason: '应回到刚才那个会话,而不是爱丽丝"最近"的 c2 —— 否则你正在看的会话会被换掉',
      );
    });

    testWidgets('到头绕回:最后一个角色再左滑回到第一个', (WidgetTester tester) async {
      final AppController c = await boot();
      await pump(tester, c, conversationId: 'c3'); // 鲍勃(最后一个角色)

      await swipeBy(tester, -300);
      // 爱丽丝还没被访问过 ⇒ 兜底用她最近活跃的会话 c2
      expect(currentId(tester), 'c2');

      await swipeBy(tester, 300); // 第一个角色再右滑 ⇒ 绕回最后一个
      expect(currentId(tester), 'c3');
    });
    testWidgets('跟手翻页:拖动时当前页跟着手指走,并露出下一个角色的预览', (
      WidgetTester tester,
    ) async {
      final AppController c = await boot();
      await pump(tester, c, conversationId: 'c1');
      expect(currentId(tester), 'c1');

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(ChatConversationView)),
      );
      // 分两步:识别器接受拖动的那一次 move 不产生 update(真实手指
      // 同样有约 18px 死区),所以先走一个 slop 再走主体。
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();

      // 当前页跟着手指左移(不是"松手才动")
      final Rect moved = tester.getRect(find.byType(ChatConversationView));
      expect(moved.left, lessThan(0), reason: '当前页应跟手平移');
      // 旁边露出下一个角色(鲍勃)的预览
      expect(find.text('鲍勃'), findsWidgets, reason: '应露出下一页预览');

      // 松手 → 滑出旧页并完成切换
      await gesture.up();
      await settle(tester);
      expect(currentId(tester), 'c3');
    });

    testWidgets('拖不够阈值:弹回原位,不切换', (WidgetTester tester) async {
      final AppController c = await boot();
      await pump(tester, c, conversationId: 'c1');

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(ChatConversationView)),
      );
      await gesture.moveBy(const Offset(-20, 0)); // 让识别器接受拖动
      await gesture.moveBy(const Offset(-30, 0)); // 累计 -30,小于 64 阈值
      await tester.pump();
      await gesture.up();
      await settle(tester);

      expect(currentId(tester), 'c1', reason: '没拖够应弹回,不切换');
      // 弹回后回到原位
      final Rect rect = tester.getRect(find.byType(ChatConversationView));
      expect(rect.left, closeTo(0, 1.0));
    });
    testWidgets('上下滚动不会误触发左右切换(纵向占优时把手势让给列表)', (
      WidgetTester tester,
    ) async {
      final AppController c = await boot();
      await pump(tester, c, conversationId: 'c1');

      // 纵向占优,但横向漂移 80px —— 已经超过 64 的切换阈值。
      // 修方向判定之前,这种"上下滑带点偏"会被抢成横滑并切换。
      await tester.drag(
        find.byType(ChatConversationView),
        const Offset(80, -300),
      );
      await settle(tester);
      expect(currentId(tester), 'c1', reason: '纵向滚动不该触发切换');
    });

    testWidgets('斜着滑但横向明显占优时仍能切换', (WidgetTester tester) async {
      final AppController c = await boot();
      await pump(tester, c, conversationId: 'c1');

      // 横向明显占优(200 vs 40):应正常切换
      await tester.drag(
        find.byType(ChatConversationView),
        const Offset(-200, 40),
      );
      await settle(tester);
      expect(currentId(tester), 'c3');
    });

    testWidgets('设置里关掉后滑动不生效', (WidgetTester tester) async {
      final AppController c = await boot(swipe: false);
      await pump(tester, c, conversationId: 'c1');

      await swipeBy(tester, -300);
      expect(currentId(tester), 'c1');
    });

    testWidgets('群聊不参与左右滑动', (WidgetTester tester) async {
      final AppController c = await boot();
      await pump(tester, c, conversationId: 'g1', isGroup: true);
      expect(currentId(tester), 'g1');

      await swipeBy(tester, -300);
      expect(currentId(tester), 'g1', reason: '群聊里滑动应无动作');
      await swipeBy(tester, 300);
      expect(currentId(tester), 'g1');
    });
  });
}