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

    // FitText 是 Text 的子类，短标签内部还会再套一层 Text，所以用 findsWidgets。
    expect(find.text('查看详情'), findsWidgets);
    expect(find.text('隐藏'), findsWidgets);
    expect(find.text('重新提审'), findsNothing, reason: 'visible=false 的动作不该出现');

    await tester.tap(find.text('隐藏').first);
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

    final BuildContext ctx = tester.element(find.text('删除').first);
    final Iterable<Text> texts = tester.widgetList<Text>(find.text('删除'));
    expect(
      texts.any((Text t) => t.style?.color == Theme.of(ctx).colorScheme.error),
      isTrue,
      reason: '危险动作的文字应为 error 色',
    );
  });

  testWidgets('勾选项渲染成 CheckedPopupMenuItem，带分隔线的项后面有线', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: rowActionMenu(
            itemStyle: RowActionItemStyle.listTile,
            actions: <RowAction>[
              RowAction(
                id: 'bgm',
                label: '背景音乐',
                checked: true,
                icon: Icons.music_note_outlined,
                onSelected: () {},
              ),
              RowAction(
                id: 'export',
                label: '导出对话',
                dividerAfter: true,
                onSelected: () {},
              ),
              RowAction(id: 'archive', label: '存档', onSelected: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.byType(CheckedPopupMenuItem<String>), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    expect(find.text('导出对话'), findsWidgets);
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
