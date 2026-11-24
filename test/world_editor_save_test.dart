import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/models/world.dart';
import 'package:dna/pages/world_editor_page.dart';
import 'package:dna/widgets/app_editor_frame.dart';

/// 世界编辑器「保存失败」的行为锁。
///
/// 这条测试是给一个真实漏洞补的：`WorldEditorPage._save` 原来**没有 try/catch**
/// （角色卡编辑器早就有）。保存抛异常时界面停在原地、什么都不提示，用户看到的
/// 就是「点了没反应」；连点还会重复写库。
///
/// 断言两件事：原因要弹出来、页面不能被关掉。
Future<void> _pumpEditor(
  WidgetTester tester, {
  required Future<void> Function(World) onSave,
}) async {
  await tester.pumpWidget(MaterialApp(home: WorldEditorPage(onSave: onSave)));
  await tester.pumpAndSettle();
}

Future<void> _fillName(WidgetTester tester, String name) async {
  final Finder nameField = find.byType(TextField).first;
  await tester.enterText(nameField, name);
  await tester.pump();
}

void main() {
  testWidgets('保存抛异常：把原因弹出来，且不关闭页面', (WidgetTester tester) async {
    bool called = false;
    await _pumpEditor(
      tester,
      onSave: (World world) async {
        called = true;
        throw Exception('磁盘满了');
      },
    );
    await _fillName(tester, '测试世界');

    await tester.tap(find.byType(AppEditorFab));
    await tester.pumpAndSettle();

    expect(called, isTrue, reason: '应当真的调用了保存');
    expect(find.textContaining('磁盘满了'), findsWidgets,
        reason: '失败原因必须显示给用户，不能静默吞掉');
    expect(find.byType(WorldEditorPage), findsOneWidget,
        reason: '保存失败不能把页面关掉');
  });

  testWidgets('名称为空：给字段级错误，且不调用保存', (WidgetTester tester) async {
    bool called = false;
    await _pumpEditor(
      tester,
      onSave: (World world) async {
        called = true;
      },
    );

    await tester.tap(find.byType(AppEditorFab));
    await tester.pumpAndSettle();

    expect(called, isFalse, reason: '名称为空时不该写库');
    expect(find.textContaining('请填写世界名称'), findsWidgets);
    expect(find.byType(WorldEditorPage), findsOneWidget);
  });
}
