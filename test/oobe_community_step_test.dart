import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/server_config.dart';
import 'package:dna/pages/oobe/oobe_steps.dart';

/// 主引导（OOBE）里的「社区」步骤。
///
/// 需求：社区原先有自己的服务器地址设置页（装完 App 还得再进社区配一次），现在并入主
/// 引导 —— 默认值与社区内一致（官方地址），连不上可以勾「忽略此问题」继续，与 API Key
/// 那一步同一套交互。
///
/// 注意：本仓库的 `FitText` 是 `Text` 的子类且内含一层 `Text`，所以同一段文案会被
/// `find.text` 匹配到两次 —— 断言用 `findsWidgets`，点击用 `.first`。
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  CommunityStep buildStep({
    required TextEditingController controller,
    bool checking = false,
    bool validated = false,
    String? error,
    bool ignoreIssue = false,
    VoidCallback? onCheck,
    VoidCallback? onUseDefault,
    ValueChanged<bool>? onIgnoreChanged,
    VoidCallback? onInputChanged,
  }) {
    return CommunityStep(
      urlController: controller,
      defaultUrl: ServerConfig.defaultBaseUrl,
      checking: checking,
      validated: validated,
      error: error,
      ignoreIssue: ignoreIssue,
      onIgnoreChanged: onIgnoreChanged ?? (_) {},
      onCheck: onCheck ?? () {},
      onInputChanged: onInputChanged ?? () {},
      onUseDefault: onUseDefault ?? () {},
    );
  }

  testWidgets('是第 4 步，且默认预填官方社区地址', (WidgetTester tester) async {
    final controller = TextEditingController(text: ServerConfig.defaultBaseUrl);
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrap(buildStep(controller: controller)));
    await tester.pump();

    expect(find.text('步骤 4/4 · 社区'), findsWidgets);
    expect(
      find.text(ServerConfig.defaultBaseUrl),
      findsWidgets,
      reason: '默认值必须与社区内部的「服务器地址」一致（官方地址）',
    );
  });

  testWidgets('检测失败才出现「忽略此问题」；成功时显示绿字', (WidgetTester tester) async {
    final controller = TextEditingController(text: 'https://self.test');
    addTearDown(controller.dispose);

    // 未检测/未出错：没有忽略勾选
    await tester.pumpWidget(wrap(buildStep(controller: controller)));
    await tester.pump();
    expect(find.text('忽略此问题'), findsNothing);

    // 检测成功
    await tester.pumpWidget(
      wrap(buildStep(controller: controller, validated: true)),
    );
    await tester.pump();
    expect(find.text('社区连接验证成功。'), findsWidgets);
    expect(find.text('忽略此问题'), findsNothing);

    // 检测失败：错误文案 + 忽略勾选
    await tester.pumpWidget(
      wrap(buildStep(controller: controller, error: '连接超时')),
    );
    await tester.pump();
    expect(find.text('连接超时'), findsWidgets);
    expect(find.text('忽略此问题'), findsWidgets);
  });

  testWidgets('按钮回调：检测、使用官方地址、勾选忽略', (WidgetTester tester) async {
    final controller = TextEditingController(text: 'https://self.test');
    addTearDown(controller.dispose);
    int checks = 0;
    int defaults = 0;
    bool? ignored;

    await tester.pumpWidget(
      wrap(
        buildStep(
          controller: controller,
          error: '连不上',
          onCheck: () => checks++,
          onUseDefault: () => defaults++,
          onIgnoreChanged: (bool v) => ignored = v,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('保存并检测社区').first);
    await tester.pump();
    expect(checks, 1);

    await tester.tap(find.text('使用官方服务器').first);
    await tester.pump();
    expect(defaults, 1);

    await tester.tap(find.text('忽略此问题').first);
    await tester.pump();
    expect(ignored, isTrue);
  });

  testWidgets('检测中：按钮禁用，文案变成「检测中...」', (WidgetTester tester) async {
    final controller = TextEditingController(text: 'https://self.test');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(buildStep(controller: controller, checking: true)),
    );
    await tester.pump();

    expect(find.text('检测中...'), findsWidgets);
    final FilledButton button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '检测中...').first,
    );
    expect(button.onPressed, isNull, reason: '检测中不应能重复点击');
  });

  group('步骤总数与页脚', () {
    test('引导一共 4 步', () {
      expect(kOobeStepCount, 4);
    });

    testWidgets('进度条渲染 4 段', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const StepTracker(stepIndex: 0)));
      await tester.pump();
      expect(find.byType(AnimatedContainer), findsNWidgets(kOobeStepCount));
    });

    testWidgets('最后一步的页脚是「完成」；勾了忽略则是「忽略并继续」', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          OobeFooter(
            stepIndex: kOobeStepCount - 1,
            canGoNext: true,
            onBack: () {},
            onNext: () {},
            ignoreIssue: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('完成'), findsWidgets);

      await tester.pumpWidget(
        wrap(
          OobeFooter(
            stepIndex: kOobeStepCount - 1,
            canGoNext: true,
            onBack: () {},
            onNext: () {},
            ignoreIssue: true,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('忽略并继续'), findsWidgets);
      expect(find.text('完成'), findsNothing);
    });

    testWidgets('中间步骤仍是「下一步」', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          OobeFooter(
            stepIndex: 2,
            canGoNext: true,
            onBack: () {},
            onNext: () {},
            ignoreIssue: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('下一步'), findsWidgets);
    });
  });
}
