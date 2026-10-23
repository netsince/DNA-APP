import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/widgets/tag_input.dart';

/// 共用标签输入：角色卡与世界卡的四个编辑器都用它。
///
/// 守三件事：回车/逗号落成 chip、点 × 移除、点热门标签直接加。
class _Host extends StatefulWidget {
  const _Host({this.suggestions = const <String>[]});

  final List<String> suggestions;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  List<String> tags = <String>['已有'];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TagInput(
            tags: tags,
            suggestions: widget.suggestions,
            onChanged: (List<String> next) => setState(() => tags = next),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('回车添加标签', (WidgetTester tester) async {
    await tester.pumpWidget(const _Host());
    await tester.enterText(find.byType(TextField), '奇幻');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('奇幻'), findsOneWidget);
  });

  testWidgets('逗号直接落成标签', (WidgetTester tester) async {
    await tester.pumpWidget(const _Host());
    await tester.enterText(find.byType(TextField), '科幻,');
    await tester.pumpAndSettle();
    expect(find.text('科幻'), findsOneWidget);
    // 输入框被清空，标签落到 chips 里
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });

  testWidgets('点 × 移除标签', (WidgetTester tester) async {
    await tester.pumpWidget(const _Host());
    expect(find.text('已有'), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.widgetWithText(InputChip, '已有'),
      matching: find.byIcon(Icons.close),
    ));
    await tester.pumpAndSettle();
    expect(find.text('已有'), findsNothing);
  });

  testWidgets('点热门标签直接加，已存在的不再出现', (WidgetTester tester) async {
    await tester.pumpWidget(const _Host(suggestions: <String>['废土', '已有']));
    await tester.pumpAndSettle();
    // 「已有」已在 chips 里，不该再出现在候选里
    expect(find.widgetWithText(ActionChip, '已有'), findsNothing);
    await tester.tap(find.widgetWithText(ActionChip, '废土'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '废土'), findsOneWidget);
    // 加过之后候选里也不再出现
    expect(find.widgetWithText(ActionChip, '废土'), findsNothing);
  });
}
