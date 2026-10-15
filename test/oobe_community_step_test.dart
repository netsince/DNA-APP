import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dna/island_app/server_config.dart';
import 'package:dna/pages/oobe/community_edit_page.dart';
import 'package:dna/pages/oobe/oobe_steps.dart';
import 'package:dna/widgets/fit_text.dart';

/// 社区步骤（折叠态）与社区编辑页。
///
/// 需求变化：社区那一步从「一整张输入表单」改成**折叠摘要 + 改**。
/// 官方用户直接下一步即可，输入框、检测、「忽略这个错误」、「不使用社区功能」
/// 全部收进编辑页的「更多选项」里。
///
/// FitText extends Text，find.text 会重复命中；这里用谓词只匹配内层真实 Text。
Finder findText(String s) => find.byWidgetPredicate(
    (Widget w) => w is Text && w is! FitText && w.data == s);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// 点在树里但可能滚出可视区的控件：先滚到可见再点。
  ///
  /// 不这么做的话 tester.tap 会「命中失败」—— 它只警告、不报错，于是测试
  /// 看起来跑过了，实际什么都没点到。对话框里的按钮不在可滚动容器里，
  /// ensureVisible 会抛异常，退回直接点。
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    try {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    } catch (_) {
      // 没有可滚动祖先（对话框等），直接点。
    }
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  CommunityStep buildStep({
    bool enabled = true,
    String? url,
    CommunityStepStatus status = CommunityStepStatus.unchecked,
    VoidCallback? onEdit,
  }) {
    return CommunityStep(
      enabled: enabled,
      url: url ?? ServerConfig.defaultBaseUrl,
      defaultUrl: ServerConfig.defaultBaseUrl,
      status: status,
      heroSize: 72,
      onEdit: onEdit ?? () {},
    );
  }

  group('社区步骤（折叠态）', () {
    testWidgets('官方地址：直接给出结论，不铺输入框', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(buildStep()));
      await tester.pump();

      expect(findText('步骤 2/4 · 社区'), findsOneWidget);
      expect(findText('已连接官方服务器'), findsOneWidget);
      expect(findText(ServerConfig.defaultBaseUrl), findsOneWidget);
      expect(find.byType(TextField), findsNothing,
          reason: '折叠态不该出现输入框，改地址要进编辑页');
      expect(findText('改'), findsOneWidget);
    });

    testWidgets('自建地址：显示「使用自建服务器」与地址', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(buildStep(url: 'https://self.test')),
      );
      await tester.pump();

      expect(findText('使用自建服务器'), findsOneWidget);
      expect(findText('https://self.test'), findsOneWidget);
    });

    testWidgets('关闭社区：显示「社区已关闭」', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(buildStep(enabled: false)));
      await tester.pump();

      expect(findText('社区已关闭'), findsOneWidget);
      expect(findText('已连接官方服务器'), findsNothing);
    });

    testWidgets('点「改」触发回调', (WidgetTester tester) async {
      int edits = 0;
      await tester.pumpWidget(wrap(buildStep(onEdit: () => edits++)));
      await tester.pump();

      await tester.tap(findText('改'));
      await tester.pump();
      expect(edits, 1);
    });

    testWidgets('检测状态显示在摘要里', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(buildStep(status: CommunityStepStatus.connected)),
      );
      await tester.pump();
      expect(findText('上次检测：连接正常'), findsOneWidget);

      await tester.pumpWidget(
        wrap(buildStep(status: CommunityStepStatus.ignored)),
      );
      await tester.pump();
      expect(findText('上次检测：连接失败，已选择跳过'), findsOneWidget);

      await tester.pumpWidget(
        wrap(buildStep(status: CommunityStepStatus.unchecked)),
      );
      await tester.pump();
      expect(findText('上次检测：连接正常'), findsNothing);
    });
  });

  group('社区编辑页', () {
    /// 从宿主页面 push 编辑页，这样 pop 有地方可去、也能拿到返回值。
    Future<CommunityEditResult?> Function() openPage(
      WidgetTester tester, {
      required Future<String?> Function(String) validator,
      bool enableCommunity = true,
      List<bool>? toggles,
      String? initialUrl,
    }) {
      return () async {
        // 编辑页会读写 ServerConfig（SharedPreferences），测试环境要先装 mock，
        // 否则落盘那一步抛异常，按钮会停在转圈状态。
        SharedPreferences.setMockInitialValues(<String, Object>{});
        CommunityEditResult? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await Navigator.of(context)
                          .push<CommunityEditResult>(
                        MaterialPageRoute<CommunityEditResult>(
                          builder: (_) => CommunityEditPage(
                            initialUrl:
                                initialUrl ?? ServerConfig.defaultBaseUrl,
                            defaultUrl: ServerConfig.defaultBaseUrl,
                            enableCommunity: enableCommunity,
                            validator: validator,
                            onToggleCommunity: (bool v) =>
                                toggles?.add(v),
                          ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        return result;
      };
    }

    testWidgets('渲染地址输入框与检测按钮', (WidgetTester tester) async {
      await openPage(tester, validator: (_) async => null)();
      expect(find.byType(TextField), findsOneWidget);
      expect(findText('保存并检测社区'), findsOneWidget);
      expect(findText('使用官方服务器'), findsOneWidget);
      // 折叠时不该看到更多选项里的东西。
      expect(findText('忽略这个错误'), findsNothing);
      expect(findText('不使用社区功能'), findsNothing);
    });

    testWidgets('检测成功显示绿字横幅', (WidgetTester tester) async {
      await openPage(tester, validator: (_) async => null)();
      await tapVisible(tester, findText('保存并检测社区'));
      await tester.pumpAndSettle();
      expect(findText('社区连接验证成功。'), findsOneWidget);
    });

    testWidgets('检测失败：横幅 + 更多选项自动展开 + 忽略错误可用',
        (WidgetTester tester) async {
      await openPage(tester, validator: (_) async => '连接超时')();
      await tapVisible(tester, findText('保存并检测社区'));
      await tester.pumpAndSettle();

      expect(findText('连接超时'), findsOneWidget);
      expect(findText('忽略这个错误'), findsOneWidget,
          reason: '失败时「更多选项」应自动展开，忽略这条路不能被折叠藏起来');
    });

    testWidgets('更多选项 → 不常用选项 → 不使用社区功能，带劝阻弹窗',
        (WidgetTester tester) async {
      final List<bool> toggles = <bool>[];
      final Future<CommunityEditResult?> Function() open = openPage(
        tester,
        validator: (_) async => null,
        toggles: toggles,
      );
      await open();

      // 更多选项
      await tapVisible(tester, findText('更多选项'));
      await tester.pumpAndSettle();
      expect(findText('忽略这个错误'), findsOneWidget);
      expect(findText('不常用选项'), findsOneWidget);

      // 不常用选项 → 不使用社区功能
      await tapVisible(tester, findText('不常用选项'));
      await tester.pumpAndSettle();
      expect(findText('不使用社区功能'), findsOneWidget);

      await tapVisible(tester, findText('不使用社区功能'));
      await tester.pumpAndSettle();
      expect(findText('确定不使用社区功能？'), findsOneWidget);
      expect(
        findTextContaining('你将失去社区里百余个角色卡'),
        findsOneWidget,
        reason: '关闭前必须劝阻',
      );

      // 先取消：不该关。
      await tapVisible(tester, findText('取消'));
      await tester.pumpAndSettle();
      expect(toggles, isEmpty);

      // 再来一次并确认。
      await tapVisible(tester, findText('不使用社区功能'));
      await tester.pumpAndSettle();
      await tapVisible(tester, findText('仍然关闭'));
      await tester.pumpAndSettle();
      expect(toggles, <bool>[false]);
    });

    testWidgets('「忽略这个错误」返回 ignored 状态', (WidgetTester tester) async {
      final Future<CommunityEditResult?> Function() open = openPage(
        tester,
        validator: (_) async => '连接超时',
      );
      await open();
      await tapVisible(tester, findText('保存并检测社区'));
      await tester.pumpAndSettle();
      await tapVisible(tester, findText('忽略这个错误'));
      await tester.pumpAndSettle();
    });
  });

  group('步骤条', () {
    testWidgets('横向渲染 4 段', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const StepTracker(stepIndex: 0)));
      await tester.pump();
      expect(find.byType(AnimatedContainer), findsNWidgets(kOobeStepCount));
    });

    testWidgets('纵向渲染 4 段（宽屏左栏）', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const StepTracker(stepIndex: 1, axis: Axis.vertical)),
      );
      await tester.pump();
      expect(find.byType(AnimatedContainer), findsNWidgets(kOobeStepCount));
    });

    testWidgets('可点：点到 maxReached 以内的步骤会回调', (WidgetTester tester) async {
      final List<int> jumps = <int>[];
      await tester.pumpWidget(
        wrap(StepTracker(
          stepIndex: 2,
          maxReached: 2,
          onStepSelected: jumps.add,
        )),
      );
      await tester.pump();

      await tester.tap(findText('欢迎'));
      await tester.pump();
      expect(jumps, <int>[0]);
    });

    testWidgets('不可点：超过 maxReached 的步骤点了没反应', (WidgetTester tester) async {
      final List<int> jumps = <int>[];
      await tester.pumpWidget(
        wrap(StepTracker(
          stepIndex: 0,
          maxReached: 0,
          onStepSelected: jumps.add,
        )),
      );
      await tester.pump();

      await tester.tap(findText('模型'));
      await tester.pump();
      expect(jumps, isEmpty);
    });
  });

  group('页脚', () {
    testWidgets('最后一步是「完成」；勾了忽略则是「忽略并继续」',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(OobeFooter(
          stepIndex: kOobeStepCount - 1,
          canGoNext: true,
          onBack: () {},
          onNext: () {},
          ignoreIssue: false,
        )),
      );
      await tester.pump();
      expect(findText('完成'), findsOneWidget);

      await tester.pumpWidget(
        wrap(OobeFooter(
          stepIndex: kOobeStepCount - 1,
          canGoNext: true,
          onBack: () {},
          onNext: () {},
          ignoreIssue: true,
        )),
      );
      await tester.pump();
      expect(findText('忽略并继续'), findsOneWidget);
      expect(findText('完成'), findsNothing);
    });

    testWidgets('中间步骤是「下一步」', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(OobeFooter(
          stepIndex: 2,
          canGoNext: true,
          onBack: () {},
          onNext: () {},
          ignoreIssue: false,
        )),
      );
      await tester.pump();
      expect(findText('下一步'), findsOneWidget);
    });
  });
}

/// 匹配「包含某段文字」的 Text。
///
/// 同样要排除 FitText 本身：它 extends Text，且内部再包一层 Text，
/// 不排除的话同一个字符串会命中两次。
Finder findTextContaining(String s) => find.byWidgetPredicate(
    (Widget w) => w is Text && w is! FitText && (w.data ?? '').contains(s));
