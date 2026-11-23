import 'package:dna/pages/splash/splash_animations.dart';
import 'package:dna/pages/splash/splash_preview_dialog.dart';
import 'package:dna/pages/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设置 → 高级 → 预览开场动画：能播、能重播、关掉动画时给说明。
void main() {
  Future<void> pumpDialog(WidgetTester tester, String animationId) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SplashPreviewDialog(animationId: animationId)),
      ),
    );
    await tester.pump();
  }

  final Finder replayFinder =
      find.byKey(const ValueKey<String>('splash-preview-replay'));
  TextButton replayButton(WidgetTester tester) =>
      tester.widget<TextButton>(replayFinder);

  testWidgets('标题、动画名与时长都在', (WidgetTester tester) async {
    await pumpDialog(tester, 'fade');
    expect(find.text('开场动画预览'), findsWidgets);
    expect(find.textContaining('淡入'), findsWidgets);
    expect(find.textContaining('0.9 秒'), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('播完之前不能重播，播完之后可以，点了会重新播', (WidgetTester tester) async {
    await pumpDialog(tester, 'fade');
    expect(replayButton(tester).onPressed, isNull, reason: '播完前不该能点');

    await tester.pump(); // 起跑
    await tester.pump(Duration(milliseconds: splashAnimationById('fade').durationMs));
    await tester.pumpAndSettle(); // 让 whenComplete 里的 setState 落到帧上
    expect(replayButton(tester).onPressed, isNotNull, reason: '播完后应能重播');

    await tester.tap(replayFinder);
    await tester.pump();
    await tester.pump();
    expect(replayButton(tester).onPressed, isNull, reason: '点了重播应重新进入「播放中」');

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('选「关闭动画」时给说明，不放舞台', (WidgetTester tester) async {
    await pumpDialog(tester, kSplashAnimationOffId);
    expect(find.byType(SplashStage), findsNothing);
    expect(find.textContaining('关闭动画'), findsWidgets);
    expect(replayFinder, findsNothing, reason: '没有可播的动画就不该有重播按钮');
    await tester.pumpAndSettle();
  });

  testWidgets('未知 id 回退到默认动画，不崩', (WidgetTester tester) async {
    await pumpDialog(tester, '不存在的动画');
    expect(find.byType(SplashStage), findsOneWidget);
    await tester.pump(Duration(milliseconds: kSplashAnimations.first.durationMs));
    await tester.pumpAndSettle();
  });
}
