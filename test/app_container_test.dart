import 'package:animations/animations.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/app_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: AppContainer<String>(
              closedBuilder: (BuildContext context, VoidCallback open) =>
                  SizedBox(
                width: 120,
                height: 48,
                child: TextButton(
                  onPressed: open,
                  child: const Text('closed'),
                ),
              ),
              openBuilder: (BuildContext context, VoidCallback close) =>
                  Scaffold(
                body: Center(
                  child: TextButton(
                    // close({returnValue}) 命名可选参数;此处不回传。
                    onPressed: close,
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('closed 态渲染 closedBuilder;open 页尚未挂载',
      (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.pump();
    expect(find.text('closed'), findsOneWidget);
    expect(find.text('open'), findsNothing);
  });

  testWidgets('点击 closed 侧起飞:飞行结束后 openBuilder 接管',
      (WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('closed'));
    await tester.pump();
    await tester.pump(AppMotion.transform);
    await tester.pump();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('open 侧调 close 回传结果,容器缩回原位',
      (WidgetTester tester) async {
    String? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: AppContainer<String>(
              onClosed: (String? result) => received = result,
              closedBuilder: (BuildContext context, VoidCallback open) =>
                  const Text('closed'),
              openBuilder:
                  (BuildContext context, CloseContainerActionCallback<String> close) =>
                  TextButton(
                // close({returnValue}):命名可选参数回传结果。
                onPressed: () => close(returnValue: 'done'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('closed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(received, 'done');
    expect(find.text('closed'), findsOneWidget);
  });
}
