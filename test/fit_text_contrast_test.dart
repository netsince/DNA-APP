import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dna/widgets/fit_text.dart';

void main() {
  group('FitText 背景明暗自动感知与对比度计算测试', () {
    test('compositeOver 正确处理实色与半透明颜色混合', () {
      const Color darkSurface = Color(0xFF141218);
      const Color whiteOpaque = Color(0xFFFFFFFF);
      const Color whiteHalf = Color(0x80FFFFFF); // alpha ~ 0.5

      final Color fullyWhite = FitText.compositeOver(whiteOpaque, darkSurface);
      expect(fullyWhite.r, closeTo(1.0, 0.01));
      expect(fullyWhite.g, closeTo(1.0, 0.01));
      expect(fullyWhite.b, closeTo(1.0, 0.01));

      final Color blended = FitText.compositeOver(whiteHalf, darkSurface);
      expect(blended.a, 1.0);
      expect(blended.r, greaterThan(0.4));
    });

    test('isLightBackground 准确识别浅色与深色背景', () {
      // 纯白背景为浅色
      expect(FitText.isLightBackground(const Color(0xFFFFFFFF)), isTrue);
      // 浅黄高亮强调色（如部分角色卡提取色）为浅色
      expect(FitText.isLightBackground(const Color(0xFFFFF9C4)), isTrue);
      expect(FitText.isLightBackground(const Color(0xFFFFE082)), isTrue);

      // 深色主题底色为深色
      expect(FitText.isLightBackground(const Color(0xFF141218)), isFalse);
      // 经典深灰为深色
      expect(FitText.isLightBackground(const Color(0xFF2C2C2C)), isFalse);

      // 深色底色上叠加高透明度白色气泡（80% 不透明度白色）为浅色
      expect(
        FitText.isLightBackground(
          const Color(0xCCFFFFFF),
          const Color(0xFF141218),
        ),
        isTrue,
      );

      // 深色底色上叠加低透明度白色气泡（15% 不透明度白色）整体仍偏深
      expect(
        FitText.isLightBackground(
          const Color(0x26FFFFFF),
          const Color(0xFF141218),
        ),
        isFalse,
      );
    });

    testWidgets('FitText 根据 contrastBackground 渲染正确对比度的文字颜色', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: Column(
              children: <Widget>[
                FitText(
                  '浅色背景文字',
                  key: Key('light_bg_text'),
                  contrastBackground: Color(0xFFFFF9C4), // 亮黄色气泡
                ),
                FitText(
                  '深色背景文字',
                  key: Key('dark_bg_text'),
                  contrastBackground: Color(0xFF1E1E24), // 深色气泡
                ),
              ],
            ),
          ),
        ),
      );

      final Text lightBgText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('light_bg_text')),
          matching: find.byType(Text),
        ).last,
      );
      final Text darkBgText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('dark_bg_text')),
          matching: find.byType(Text),
        ).last,
      );

      // 亮黄背景在深色模式下自动采用深色字（避免白字配白底看不清）
      expect(lightBgText.style?.color, const Color(0xFF1D1B20));
      // 深色背景在深色模式下继续采用浅色字
      expect(darkBgText.style?.color, isNotNull);
      expect(darkBgText.style!.color!.computeLuminance(), greaterThan(0.5));
    });
  });
}
