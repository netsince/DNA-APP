import 'package:dna/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dna/theme/font_scale.dart';

/// 空态在字号调大时的表现。
///
/// 标题下沉后从 `Text` 换成了 `FitText`。`FitText` 对 6 字以内的短文本会套
/// `FittedBox` 强制单行，空间不够时**缩小**而不是换行 —— 空态标题大多是 4~10 字，
/// 正好落在阈值边缘，所以要实测「调大字号后，标题是不是真的变大了」。
void main() {
  Future<double> titleHeight(WidgetTester tester, int step, String title) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) {
          // step 0 表示「跟随系统」会返回 null，这里只用 2 与 5，必定非空。
          final TextScaler scaler = AppFontScale.textScalerOf(step)!;
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: child!,
          );
        },
        home: Scaffold(
          body: AppEmptyState(icon: Icons.inbox_outlined, title: title),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.text(title).first).height;
  }

  testWidgets('长一点的空态标题：字号调大后确实变大', (WidgetTester tester) async {
    const String t = '还没有人发布世界卡';
    final double small = await titleHeight(tester, 2, t);
    final double large = await titleHeight(tester, 5, t);
    expect(
      large,
      greaterThan(small),
      reason: '字号从「小」调到「超大」，标题高度应当增长；实测 $small → $large',
    );
  });

  testWidgets('短一点的空态标题：字号调大后也确实变大', (WidgetTester tester) async {
    const String t = '暂无内容';
    final double small = await titleHeight(tester, 2, t);
    final double large = await titleHeight(tester, 5, t);
    expect(
      large,
      greaterThan(small),
      reason: '4 字标题会命中 FitText 的 6 字阈值，最容易「不再变大」；实测 $small → $large',
    );
  });
}
