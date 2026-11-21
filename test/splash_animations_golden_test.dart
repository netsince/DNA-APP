import 'dart:io';

import 'package:dna/pages/splash/glass_logo_animation.dart';
import 'package:dna/pages/splash/splash_animations.dart';
import 'package:dna/pages/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 四种开场动画的观感截图（golden）。
///
/// 跑法：flutter test --update-goldens test/splash_animations_golden_test.dart
/// 每段在「播到 40%」时截一张，方便一眼比对不同风格。
Future<void> _loadFonts() async {
  final FontLoader loader = FontLoader('SourceHanSans');
  for (final String path in <String>[
    'assets/fonts/SourceHanSansSC-Regular.otf',
    'assets/fonts/SourceHanSansSC-Medium.otf',
  ]) {
    final File file = File(path);
    if (file.existsSync()) {
      loader.addFont(Future<ByteData>.value(
        ByteData.view(file.readAsBytesSync().buffer),
      ));
    }
  }
  await loader.load();
}

void main() {
  setUp(() => GlassLogoAnimation.debugSkipFirstFrameGate = true);
  tearDown(() => GlassLogoAnimation.debugSkipFirstFrameGate = false);

  setUpAll(() async {
    await _loadFonts();
  });

  for (final SplashAnimationSpec spec in kSplashAnimations) {
    testWidgets('开场动画：${spec.id}', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, fontFamily: 'SourceHanSans'),
          home: SplashPage(animation: spec, onComplete: () {}),
        ),
      );
      if (spec.enabled) {
        // 时钟每帧最多推进 50ms，取 25% 时刻需要小步 pump。
        await tester.pump();
        if (spec.id == 'glassLogo') {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          });
        }
        await tester.pump(const Duration(milliseconds: 16));
        final int steps = (spec.durationMs * 0.25 / 50).round();
        for (int i = 0; i < steps; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
      await expectLater(
        find.byType(SplashPage),
        matchesGoldenFile('goldens/splash_${spec.id}.png'),
      );
      // 让动画跑完，避免测试结束时还有未完成的 ticker。
      if (spec.enabled) {
        await tester.pump(Duration(milliseconds: spec.durationMs));
        await tester.pumpAndSettle();
      }
    });
  }
}
