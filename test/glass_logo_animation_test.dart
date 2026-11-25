import 'dart:ui' as ui;

import 'package:dna/pages/splash/glass_logo_animation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// 液态玻璃开场动画：着色器能编译、组件能跑完、不吞异常。
void main() {
  testWidgets('着色器能加载（语法/联编正确性）', (WidgetTester tester) async {
    late ui.FragmentProgram program;
    try {
      program = await ui.FragmentProgram.fromAsset('shaders/glass_logo.frag');
    } catch (e) {
      fail('着色器编译失败：$e');
    }
    expect(program.fragmentShader(), isNotNull);
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
    await tester.pump(); // 起跑
    await tester.pump(const Duration(milliseconds: 900));
    expect(done, 0, reason: '中途不该提前回调');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(done, 1);
  });
}
