import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/oobe/oobe_steps.dart';
import 'package:dna/pages/oobe/step_hero.dart';
import 'package:dna/pages/oobe_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/brand_icon.dart';
import 'package:dna/widgets/fit_text.dart';

/// OOBE 的**渲染契约测试**。
///
/// 存在的理由和 test/ai_service_page_render_test.dart 一样：「AI 服务」页曾经被
/// 拆坏过一次 —— 子组件收下控制器却从不用，精简模式渲染出来一个输入框都没有，
/// 而 flutter analyze 干净、行数正常。静态手段查不出来。
///
/// OOBE 是首次体验的唯一入口，更不该出现「某个控件悄悄没了」。这里逐个步骤把
/// 控件渲染出来断言存在。
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

/// FitText extends Text，find.text 会重复命中；只匹配内层真实 Text。
Finder findText(String s) => find.byWidgetPredicate(
    (Widget w) => w is Text && w is! FitText && w.data == s);

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

  Future<void> pumpStep(WidgetTester t, Widget child) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await t.pumpAndSettle();
  }

  group('API 步骤', () {
    testWidgets('Base URL / API Key 输入框、服务商 Chip、检测按钮必须存在',
        (WidgetTester tester) async {
      final AppController c = await boot();
      final TextEditingController base = TextEditingController();
      final TextEditingController key = TextEditingController();
      addTearDown(base.dispose);
      addTearDown(key.dispose);

      await pumpStep(
        tester,
        ApiStep(
          providers: c.llmProviders,
          selectedProviderId: c.settings.provider,
          baseUrlController: base,
          apiKeyController: key,
          baseUrlHint: c.llmProvider.defaultBaseUrl,
          requiresApiKey: true,
          heroSize: 72,
          checkingApi: false,
          apiValidated: false,
          apiError: null,
          ignoreApiIssue: false,
          onProviderChanged: (_) {},
          onIgnoreChanged: (_) {},
          onCheck: () {},
          onInputChanged: () {},
        ),
      );

      expect(findText('步骤 3/4 · API 配置'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2),
          reason: 'Base URL + API Key，少一个就是拆分事故重演');
      expect(find.byType(ChoiceChip), findsNWidgets(c.llmProviders.length));
      expect(findText('保存并检测 API'), findsOneWidget);
    });

    testWidgets('服务商不需要 Key 时不渲染 Key 输入框，也不再要求填',
        (WidgetTester tester) async {
      final AppController c = await boot();
      final TextEditingController base = TextEditingController();
      final TextEditingController key = TextEditingController();
      addTearDown(base.dispose);
      addTearDown(key.dispose);

      await pumpStep(
        tester,
        ApiStep(
          providers: c.llmProviders,
          selectedProviderId: c.settings.provider,
          baseUrlController: base,
          apiKeyController: key,
          baseUrlHint: c.llmProvider.defaultBaseUrl,
          requiresApiKey: false,
          heroSize: 72,
          checkingApi: false,
          apiValidated: false,
          apiError: null,
          ignoreApiIssue: false,
          onProviderChanged: (_) {},
          onIgnoreChanged: (_) {},
          onCheck: () {},
          onInputChanged: () {},
        ),
      );

      expect(find.byType(TextField), findsOneWidget, reason: '只留 Base URL');
      expect(findText('这个服务商不需要 API Key。'), findsOneWidget);
    });

    testWidgets('Base URL 锁定的服务商不渲染该输入框', (WidgetTester tester) async {
      final AppController c = await boot();
      final TextEditingController base = TextEditingController();
      final TextEditingController key = TextEditingController();
      addTearDown(base.dispose);
      addTearDown(key.dispose);

      await pumpStep(
        tester,
        ApiStep(
          providers: c.llmProviders,
          selectedProviderId: c.settings.provider,
          baseUrlController: base,
          apiKeyController: key,
          baseUrlHint: c.llmProvider.defaultBaseUrl,
          requiresApiKey: true,
          hideBaseUrl: true,
          heroSize: 72,
          checkingApi: false,
          apiValidated: false,
          apiError: null,
          ignoreApiIssue: false,
          onProviderChanged: (_) {},
          onIgnoreChanged: (_) {},
          onCheck: () {},
          onInputChanged: () {},
        ),
      );

      expect(find.byType(TextField), findsOneWidget, reason: '只留 API Key');
    });
  });

  group('步骤英雄位', () {
    Future<void> pumpHero(WidgetTester tester, Widget hero,
        {bool disableAnimations = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: disableAnimations),
              child: Scaffold(body: Center(child: hero)),
            ),
          ),
        ),
      );
    }

    double heroOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byType(StepHero),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    testWidgets('没有服务商时画步骤图标', (WidgetTester tester) async {
      await pumpHero(
        tester,
        const StepHero(stepIndex: 1, icon: Icons.public_outlined, size: 72),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.public_outlined), findsOneWidget);
    });

    testWidgets('传了服务商就画真实品牌标，而不是通用图标',
        (WidgetTester tester) async {
      await pumpHero(
        tester,
        const StepHero(
          stepIndex: 2,
          icon: Icons.key_outlined,
          size: 72,
          providerId: 'deepseek',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BrandIcon), findsOneWidget);
      expect(find.byIcon(Icons.key_outlined), findsNothing);
    });

    testWidgets('入场动画会跑完，而且能静止（不是常驻循环）',
        (WidgetTester tester) async {
      await pumpHero(
        tester,
        const StepHero(
          stepIndex: 2,
          icon: Icons.key_outlined,
          size: 72,
          providerId: 'openai',
        ),
      );
      // 刚进来时进度还没走完。
      expect(heroOpacity(tester), lessThan(1));
      // pumpAndSettle 能结束 —— 常驻动画会在这里超时，这条就是那道闸门。
      await tester.pumpAndSettle();
      expect(heroOpacity(tester), 1);
    });

    testWidgets('系统要求减少动态效果时直接给终态', (WidgetTester tester) async {
      await pumpHero(
        tester,
        const StepHero(
          stepIndex: 2,
          icon: Icons.key_outlined,
          size: 72,
          providerId: 'openai',
        ),
        disableAnimations: true,
      );
      await tester.pump();
      expect(heroOpacity(tester), 1);
    });
  });

  group('模型步骤', () {
    testWidgets('刷新 / 自定义按钮与空态必须存在', (WidgetTester tester) async {
      await pumpStep(
        tester,
        ModelStep(
          loadingModels: false,
          models: const <String>[],
          modelsError: null,
          selectedModel: null,
          onReload: () {},
          onSelect: (_) {},
          onCustom: () {},
          heroSize: 72,
        ),
      );

      expect(findText('步骤 4/4 · 模型选择'), findsOneWidget);
      expect(findText('刷新模型列表'), findsOneWidget);
      expect(findText('自定义模型'), findsOneWidget);
      expect(findText('暂无可用模型'), findsOneWidget);
    });

    testWidgets('有模型时渲染可点列表', (WidgetTester tester) async {
      await pumpStep(
        tester,
        ModelStep(
          loadingModels: false,
          models: const <String>['gpt-4.1', 'gpt-4.1-mini'],
          modelsError: null,
          selectedModel: 'gpt-4.1',
          onReload: () {},
          onSelect: (_) {},
          onCustom: () {},
          heroSize: 72,
        ),
      );

      expect(findText('gpt-4.1'), findsOneWidget);
      expect(findText('gpt-4.1-mini'), findsOneWidget);
    });
  });

  group('整页流程', () {
    testWidgets('欢迎页：品牌标题 + 步骤条 + 先看看 + 跳过',
        (WidgetTester tester) async {
      final AppController c = await boot();
      await tester.pumpWidget(MaterialApp(home: OobePage(controller: c)));
      await tester.pumpAndSettle();

      expect(findText('与汝共奏'), findsOneWidget);
      expect(find.byType(StepTracker), findsOneWidget);
      expect(findText('开始'), findsOneWidget);
      expect(findText('先看看，稍后再配置'), findsOneWidget);
      // 跳过按钮必须在第一步就有，且每一步都在（见下一个用例）。
      expect(findText('跳过'), findsOneWidget);
      expect(findText('上一步'), findsOneWidget);
    });

    testWidgets('社区是第 2 步，且是折叠摘要（没有输入框）',
        (WidgetTester tester) async {
      final AppController c = await boot();
      await tester.pumpWidget(MaterialApp(home: OobePage(controller: c)));
      await tester.pumpAndSettle();

      await tester.tap(findText('开始'));
      await tester.pumpAndSettle();

      expect(findText('步骤 2/4 · 社区'), findsOneWidget);
      expect(findText('已连接官方服务器'), findsOneWidget);
      expect(findText('改'), findsOneWidget);
      expect(find.byType(TextField), findsNothing,
          reason: '社区步骤折叠态不该有输入框');
      // 跳过按钮在第二步依然在。
      expect(findText('跳过'), findsOneWidget);
      expect(findText('下一步'), findsOneWidget);
    });

    testWidgets('「先看看」直接完成引导（不弹劝阻框）', (WidgetTester tester) async {
      final AppController c = await boot();
      expect(c.settings.completedOobe, isFalse);

      await tester.pumpWidget(MaterialApp(home: OobePage(controller: c)));
      await tester.pumpAndSettle();

      // 「先看看」在欢迎卡片的底部，800x600 的测试视口里要滚动才可见；
      // 不先滚过去，tap 会「命中失败」—— 只警告不报错，测试会假装通过。
      await tester.ensureVisible(findText('先看看，稍后再配置'));
      await tester.pumpAndSettle();
      await tester.tap(findText('先看看，稍后再配置'));
      await tester.pumpAndSettle();

      expect(c.settings.completedOobe, isTrue);
      expect(find.byType(AlertDialog), findsNothing,
          reason: '「先看看」是主动选择，不该再弹劝阻框');
    });

    testWidgets('「跳过」要二次确认', (WidgetTester tester) async {
      final AppController c = await boot();
      await tester.pumpWidget(MaterialApp(home: OobePage(controller: c)));
      await tester.pumpAndSettle();

      await tester.tap(findText('跳过'));
      await tester.pumpAndSettle();
      expect(findText('跳过引导？'), findsOneWidget);

      await tester.tap(findText('继续设置'));
      await tester.pumpAndSettle();
      expect(c.settings.completedOobe, isFalse);
    });
  });
}
