import 'package:dna/island/island_card.dart';
import 'package:dna/island/island_trial_chat_page.dart';
import 'package:dna/island/trial_chat.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「试聊」的契约。
///
/// 这里注入假的模型调用（[IslandTrialChatPage.completer]），所以测的是
/// **页面流程**：开场白、上限、强制二选一、本地暂存与丢弃。
/// 模型调用本身走的是主项目现成的 `buildLlmRequest` + `llmProvider`。
class _FakeHive extends HiveService {
  @override
  Future<void> init() async {}
  @override
  Future<List<TA>> getTas() async => <TA>[];
  @override
  Future<List<UserIdentity>> getIdentities() async => <UserIdentity>[];
  @override
  Future<List<World>> getWorlds() async => <World>[];
  @override
  Future<List<Conversation>> getConversations() async => <Conversation>[];
}

/// FitText 是 Text 子类且内部再包一层 Text，只匹配内层真实 Text。
Finder label(String s) => find.byWidgetPredicate(
  (Widget w) => w is Text && w.data == s && w is! FitText,
);

void main() {
  Future<AppController> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await c.initialize();
    return c;
  }

  IslandCard card() => IslandCard.fromJson(<String, dynamic>{
    'id': 'card-123',
    'name': '爱丽丝',
    'persona': '冷静、话少。',
    'intro': '来自北境的旅人。',
    'opening': '「你终于来了。」',
    'tags': <String>['北境'],
  });

  Future<void> pumpPage(
    WidgetTester tester,
    AppController c, {
    Future<String> Function(List<Map<String, String>>)? completer,
  }) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: IslandTrialChatPage(
          controller: c,
          card: card(),
          completer:
              completer ??
              (List<Map<String, String>> messages) async => '「嗯。」',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
  }

  /// 发一条消息（不 settle：发送中会转圈，settle 会一直等下去）。
  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
  }

  testWidgets('开场白先出场，并显示还能聊几句', (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpPage(tester, c);

    expect(label('「你终于来了。」'), findsOneWidget);
    expect(label('还能聊 9 句'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('聊满之后强制二选一：输入栏消失，出现导入/返回', (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpPage(tester, c);

    // 开场白算 1 条，每次发送 +2：1→3→5→7→9→11，第 5 次后聊满
    for (int i = 1; i <= 4; i++) {
      await send(tester, '第 $i 句');
      expect(find.byType(TextField), findsOneWidget, reason: '还没满，应该还能聊');
    }
    await send(tester, '第 5 句');

    expect(find.byType(TextField), findsNothing, reason: '聊满后不该还能输入');
    expect(label('聊满了，请选择'), findsOneWidget);
    expect(label('导入角色卡接着聊'), findsOneWidget);
    expect(label('返回'), findsOneWidget);
  });

  testWidgets('试聊记录暂存在本地：退出再进来还在', (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpPage(tester, c);
    await send(tester, '你好呀');

    final TrialChat? saved = await TrialChatStore.load('card-123');
    expect(saved, isNotNull);
    expect(saved!.messages.length, 3, reason: '开场白 + 用户 + 回复');
    expect(saved.messages.first.text, '「你终于来了。」');
    expect(saved.messages[1].text, '你好呀');
    expect(saved.messages.last.role, 'assistant');

    // 重新进页面：记录还在，不用重头开始
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpPage(tester, c);
    expect(label('你好呀'), findsOneWidget);
    expect(label('「嗯。」'), findsOneWidget);
  });

  testWidgets('返回 = 丢弃：确认后清空本地记录', (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpPage(tester, c);
    for (int i = 1; i <= 5; i++) {
      await send(tester, '第 $i 句');
    }
    expect(label('返回'), findsOneWidget);

    await tester.tap(label('返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(label('丢弃这次试聊？'), findsOneWidget);

    await tester.tap(label('丢弃'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(await TrialChatStore.load('card-123'), isNull);
  });

  testWidgets('模型报错时给出提示，不吞掉', (WidgetTester tester) async {
    final AppController c = await boot();
    await pumpPage(
      tester,
      c,
      completer: (List<Map<String, String>> messages) async =>
          throw Exception('没有配置模型'),
    );
    await send(tester, '在吗');

    expect(find.textContaining('没有配置模型'), findsWidgets);
  });
}
