import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/utils/svg_path.dart';
import 'package:dna/widgets/brand_icon.dart';
import 'package:dna/widgets/brand_paths.dart';

/// 厂商标组件的渲染契约。
///
/// 曾经这里是四个通用 Material 图标（hub / psychology / auto_awesome /
/// travel_explore），用户反馈「认不出是哪一家」。现在用真实品牌图形。
///
/// 因为品牌图形是**画出来的**（CustomPainter + SVG path），不是字体字形，
/// 「编译通过 + 不抛异常」完全不能说明画对了 —— 所以这里把渲染结果真的
/// 光栅化出来数像素，并跟路径的 evenOdd 面积对账。
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );
  }

  /// 网格采样求「路径覆盖的面积占 24x24 viewBox 的比例」。
  double areaFraction(String d, PathFillType fillType) {
    final Path p = parseSvgPath(d, fillType: fillType);
    const int n = 96;
    int inside = 0;
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        final Offset o = Offset(
          (i + 0.5) * kBrandSvgViewBox / n,
          (j + 0.5) * kBrandSvgViewBox / n,
        );
        if (p.contains(o)) inside++;
      }
    }
    return inside / (n * n);
  }

  /// 真的把 BrandIcon 光栅化，返回「有像素覆盖的面积占比」。
  Future<double> paintedCoverage(
    WidgetTester tester,
    String id, {
    double progress = 1,
  }) async {
    final GlobalKey key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: BrandIcon(
              id: id,
              size: 96,
              color: const Color(0xFF000000),
              progress: progress,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    double coverage = 0;
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage();
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      final Uint8List px = data!.buffer.asUint8List();
      int painted = 0;
      int total = 0;
      for (int i = 0; i + 3 < px.length; i += 4) {
        total++;
        // 边界像素带抗锯齿，alpha 阈值取 10 以上才算「画到了」。
        if (px[i + 3] > 10) painted++;
      }
      coverage = total == 0 ? 0 : painted / total;
    });
    return coverage;
  }

  testWidgets('四个厂商都画出品牌图形（CustomPaint），而不是通用图标',
      (WidgetTester tester) async {
    for (final String id in kBrandSvgPaths.keys) {
      await pump(tester, BrandIcon(id: id));
      expect(
        find.byWidgetPredicate(
            (Widget w) => w is CustomPaint && w.painter != null),
        findsWidgets,
        reason: '$id 应画出品牌图形',
      );
      expect(find.byType(Icon), findsNothing,
          reason: '$id 不该退回通用图标');
    }
  });

  testWidgets('未登记的厂商退回通用图标（不空白、不抛异常）',
      (WidgetTester tester) async {
    await pump(tester, const BrandIcon(id: 'not-a-vendor'));
    expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
  });

  testWidgets('尺寸可控', (WidgetTester tester) async {
    await pump(tester, const BrandIcon(id: 'deepseek', size: 32));
    final SizedBox box = tester.widget<SizedBox>(
      find
          .ancestor(
            of: find.byWidgetPredicate(
                (Widget w) => w is CustomPaint && w.painter != null),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(box.width, 32);
    expect(box.height, 32);
  });

  testWidgets('每个厂商标都真的画出图形，且覆盖率与 evenOdd 面积吻合',
      (WidgetTester tester) async {
    for (final MapEntry<String, String> entry in kBrandSvgPaths.entries) {
      final String id = entry.key;
      final double expected = areaFraction(entry.value, PathFillType.evenOdd);
      expect(expected, greaterThan(0.05),
          reason: '$id 面积过小，路径可能没解析出来');
      expect(expected, lessThan(0.75),
          reason: '$id 面积过大，路径可能画糊了');

      final double actual = await paintedCoverage(tester, id);
      // 容差 0.06：网格采样误差 + 抗锯齿边缘像素。
      // 若 fillType 被改成 nonZero（OpenAI 的结、DeepSeek 的鲸鱼有镂空），
      // 或 A/a 支持被拿掉，这里会对不上。
      expect(actual, closeTo(expected, 0.06),
          reason: '$id 渲染覆盖率 $actual 与 evenOdd 面积 $expected 不符');
    }
  });

  testWidgets('描边生长：进度越大覆盖越多，走完等于完整图形',
      (WidgetTester tester) async {
    // OOBE 的英雄位靠 progress 做「画出来」的入场动画。这里用像素把三段钉住：
    // 0 几乎不画、中途介于两者之间、1 与完整面积吻合。
    final double full =
        areaFraction(kBrandSvgPaths['openai']!, PathFillType.evenOdd);

    final double atStart = await paintedCoverage(tester, 'openai', progress: 0);
    final double atHalf = await paintedCoverage(tester, 'openai', progress: 0.5);
    final double atEnd = await paintedCoverage(tester, 'openai', progress: 1);

    expect(atStart, lessThan(0.01), reason: 'progress=0 时不该已经画出图形');
    expect(atHalf, greaterThan(atStart), reason: '中途应比起点画得多');
    expect(atHalf, lessThan(atEnd), reason: '中途不该已经画满');
    expect(atEnd, closeTo(full, 0.06));
  });
}
