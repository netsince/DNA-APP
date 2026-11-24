import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/pages/chat/ui/widgets/candidate_action_bar.dart';

/// `CandidateActionBar` 的行为锁。
///
/// 它是从「重说结果」与「灵感列表」两张弹框里抽出来的共享按钮栏，抽的时候
/// 就发现两张表的禁用条件不一样（重说：生成中全禁 + 图标换转圈；灵感：生成中
/// 全禁但图标不变），所以这里把这几条钉住，避免以后改一处坏另一处。
Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('空闲态：三个按钮都可点，文案按传入显示', (WidgetTester tester) async {
    int cancels = 0, regens = 0, confirms = 0;
    await tester.pumpWidget(
      _host(
        CandidateActionBar(
          onCancel: () => cancels++,
          onRegenerate: () => regens++,
          onConfirm: () => confirms++,
          cancelLabel: '取消',
          regenerateLabel: '再生成三条',
        ),
      ),
    );

    expect(find.text('取消'), findsWidgets);
    expect(find.text('再生成三条'), findsWidgets);
    expect(find.text('使用'), findsWidgets);

    await tester.tap(find.text('取消').last);
    await tester.tap(find.text('再生成三条').last);
    await tester.tap(find.text('使用').last);
    expect(cancels, 1);
    expect(regens, 1);
    expect(confirms, 1);
  });

  testWidgets('busy：三个按钮全部禁用', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(
      _host(
        CandidateActionBar(
          onCancel: () => taps++,
          onRegenerate: () => taps++,
          onConfirm: () => taps++,
          cancelLabel: '取消',
          regenerateLabel: '再生成三条',
          busy: true,
        ),
      ),
    );

    await tester.tap(find.text('取消').last, warnIfMissed: false);
    await tester.tap(find.text('使用').last, warnIfMissed: false);
    expect(taps, 0, reason: '生成中不允许任何操作');

    final OutlinedButton cancel = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(cancel.onPressed, isNull);
  });

  testWidgets('showRegenerateSpinner：只有要求时才把图标换成转圈并改文案', (
    WidgetTester tester,
  ) async {
    // 重说那张：busy + spinner
    await tester.pumpWidget(
      _host(
        CandidateActionBar(
          onCancel: () {},
          onRegenerate: () {},
          onConfirm: () {},
          cancelLabel: '取消',
          regenerateLabel: '再生成三条',
          busy: true,
          showRegenerateSpinner: true,
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('生成中…'), findsWidgets);

    // 灵感那张：busy 但不换图标
    await tester.pumpWidget(
      _host(
        CandidateActionBar(
          onCancel: () {},
          onRegenerate: () {},
          onConfirm: () {},
          cancelLabel: '关闭',
          regenerateLabel: '再试',
          busy: true,
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('再试'), findsWidgets);
  });

  testWidgets('regenerateEnabled / confirmEnabled 为 false 时对应按钮禁用', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CandidateActionBar(
          onCancel: () {},
          onRegenerate: () {},
          onConfirm: () {},
          cancelLabel: '关闭',
          regenerateLabel: '再试',
          regenerateEnabled: false,
          confirmEnabled: false,
        ),
      ),
    );
    // FilledButton.tonalIcon 也是 FilledButton，所以按顺序取：先「再试」后「使用」。
    final Finder filled = find.byType(FilledButton);
    expect(filled, findsNWidgets(2));
    final FilledButton regenerate = tester.widget<FilledButton>(filled.first);
    final FilledButton confirm = tester.widget<FilledButton>(filled.last);
    expect(regenerate.onPressed, isNull, reason: '没填主题时「再试」应禁用');
    expect(confirm.onPressed, isNull, reason: '没选候选时「使用」应禁用');
  });
}
