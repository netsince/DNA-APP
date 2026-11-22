import 'dart:ui' as ui;

import 'package:dna/pages/splash/glass_logo_animation.dart';
import 'package:dna/pages/splash/splash_entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 液态玻璃开场动画：着色器能编译、组件能跑完、不吞异常。
void main() {
  setUp(() => GlassLogoAnimation.debugSkipFirstFrameGate = true);
  tearDown(() => GlassLogoAnimation.debugSkipFirstFrameGate = false);

  testWidgets('着色器能加载（语法/联编正确性）', (WidgetTester tester) async {
    late ui.FragmentProgram program;
    try {
      program = await ui.FragmentProgram.fromAsset('shaders/glass_logo.frag');
    } catch (e) {
      fail('着色器编译失败：$e');
    }
    expect(program.fragmentShader(), isNotNull);
  });

  testWidgets('玻璃就绪之前先播「缩放淡入」亮相', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GlassLogoAnimation(durationMs: 3800, onComplete: () {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SplashZoomLogo), findsOneWidget);
    // 收尾：让它跑完，别留下未完成的 ticker
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    for (int i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  });

  testWidgets('动画在时长内回调 onComplete', (WidgetTester tester) async {
    int done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GlassLogoAnimation(
            durationMs: 1800,
            onComplete: () => done++,
          ),
        ),
      ),
    );
    // 启动路径里有两道异步闸（首帧上屏 → 着色器/纹理就绪）。图片解码是真实的
    // 异步 I/O，在 widget 测试里必须用 runAsync 放行，pump 推不动它。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    for (int i = 0; i < 400 && done == 0; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(done, 1);
  });
}
