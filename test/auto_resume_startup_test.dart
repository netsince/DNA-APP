import 'package:dna/main.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/chat_page.dart';
import 'package:dna/pages/settings/appearance_display_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/resume_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/app_section.dart';
import 'package:dna/widgets/setting_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「打开应用自动继续上次聊天」的**接线**测试。
///
/// 决策逻辑（闸门 / 指针解析 / 存储）在 `auto_resume_test.dart` 里单测；
/// 这里只验真正容易接错的那一层：AppRoot 的启动时序、只跑一次、失效静默。
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

Conversation _conv(String id, String taId) => Conversation(
      id: id,
      taId: taId,
      worldId: null,
      note: '',
      messages: <ConversationMessage>[
        ConversationMessage(id: 'm1', role: 'user', text: '在吗', timestamp: 1),
      ],
      backgroundMode: 'color',
      summaries: <ConversationSummary>[],
      archived: false,
      isGroup: false,
      groupName: '',
      groupPrompt: '',
      memberTaIds: <String>[taId],
      activeTaId: taId,
    );

void main() {
  /// 起一个「已完成 OOBE、没有开场动画」的控制器。
  Future<AppController> boot({
    required bool autoOpen,
    String? pointer,
  }) async {
    final Map<String, Object> initial = <String, Object>{
      'completed_oobe': true,
      'show_splash_animation': false,
      'enable_community': false,
      'auto_open_last_chat': autoOpen,
    };
    if (pointer != null) {
      initial['resume_last_conversation_id'] = pointer;
    }
    SharedPreferences.setMockInitialValues(initial);
    final AppController controller = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(
        tas: <TA>[_ta('ta-1')],
        conversations: <Conversation>[_conv('c1', 'ta-1')],
      ),
    );
    await controller.initialize();
    return controller;
  }

  /// 不用 pumpAndSettle：聊天页有光标闪烁等持续动画，settle 会超时。
  Future<void> spin(WidgetTester tester) async {
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('开关开启 + 指针有效：启动后自动进入那场会话', (WidgetTester tester) async {
    final AppController controller = await boot(autoOpen: true, pointer: 'c1');
    await tester.pumpWidget(DnaApp(controller: controller));
    await spin(tester);

    expect(find.byType(ChatPage), findsOneWidget);
    expect(
      tester.widget<ChatPage>(find.byType(ChatPage)).conversationId,
      'c1',
    );
  });

  testWidgets('开关关闭：停在主界面，不推任何页面', (WidgetTester tester) async {
    final AppController controller = await boot(autoOpen: false, pointer: 'c1');
    await tester.pumpWidget(DnaApp(controller: controller));
    await spin(tester);

    expect(find.byType(ChatPage), findsNothing);
    expect(find.byType(AppSectionShell), findsOneWidget);
  });

  testWidgets('指针指向已删会话：静默放弃并清掉指针', (WidgetTester tester) async {
    final AppController controller = await boot(autoOpen: true, pointer: 'c-gone');
    await tester.pumpWidget(DnaApp(controller: controller));
    await spin(tester);

    expect(find.byType(ChatPage), findsNothing);
    expect(find.byType(AppSectionShell), findsOneWidget);
    expect(await ResumeService.instance.lastConversationId(), isNull);
  });

  testWidgets('连续两次「自动续玩时进程死掉」：自行关掉开关，不再弹进去', (WidgetTester tester) async {
    // 上一次启动留下了未确认的尝试，且已经失败过一次。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'completed_oobe': true,
      'show_splash_animation': false,
      'enable_community': false,
      'auto_open_last_chat': true,
      'resume_last_conversation_id': 'c1',
      'resume_pending_conversation_id': 'c1',
      'resume_startup_failures': 1,
    });
    final AppController controller = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(
        tas: <TA>[_ta('ta-1')],
        conversations: <Conversation>[_conv('c1', 'ta-1')],
      ),
    );
    await controller.initialize();

    await tester.pumpWidget(DnaApp(controller: controller));
    await spin(tester);

    expect(find.byType(ChatPage), findsNothing, reason: '不能把用户再弹进同一个会话');
    expect(controller.settings.autoOpenLastChat, isFalse, reason: '开关应被自动关掉');
  });

  testWidgets('设置里的开关能开：状态真的落到 controller', (WidgetTester tester) async {
    final AppController controller = await boot(autoOpen: false, pointer: null);
    await tester.pumpWidget(
      MaterialApp(home: AppearanceDisplayPage(controller: controller)),
    );
    await tester.pump();

    // 页面是 ListView（懒构建），开关在靠下的「启动与导航」分区里，
    // 所以按 widget 属性找、再滚到可见处 —— 不按文案找（FitText 可能渲染
    // 出多个 Text 节点，find.text 会匹配到多个）。
    final Finder target = find.byWidgetPredicate(
      (Widget w) => w is SettingSwitch && w.title == '自动继续上次聊天',
    );
    await tester.dragUntilVisible(
      target,
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(controller.settings.autoOpenLastChat, isFalse);

    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(controller.settings.autoOpenLastChat, isTrue);
  });

  testWidgets('打开聊天页就把指针写回（唯一写入入口真的在生效）', (WidgetTester tester) async {
    final AppController controller = await boot(autoOpen: false, pointer: null);
    expect(await ResumeService.instance.lastConversationId(), isNull);

    // 直接挂一个聊天页 —— 等价于用户从消息列表点进会话。
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(controller: controller, conversationId: 'c1'),
      ),
    );
    await spin(tester);

    expect(await ResumeService.instance.lastConversationId(), 'c1');
  });
}
