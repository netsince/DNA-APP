import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/chat_page.dart';
import 'package:dna/pages/ta_editor_page.dart';
import 'package:dna/pages/ta_showcase_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/ta_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 角色展示页的契约。
///
/// 设计意图:点「我家」卡片的默认意图是"看看这是谁",所以先进展示页,
/// 编辑收成右上角小图标;归档收进「⋮」;主按钮留给「开始新聊天」;
/// 「已有聊天」与聊天页侧栏共用同一套排序与文案。
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
  @override
  Future<void> upsertConversation(Conversation conversation) async {}
  @override
  Future<void> upsertTa(TA ta) async {}
}

TA _ta(String id, String name) => TA(
  id: id,
  name: name,
  gender: '女',
  persona: '冷静、话少、偶尔毒舌。',
  intro: '来自北境的旅人。',
  opening: '「你终于来了。」',
  tags: <String>['北境', '旅人'],
  images: <String, String>{},
  dialogueStyle: <DialogueTurn>[
    const DialogueTurn(user: '你好', assistant: '「嗯。」'),
  ],
  archived: false,
);

Conversation _conv({
  required String id,
  required String taId,
  String note = '',
  List<ConversationMessage> messages = const <ConversationMessage>[],
  bool pinned = false,
}) => Conversation(
  id: id,
  taId: taId,
  worldId: null,
  note: note,
  messages: messages,
  backgroundMode: 'none',
  summaries: <ConversationSummary>[],
  archived: false,
  isGroup: false,
  groupName: '',
  groupPrompt: '',
  memberTaIds: <String>[taId],
  activeTaId: taId,
  pinned: pinned,
);

ConversationMessage _msg(String text, int at) =>
    ConversationMessage(id: 'm$at', role: 'user', text: text, timestamp: at);

/// FitText 是 Text 子类且内部再包一层 Text,只匹配内层真实 Text。
Finder label(String s) =>
    find.byWidgetPredicate((Widget w) => w is Text && w.data == s && w is! FitText);

void main() {
  Future<AppController> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(
        tas: <TA>[_ta('taA', '爱丽丝')],
        conversations: <Conversation>[
          // 置顶的排在前面;另一条按最近消息排
          _conv(
            id: 'c1',
            taId: 'taA',
            note: '初遇',
            pinned: true,
            messages: <ConversationMessage>[_msg('你好', 1000)],
          ),
          _conv(
            id: 'c2',
            taId: 'taA',
            messages: <ConversationMessage>[_msg('今天天气真不错啊', 2000)],
          ),
        ],
      ),
    );
    await c.initialize();
    return c;
  }

  Future<void> pumpShowcase(
    WidgetTester tester,
    AppController c, {
    Size size = const Size(600, 1200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: TaShowcasePage(controller: c, taId: 'taA')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('介绍 tab:显示角色信息;编辑收在右上角小图标里', (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpShowcase(tester, c);

    // hero 标题 + 介绍内容
    expect(label('爱丽丝'), findsWidgets);
    expect(label('来自北境的旅人。'), findsOneWidget); // 简介
    expect(label('冷静、话少、偶尔毒舌。'), findsOneWidget); // 人设
    expect(label('「你终于来了。」'), findsOneWidget); // 开场白
    expect(label('北境'), findsOneWidget); // 标签

    // 右上角「编辑」小图标 → 进原编辑器
    await tester.tap(find.byTooltip('编辑'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TaEditorPage), findsOneWidget);
  });

  testWidgets('已有聊天 tab:复用侧栏的排序与文案,点一条进对应聊天', (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpShowcase(tester, c);

    // 切到「已有聊天」
    await tester.tap(label('已有聊天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 备注优先 → 「初遇」;无备注 → 最后一条用户消息前 5 字 + 省略号
    expect(label('初遇'), findsOneWidget);
    expect(label('今天天气真…'), findsOneWidget);
    // 置顶的排前面
    final double pinnedTop = tester.getRect(label('初遇')).top;
    final double otherTop = tester.getRect(label('今天天气真…')).top;
    expect(pinnedTop, lessThan(otherTop));

    await tester.tap(label('今天天气真…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<ChatConversationView>(find.byType(ChatConversationView))
          .conversationId,
      'c2',
    );
  });

  testWidgets('「⋮」里是归档;主按钮开始新聊天', (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpShowcase(tester, c);

    // 「⋮」点开才出现归档
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(label('归档'), findsOneWidget);
    await tester.tap(label('归档'));
    await tester.pumpAndSettle();
    expect(c.getTaById('taA')!.archived, isTrue);

    // 主按钮:新建一个会话并进入
    final int before = c.conversations.length;
    await tester.tap(label('开始新聊天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.conversations.length, before + 1);
    expect(find.byType(ChatConversationView), findsOneWidget);
  });
  testWidgets('宽窗口一分为二:hero 在左,信息栏在右', (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpShowcase(tester, c, size: const Size(1400, 900));

    // 右侧信息栏:tab 落在窗口右半边(窄窗口时它贴着左边)
    final double tabLeft = tester.getRect(label('介绍')).left;
    expect(tabLeft, greaterThan(1400 * 0.4), reason: '宽窗口应把信息栏放到右半边');

    // 左栏是 hero(没有立绘时是首字占位),占据左侧 40%
    final Rect heroAvatar = tester.getRect(find.byType(TaAvatar).first);
    expect(heroAvatar.left, lessThan(1400 * 0.4));

    // 窄窗口同一页仍是单列:tab 靠左
    await pumpShowcase(tester, c, size: const Size(600, 1200));
    expect(tester.getRect(label('介绍')).left, lessThan(300));
  });

  testWidgets('切换 tab 有过渡:过程中新旧内容短暂并存', (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpShowcase(tester, c);
    expect(label('来自北境的旅人。'), findsOneWidget); // 介绍内容

    await tester.tap(label('已有聊天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60)); // 过渡中段

    // 淡入淡出进行中:介绍与聊天内容同时在场 ⇒ 是过渡而不是硬切
    expect(label('来自北境的旅人。'), findsOneWidget);
    expect(label('初遇'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(label('来自北境的旅人。'), findsNothing);
    expect(label('初遇'), findsOneWidget);
  });
}
