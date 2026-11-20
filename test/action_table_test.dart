import 'package:dna/utils/action_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 动作表的契约：可见性过滤、危险色、以及「没有可见动作就别渲染菜单」。
void main() {
  testWidgets('行内动作表：不可见的动作不出现，点可见项才触发', (WidgetTester tester) async {
    final List<String> fired = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: rowActionMenu(
            actions: <RowAction>[
              RowAction(id: 'detail', label: '查看详情', onSelected: () => fired.add('detail')),
              RowAction(
                id: 'resubmit',
                label: '重新提审',
                visible: false,
                onSelected: () => fired.add('resubmit'),
              ),
              RowAction(
                id: 'hidden',
                label: '隐藏',
                danger: true,
                onSelected: () => fired.add('hidden'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.text('查看详情'), findsOneWidget);
    expect(find.text('隐藏'), findsOneWidget);
    expect(find.text('重新提审'), findsNothing, reason: 'visible=false 的动作不该出现');

    await tester.tap(find.text('隐藏'));
    await tester.pumpAndSettle();
    expect(fired, <String>['hidden']);
  });

  testWidgets('危险动作用 error 色', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: rowActionMenu(
            actions: <RowAction>[
              RowAction(id: 'del', label: '删除', danger: true, onSelected: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    final BuildContext ctx = tester.element(find.text('删除'));
    final Text text = tester.widget<Text>(find.text('删除'));
    expect(text.style?.color, Theme.of(ctx).colorScheme.error);
  });

  test('hasVisibleRowAction：全不可见时为 false', () {
    expect(
      hasVisibleRowAction(<RowAction>[
        RowAction(id: 'a', label: 'A', visible: false, onSelected: () {}),
      ]),
      isFalse,
    );
    expect(
      hasVisibleRowAction(<RowAction>[
        RowAction(id: 'a', label: 'A', onSelected: () {}),
      ]),
      isTrue,
    );
  });
}
