import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_collapsible.dart';
import 'package:dna/widgets/setting_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 折叠组件的**运行时**行为测试。
///
/// 此前这类改造只做过静态分析(正则数数),没有真正渲染过 ——
/// 本文件补上运行时验证:收起/展开、值显示、clamp、回调。
/// `FitText extends Text`,所以 `find.text` / `w is Text` 会把
/// FitText 与其内部构造的 Text **同时**匹配到(同一字符串命中两次)。
/// 这里排除 FitText 本身,只匹配它内部那个真实的 Text。
Finder findText(String s) => find.byWidgetPredicate(
    (Widget w) => w is Text && w is! FitText && w.data == s);

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.seed),
          useMaterial3: true,
          fontFamily: AppFont.family,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('CollapsibleNumberSetting 运行时行为', () {
    testWidgets('初始为收起态:只显示名称与当前值,不渲染滑块', (WidgetTester t) async {
      await t.pumpWidget(host(CollapsibleNumberSetting(
        title: '按对话轮数触发',
        value: 200,
        min: 10,
        max: 1000,
        unit: '轮',
        onChanged: (_) {},
      )));

      expect(findText('按对话轮数触发'), findsOneWidget);
      expect(findText('200 轮'), findsOneWidget);
      // 收起态控件不在树中(AnimatedCrossFade 的 secondChild 未显示)。
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('点击标题行展开后出现滑块', (WidgetTester t) async {
      await t.pumpWidget(host(CollapsibleNumberSetting(
        title: '按对话轮数触发',
        value: 200,
        min: 10,
        max: 1000,
        unit: '轮',
        onChanged: (_) {},
      )));

      await t.tap(findText('按对话轮数触发'));
      await t.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('拖动滑块回调收到 clamp 后的整数值', (WidgetTester t) async {
      final List<int> got = <int>[];
      await t.pumpWidget(host(CollapsibleNumberSetting(
        title: '阈值',
        value: 50,
        min: 0,
        max: 100,
        onChanged: got.add,
      )));

      await t.tap(findText('阈值'));
      await t.pumpAndSettle();

      // 拖到最右端。
      await t.drag(find.byType(Slider), const Offset(500, 0));
      await t.pumpAndSettle();

      expect(got, isNotEmpty);
      expect(got.last, inInclusiveRange(0, 100));
    });

    testWidgets('值为 0 且有 zeroLabel 时显示「不限」而非 0', (WidgetTester t) async {
      await t.pumpWidget(host(CollapsibleNumberSetting(
        title: '字数阈值',
        value: 0,
        min: 0,
        max: 5000,
        unit: '字',
        zeroLabel: '不限',
        onChanged: (_) {},
      )));

      expect(findText('不限'), findsOneWidget);
      expect(findText('0 字'), findsNothing);
    });

    testWidgets('helper 文案只在展开后出现(收起态不占位)', (WidgetTester t) async {
      await t.pumpWidget(host(CollapsibleNumberSetting(
        title: '阈值',
        value: 5,
        min: 0,
        max: 10,
        helper: '计数的是对话轮数,不是消息条数。',
        onChanged: (_) {},
      )));

      expect(findText('计数的是对话轮数,不是消息条数。'), findsNothing);

      await t.tap(findText('阈值'));
      await t.pumpAndSettle();

      expect(findText('计数的是对话轮数,不是消息条数。'), findsOneWidget);
    });
  });

  group('CollapsibleDoubleSetting 运行时行为', () {
    testWidgets('按 decimals 格式化收起态数值', (WidgetTester t) async {
      await t.pumpWidget(host(CollapsibleDoubleSetting(
        title: '温度',
        value: 0.7,
        min: 0,
        max: 2,
        decimals: 2,
        onChanged: (_) {},
      )));

      expect(findText('0.70'), findsOneWidget);
    });

    testWidgets('decimals: 1 时显示一位小数', (WidgetTester t) async {
      await t.pumpWidget(host(CollapsibleDoubleSetting(
        title: '重复惩罚斜率',
        value: 0.5,
        min: 0,
        max: 1,
        decimals: 1,
        onChanged: (_) {},
      )));

      expect(findText('0.5'), findsOneWidget);
    });
  });

  group('SettingSection 运行时结构', () {
    testWidgets('渲染图标/标题/说明/子项', (WidgetTester t) async {
      await t.pumpWidget(host(SettingSection(
        icon: Icons.psychology_outlined,
        title: '剧情摘要',
        description: '对话变长后让 AI 记住前文。',
        children: <Widget>[
          SettingSwitch(
            title: '自动生成摘要',
            value: true,
            onChanged: (_) {},
          ),
        ],
      )));

      expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
      expect(findText('剧情摘要'), findsOneWidget);
      expect(findText('对话变长后让 AI 记住前文。'), findsOneWidget);
      expect(findText('自动生成摘要'), findsOneWidget);
    });

    testWidgets('SettingSwitch.description 渲染在开关右侧同一行', (WidgetTester t) async {
      await t.pumpWidget(host(SettingSection(
        icon: Icons.tune,
        title: '分组',
        children: <Widget>[
          SettingSwitch(
            title: '括号快捷键',
            description: '只影响输入栏',
            value: false,
            onChanged: (_) {},
          ),
        ],
      )));

      expect(findText('括号快捷键'), findsOneWidget);
      expect(findText('只影响输入栏'), findsOneWidget);
    });

    testWidgets('SettingSwitch.subtitle 为 null 时不渲染副标题', (WidgetTester t) async {
      await t.pumpWidget(host(const SettingSection(
        icon: Icons.tune,
        title: '分组',
        children: <Widget>[
          SettingSwitch(title: '仅标题', value: false, onChanged: null),
        ],
      )));

      expect(findText('仅标题'), findsOneWidget);
      // SwitchListTile 只有一个文本子节点。
      expect(find.byType(SwitchListTile), findsOneWidget);
    });
  });
}
