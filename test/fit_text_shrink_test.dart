import 'package:dna/widgets/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `FitText` 的「短文本缩放下限」（minShrink）契约。
///
/// 背景：6 字以内的文本会被套 FittedBox 强制单行，空间不足时会缩小；
/// 于是字号调大后，固定宽度容器里的短标签「长到装不下为止」——看起来像
/// 系统字号设置失效。
///
/// **当前契约：默认仍是 0（旧行为）**。一次性把全局默认改成 0.85 会让
/// 800+ 处调用一起变布局，实测会导致多处 RenderFlex 溢出（见
/// docs/MATERIAL_DESIGN_AUDIT.md 4.3 与修复进度）。开关保留：
/// `FitText.recommendedMinShrink`（0.85），逐处修完溢出点后再默认打开。
const TextStyle kStyle = TextStyle(fontSize: 14);

Widget _host(double width, Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  testWidgets('默认（0）：窄容器里仍缩字保单行 —— 旧行为未变', (WidgetTester tester) async {
    await tester.pumpWidget(_host(40, const FitText('测试四个字', style: kStyle)));
    await tester.pump();

    expect(find.byType(FittedBox), findsOneWidget);
    final double h = tester.getSize(find.byType(FittedBox)).height;
    expect(h, lessThan(14 * 2), reason: '单行高度');
  });

  testWidgets('传 recommendedMinShrink：窄容器里不压字，改为换行', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        40,
        const FitText(
          '测试四个字',
          style: kStyle,
          minShrink: FitText.recommendedMinShrink,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FittedBox), findsNothing, reason: '不应再把短标签压小');
    final double h = tester.getSize(find.byType(Text).first).height;
    expect(h, greaterThan(14 * 1.4), reason: '应换成多行');
  });

  testWidgets('传 recommendedMinShrink：宽容器里照旧走 FittedBox', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        400,
        const FitText(
          '完成',
          style: kStyle,
          minShrink: FitText.recommendedMinShrink,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('显式 minShrink: 0 与默认一致（逃生阀语义）', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(40, const FitText('测试四个字', style: kStyle, minShrink: 0)),
    );
    await tester.pump();

    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('minShrink: 0.9：缩得太狠时改为不缩、允许换行', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(40, const FitText('测试四个字', style: kStyle, minShrink: 0.9)),
    );
    await tester.pump();

    expect(find.byType(FittedBox), findsNothing, reason: '不能再压字');
    final double h = tester.getSize(find.byType(Text).first).height;
    expect(h, greaterThan(14 * 1.4));
  });

  group('大字号下的行为（默认不跟随）', () {
    Widget scaled(double scale, Widget child) => MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: _host(40, child),
    );

    testWidgets('默认（0）：即使大字号也保持历史行为——缩字保单行', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(scaled(1.6, const FitText('测试四个字', style: kStyle)));
      await tester.pump();
      // 2026-10-29 的决定：短标签缩字是「字号全局生效」之外的例外，
      // 默认仍缩到装下为止；不要按字号倍率自动改成换行。
      expect(find.byType(FittedBox), findsOneWidget);
    });

    testWidgets('显式传 minShrink：大字号下改为换行', (WidgetTester tester) async {
      await tester.pumpWidget(
        scaled(
          1.6,
          const FitText(
            '测试四个字',
            style: kStyle,
            minShrink: FitText.recommendedMinShrink,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(FittedBox), findsNothing, reason: '这一处明确要求不压字');
      final double h = tester.getSize(find.byType(Text).first).height;
      expect(h, greaterThan(14 * 1.4));
    });

    testWidgets('定宽布局里传 minShrink 时可用 wrapWhenTooNarrow 退回缩字', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        scaled(
          1.6,
          const FitText(
            '测试四个字',
            style: kStyle,
            minShrink: FitText.recommendedMinShrink,
            wrapWhenTooNarrow: false,
          ),
        ),
      );
      await tester.pump();
      // SegmentedButton 这类按固有宽度排版的容器查 intrinsic，
      // 换行分支内部是 LayoutBuilder，会抛断言 ⇒ 只能缩字。
      expect(find.byType(FittedBox), findsOneWidget);
    });
  });
}
