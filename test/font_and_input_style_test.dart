import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dna/models/app_settings.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/chat/ui/widgets/chat_input_bar.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';

/// 0.3.0 用户反馈的两项「给用户自己选」：
///
/// * 字体：内置思源黑体把手机主题里的自定义字体盖掉了 —— 默认改成跟随
///   系统字体，想用内置字体的自己切；
/// * 聊天输入栏：胶囊样式有人觉得不好用 —— 保留胶囊，同时把 0.2.0 的
///   「描边输入框 + 框外按钮」旧样式做成可选项。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppController> boot(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await c.initialize();
    return c;
  }

  group('字体设置', () {
    test('familyFor：跟随系统 = 不指定字体族；思源黑体 = 内置族名', () {
      expect(AppFont.familyFor(AppFont.modeSystem), isNull);
      expect(AppFont.familyFor(AppFont.modeSourceHan), AppFont.family);
      expect(AppFont.familyFor('无法识别的值'), isNull, reason: '未知值一律回退系统字体');
      expect(
        AppFont.modes,
        <String>[AppFont.modeSystem, AppFont.modeSourceHan],
      );
    });

    test('默认是系统字体（不再强制内置字体）', () {
      expect(AppSettings.empty().fontFamilyMode, AppFont.modeSystem);
      expect(
        AppSettings.fromJson(<String, dynamic>{}).fontFamilyMode,
        AppFont.modeSystem,
      );
    });

    test('主题确实按设置挑字体族（静态守护：不许再硬编码内置字体）', () {
      final String main = File('lib/main.dart').readAsStringSync();
      expect(
        main.contains(
          'AppFont.familyFor(widget.controller.settings.fontFamilyMode)',
        ),
        isTrue,
        reason: '主题字体必须由 settings.fontFamilyMode 决定',
      );
      expect(
        RegExp(r'fontFamily:\s*AppFont\.family\b').hasMatch(main),
        isFalse,
        reason: '不应再把内置字体写死在主题里',
      );
    });

    testWidgets('切换字体后立刻生效并落盘', (WidgetTester tester) async {
      final AppController c = await boot(<String, Object>{});
      expect(c.settings.fontFamilyMode, AppFont.modeSystem);

      await c.saveFontFamilyMode(AppFont.modeSourceHan);
      expect(c.settings.fontFamilyMode, AppFont.modeSourceHan);

      final AppSettings reloaded = await SettingsService().load();
      expect(reloaded.fontFamilyMode, AppFont.modeSourceHan);
    });
  });

  group('聊天输入栏样式', () {
    test('默认是胶囊样式', () {
      expect(AppSettings.empty().chatInputStyle, 'capsule');
      expect(
        AppSettings.fromJson(<String, dynamic>{}).chatInputStyle,
        'capsule',
      );
    });

    testWidgets('胶囊样式：输入框无边框，整条是 999 圆角容器',
        (WidgetTester tester) async {
      final AppController c = await boot(<String, Object>{});
      await tester.pumpWidget(hostBar(c, tester));
      await tester.pump();

      expect(effectiveDecoration(tester).border, InputBorder.none);
      expect(hasPillContainer(tester), isTrue);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing,
          reason: '空输入时显示的是灵感按钮，不是发送键');
    });

    testWidgets('旧样式：回到 0.2.0 的下划线输入框（无填充、无描边框），按钮在框外',
        (WidgetTester tester) async {
      final AppController c = await boot(<String, Object>{
        'chat_input_style': 'classic',
      });
      await tester.pumpWidget(hostBar(c, tester));
      await tester.pump();

      final InputDecoration decoration = effectiveDecoration(tester);
      // 不填充、不指定 border ⇒ 由 Flutter 的默认输入框兜底（下划线）。
      expect(decoration.filled, isFalse);
      expect(decoration.border, isNull);
      expect(decoration.isDense ?? false, isFalse);
      expect(hasPillContainer(tester), isFalse, reason: '旧样式没有胶囊容器');
    });

    testWidgets('旧样式下发送键照常工作（输入后出现发送图标，点击真的发送）',
        (WidgetTester tester) async {
      final AppController c = await boot(<String, Object>{
        'chat_input_style': 'classic',
      });
      await tester.pumpWidget(hostBar(c, tester));
      await tester.pump();

      expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);

      await tester.enterText(find.byType(TextField), '你好');
      await tester.pump();
      expect(find.byIcon(Icons.send), findsOneWidget);

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      expect(sent, 1);
    });

    testWidgets('胶囊样式下发送键仍是原来的实心圆钮', (WidgetTester tester) async {
      final AppController c = await boot(<String, Object>{});
      await tester.pumpWidget(hostBar(c, tester));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '你好');
      await tester.pump();
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.send), findsNothing);
    });
  });
}

int sent = 0;

/// 用真实主题（含 app 的 inputDecorationTheme）承载输入栏。
Widget hostBar(AppController controller, WidgetTester tester) {
  sent = 0;
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.seed),
      useMaterial3: true,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(borderRadius: AppRadius.smAll),
      ),
    ),
    home: Scaffold(
      body: Column(
        children: <Widget>[
          const Spacer(),
          ChatInputBar(
            controller: controller,
            inputController: TextEditingController(),
            inputFocusNode: FocusNode(),
            sending: false,
            inspirationInProgress: false,
            onSend: () => sent++,
            onStartInspiration: () async {},
          ),
        ],
      ),
    ),
  );
}

/// 输入框**实际生效**的 decoration：TextField 会把主题的
/// `inputDecorationTheme` 合并进去再交给 InputDecorator，
/// 所以这里读 InputDecorator 上那份（胶囊/旧样式的差异全在里面）。
InputDecoration effectiveDecoration(WidgetTester tester) =>
    tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;

/// 是否渲染了「胶囊」容器（999 圆角 = 输入岛）。
bool hasPillContainer(WidgetTester tester) {
  for (final Container c in tester.widgetList<Container>(
    find.byType(Container),
  )) {
    final Decoration? d = c.decoration;
    if (d is! BoxDecoration) continue;
    final BorderRadiusGeometry? r = d.borderRadius;
    if (r is BorderRadius && r.topLeft.x >= 999) return true;
  }
  return false;
}

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
