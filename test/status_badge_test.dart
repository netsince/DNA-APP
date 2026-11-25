import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/widgets/status_badge.dart';
import 'package:dna/theme/tokens.dart';

/// `StatusBadge` 的两条不变量（审计 3.3「小标签五套实现」的收口点）。
///
/// 1. **它是只读指示，不是控件**：不能出现 InkWell / 手势 / onTap。
///    五套旧实现各自长得像 chip，用户一直去点那些其实点不动的东西。
/// 2. **色调只有五档、都由 ColorScheme 角色决定**：不允许调用方塞 raw color，
///    否则又会裂回「各自调色」。
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('只读：不包任何可点击/手势组件', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const StatusBadge(label: '置顶')));

    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byType(InkResponse), findsNothing);
  });

  testWidgets('五档色调各自解析到 ColorScheme 角色', (WidgetTester tester) async {
    for (final BadgeTone tone in BadgeTone.values) {
      await tester.pumpWidget(_host(StatusBadge(label: 'x', tone: tone)));
      final BuildContext ctx = tester.element(find.byType(StatusBadge));
      final ColorScheme cs = Theme.of(ctx).colorScheme;
      final Container box = tester.widget<Container>(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.byType(Container),
        ).first,
      );
      final Color bg = (box.decoration! as BoxDecoration).color!;

      final Color expected = switch (tone) {
        BadgeTone.neutral => cs.surfaceContainerHighest,
        BadgeTone.positive => cs.primaryContainer,
        BadgeTone.caution => cs.tertiaryContainer,
        BadgeTone.danger => cs.errorContainer,
        BadgeTone.info => cs.secondaryContainer,
      };
      expect(bg, expected, reason: 'tone = $tone');
    }
  });

  testWidgets('文案原样显示，且不会被 FittedBox 缩字', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const StatusBadge(label: '已通过')));
    expect(find.text('已通过'), findsOneWidget);
    // 徽章用裸 Text 而不是 FitText：短标签在大字号下不该被压回去。
    expect(find.byType(FittedBox), findsNothing);
  });

  testWidgets('图标是颜色之外的第二通道', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(const StatusBadge(label: '已拒绝', icon: Icons.error_outline)),
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('读屏只念一句（label 或 semanticLabel）', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const StatusBadge(
          label: '已通过',
          icon: Icons.check_circle,
          semanticLabel: '审核状态：已通过',
        ),
      ),
    );
    final SemanticsHandle handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('审核状态：已通过'),
      findsOneWidget,
      reason: '图标与文案不该被拆成两段读出来',
    );
    handle.dispose();
  });

  test('尺寸令牌：徽章高度远小于 48dp（它不可点，不需要命中区）', () {
    expect(AppSpacing.sm, lessThan(AppSize.touchTarget));
  });
}
