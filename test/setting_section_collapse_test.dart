import 'package:dna/widgets/setting_section.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设置分组的折叠：标题常驻，内容按需展开（渐进式披露的最后一层）。
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  testWidgets('默认展开；点标题收起，再点展开', (WidgetTester tester) async {
    await tester.pumpWidget(host(
      const SettingSection(
        title: '外观',
        description: '明暗与配色',
        children: <Widget>[Text('子项A'), Text('子项B')],
      ),
    ));
    expect(find.text('外观'), findsWidgets);
    expect(find.text('子项A').hitTestable(), findsOneWidget);

    await tester.tap(find.text('外观').first);
    await tester.pumpAndSettle();
    expect(find.text('子项A').hitTestable(), findsNothing, reason: '收起后内容不该可点');
    expect(find.text('外观').hitTestable(), findsWidgets, reason: '标题始终在');

    await tester.tap(find.text('外观').first);
    await tester.pumpAndSettle();
    expect(find.text('子项A').hitTestable(), findsOneWidget);
  });

  testWidgets('初始收起：initiallyExpanded=false', (WidgetTester tester) async {
    await tester.pumpWidget(host(
      const SettingSection(
        title: '采样',
        initiallyExpanded: false,
        children: <Widget>[Text('温度')],
      ),
    ));
    expect(find.text('温度').hitTestable(), findsNothing);
    await tester.tap(find.text('采样').first);
    await tester.pumpAndSettle();
    expect(find.text('温度').hitTestable(), findsOneWidget);
  });

  testWidgets('collapsible=false 时不可折叠', (WidgetTester tester) async {
    await tester.pumpWidget(host(
      const SettingSection(
        title: '统计',
        collapsible: false,
        children: <Widget>[Text('占用 1 GB')],
      ),
    ));
    expect(find.text('占用 1 GB').hitTestable(), findsOneWidget);
    await tester.tap(find.text('统计').first);
    await tester.pumpAndSettle();
    expect(find.text('占用 1 GB').hitTestable(), findsOneWidget,
        reason: '明确关掉折叠的页面不该被收起');
  });

  testWidgets('分组说明在收起后仍然显示', (WidgetTester tester) async {
    await tester.pumpWidget(host(
      const SettingSection(
        title: '语音',
        description: '端侧合成',
        children: <Widget>[Text('音色')],
      ),
    ));
    await tester.tap(find.text('语音').first);
    await tester.pumpAndSettle();
    expect(find.text('端侧合成').hitTestable(), findsWidgets);
    expect(find.text('音色').hitTestable(), findsNothing);
  });
}
