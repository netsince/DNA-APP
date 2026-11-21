import 'package:dna/pages/splash/glass_logo_choreography.dart';
import 'package:flutter_test/flutter_test.dart';

/// 液态玻璃开场动画的编排契约：移植自 reactdrops 的五条关键帧曲线。
void main() {
  group('关键帧插值', () {
    test('首尾取端点值，中间平滑过渡', () {
      expect(track(artworkScale, 0.0), 1.4);
      expect(track(artworkScale, 1.46), closeTo(0.41, 0.001));
      final double mid = track(artworkScale, 0.7);
      expect(mid, inInclusiveRange(1.2, 1.4));
    });

    test('曲线单调段不会回弹（1.13→1.25 这段是收敛的）', () {
      double prev = track(artworkScale, 1.13);
      for (double t = 1.13; t <= 1.25; t += 0.01) {
        final double v = track(artworkScale, t);
        expect(v, lessThanOrEqualTo(prev + 0.001), reason: 't=$t 出现回弹');
        prev = v;
      }
    });
  });

  group('时间 → uniform', () {
    const double unit = 260;
    GlassLogoFrame at(double s, {bool showDrop = false}) => glassLogoFrameAt(
          s,
          unitPx: unit,
          finalLogoScale: 0.95,
          dropStrength: 1.35,
          showDrop: showDrop,
        );

    test('时间被裁到 0..2.6，且定版后冻在 1.8', () {
      expect(at(-3).time, 0);
      expect(at(99).time, closeTo(kGlassLogoHoldStart, 1.8));
      expect(kGlassLogoDuration, greaterThan(kGlassLogoHoldStart));
    });

    test('定版后时间冻在 1.8（画面停住，不再做收尾动画）', () {
      expect(at(2.0).time, closeTo(1.8, 0.001));
      expect(at(2.6).time, closeTo(1.8, 0.001));
      expect(at(2.0).artScale, at(1.8).artScale);
    });

    test('定版进度：1.16 前为 0，1.40 后为 1', () {
      expect(at(0.8).settle, 0);
      expect(at(1.3).settle, inExclusiveRange(0, 1));
      expect(at(1.45).settle, 1);
    });

    test('logo 缩放：开场放大，1.28 之后就是 finalLogoScale（不再被吸走）', () {
      expect(at(0.2).artScale, greaterThan(1.2));
      expect(at(1.3).artScale, closeTo(0.95, 0.02));
      expect(at(1.6).artScale, closeTo(0.95, 0.001));
      expect(at(1.8).artScale, closeTo(0.95, 0.001));
    });

    test('结尾默认不落第二滴（停在定版 ICON）', () {
      for (final double s in <double>[1.2, 1.5, 1.8, 2.4]) {
        expect(at(s).dropOpacity, 0, reason: 't=$s 不该出现水滴');
      }
    });

    test('打开 showDrop 时：1.46 之前不可见，之后长大', () {
      // 半径在 1.46 前就有值（关键帧的起点），真正决定「看不看得见」的是
      // dropOpacity —— 原实现同样用一道透明度门把这一滴挡在 1.46 之后。
      expect(at(1.2, showDrop: true).dropOpacity, 0);
      expect(at(1.5, showDrop: true).dropOpacity, inExclusiveRange(0, 1));
      expect(at(1.7, showDrop: true).dropOpacity, greaterThan(0.5));
      expect(at(1.7).drop[0], greaterThan(at(1.2).drop[0]));
      expect(at(1.8).drop[0], greaterThan(at(1.6).drop[0]));
    });

    test('涟漪包络在 1.8 定版时仍是满的（收尾留给 wordmark 模式）', () {
      expect(at(1.8).settleWaves, closeTo(1.0, 0.001));
      expect(at(0.5).settleWaves, closeTo(1.0, 0.001));
    });

    test('dropStrength 只放大第二滴的位移，不影响定版', () {
      final GlassLogoFrame weak = glassLogoFrameAt(1.7,
          unitPx: unit, finalLogoScale: 0.95, dropStrength: 0);
      final GlassLogoFrame strong = glassLogoFrameAt(1.7,
          unitPx: unit, finalLogoScale: 0.95, dropStrength: 2);
      expect(weak.artScale, strong.artScale);
      expect(weak.drop[3], isNot(closeTo(strong.drop[3], 0.0001)));
    });
  });

  group('tuning', () {
    test('默认值是可用的甜点档（不是示例里的极限值）', () {
      const GlassLogoTuning t = GlassLogoTuning();
      expect(t.dispersion, lessThan(2.5));
      expect(t.logoScale, lessThan(1));
      expect(t.unitPx, t.logoSize);
    });
  });
}
