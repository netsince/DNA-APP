import 'package:dna/main.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/chat_page.dart';
import 'package:dna/pages/conversation_create_page.dart';
import 'package:dna/pages/ta_editor_page.dart';
import 'package:dna/pages/ta_showcase_page.dart';
import 'package:dna/pages/settings/appearance_display_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/font_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 字号档位「最大档」的溢出冒烟闸门。
///
/// **注意:本文件只证明「不溢出」,不证明「字号生效」。**字号完全没变时它照样是绿的
/// (聊天正文曾经就是这样)。「真的生效」由 `font_scale_effect_test.dart`用高度对比证明。
///
/// 全局字号是**渲染层**缩放（MediaQuery.textScaler），它不动任何布局尺寸 ——
/// 所以真正的风险不是字号本身，而是「文字变大后挤出固定高度的容器」。
/// 这里把主要的几个面按手机尺寸（390×844）在最坏档位（1.45×）跑一遍：
/// 只要出现 RenderFlex/RenderBox 溢出，Flutter 会抛异常，测试就红。
///
/// 覆盖不到的面（社区各页、导出导入对话框等）靠真机在「超大」档巡检；
/// 这条测试的价值是把最容易回归的六个面钉住。
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
  id: id, name: '角色', gender: '', persona: '', intro: '', opening: '',
  tags: <String>[], images: <String, String>{}, dialogueStyle: <DialogueTurn>[],
);

Conversation _conv(String id, String taId) => Conversation(
  id: id, taId: taId, worldId: null, note: '测试会话',
  messages: <ConversationMessage>[
    ConversationMessage(id: 'm1', role: 'user', text: '你好，今天天气不错，我们出去走走吧。', timestamp: 1),
    ConversationMessage(id: 'm2', role: 'assistant', text: '好呀，我换件衣服就来。', timestamp: 2),
  ],
  backgroundMode: 'color', summaries: <ConversationSummary>[], archived: false,
  isGroup: false, groupName: '', groupPrompt: '', memberTaIds: <String>[taId], activeTaId: taId,
);

void main() {
  Future<AppController> boot(int step) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'completed_oobe': true,
      'show_splash_animation': false,
      'enable_community': false,
      'font_size_step': step,
    });
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(tas: <TA>[_ta('ta-1')], conversations: <Conversation>[_conv('c1', 'ta-1')]),
    );
    await c.initialize();
    return c;
  }

  Future<void> spin(WidgetTester t) async {
    for (int i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
  }

  testWidgets('最大档：主界面不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final AppController c = await boot(AppFontScale.maxStep);
    await tester.pumpWidget(DnaApp(controller: c));
    await spin(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('最大档：设置 → 界面与显示不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final AppController c = await boot(AppFontScale.maxStep);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext ctx, Widget? child) {
          final TextScaler? s = AppFontScale.textScalerOf(AppFontScale.maxStep);
          return MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: s),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: AppearanceDisplayPage(controller: c),
      ),
    );
    await spin(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('最大档：角色展示页不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final AppController c = await boot(AppFontScale.maxStep);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext ctx, Widget? child) {
          final TextScaler? s = AppFontScale.textScalerOf(AppFontScale.maxStep);
          return MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: s),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: TaShowcasePage(controller: c, taId: 'ta-1'),
      ),
    );
    await spin(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('最大档：角色编辑器不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final AppController c = await boot(AppFontScale.maxStep);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext ctx, Widget? child) {
          final TextScaler? s = AppFontScale.textScalerOf(AppFontScale.maxStep);
          return MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: s),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: TaEditorPage(controller: c),
      ),
    );
    await spin(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('最大档：新建会话页不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final AppController c = await boot(AppFontScale.maxStep);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext ctx, Widget? child) {
          final TextScaler? s = AppFontScale.textScalerOf(AppFontScale.maxStep);
          return MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: s),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: ConversationCreatePage(controller: c),
      ),
    );
    await spin(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('最大档：聊天页不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final AppController c = await boot(AppFontScale.maxStep);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext ctx, Widget? child) {
          final TextScaler? s = AppFontScale.textScalerOf(AppFontScale.maxStep);
          return MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: s),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: ChatPage(controller: c, conversationId: 'c1'),
      ),
    );
    await spin(tester);
    expect(tester.takeException(), isNull);
  });
}
