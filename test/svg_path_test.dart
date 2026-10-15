import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:dna/pages/splash/logo_painter.dart';
import 'package:dna/utils/svg_path.dart';
import 'package:dna/widgets/brand_paths.dart';

/// SVG path 解析器的行为测试。
///
/// 这里踩过一个真实的坑：厂商标（openai / deepseek / zhipu）的圆弧参数写成
/// 「a.797.797 0 00-.856 0」这种压缩形式，其中 **00 是两个标志位**（large-arc=0、
/// sweep=0），不是一个数 0。原先用「正则一把抓出所有数字」的写法会把 00 并成
/// 一个数，参数从 7 个变 6 个，弧被整段丢掉，而且当前点不再更新 —— 图形明显残缺。
/// 所以下面既测弧的几何语义，也测「每条命令的参数是否被完整消费」这个不变量。
///
/// 弧的几何用**中点**断言，不用弧长：PathMetric 走曲线扁平化，长度会比解析值短
/// 约 2.5%，拿它做精确断言会误判。
void main() {
  PathMetric metricOf(String d) => parseSvgPath(d).computeMetrics().first;

  Offset pointAt(String d, double fraction) {
    final PathMetric m = metricOf(d);
    return m.getTangentForOffset(m.length * fraction)!.position;
  }

  group('椭圆弧 A / a', () {
    test('sweep=1 从上侧绕过（屏幕坐标顺时针）', () {
      final Offset mid = pointAt('M 0 0 A 5 5 0 0 1 10 0', 0.5);
      expect(mid.dx, closeTo(5, 0.05));
      expect(mid.dy, closeTo(-5, 0.05), reason: 'sweep=1 应向上凸');
    });

    test('sweep=0 从下侧绕过（标志位不是被忽略的）', () {
      final Offset mid = pointAt('M 0 0 A 5 5 0 0 0 10 0', 0.5);
      expect(mid.dx, closeTo(5, 0.05));
      expect(mid.dy, closeTo(5, 0.05), reason: 'sweep=0 应向下凸');
    });

    test('弧长按弧长参数化（不是退化成弦长）', () {
      final double len = metricOf('M 0 0 A 5 5 0 0 1 10 0').length;
      expect(len, greaterThan(15.0), reason: '弦长只有 10');
      expect(len, lessThanOrEqualTo(math.pi * 5 + 0.01));
    });

    test('large-arc 标志位改变弧的走向（不是被忽略的）', () {
      // 弦长 6、半径 5，圆心在 (3, ±4)：
      //   劣弧圆心 (3,4)，向上凸，中点在 (3,-1)；
      //   优弧圆心 (3,-4)，绕远路，中点在 (3,-9)。
      final Offset minor = pointAt('M 0 0 A 5 5 0 0 1 6 0', 0.5);
      final Offset major = pointAt('M 0 0 A 5 5 0 1 1 6 0', 0.5);
      expect(minor.dx, closeTo(3, 0.05));
      expect(minor.dy, closeTo(-1, 0.05));
      expect(major.dx, closeTo(3, 0.05));
      expect(major.dy, closeTo(-9, 0.05), reason: '优弧应绕到另一侧');
    });

    test('rx 或 ry 为 0 时按直线处理（规范要求，不是丢弃）', () {
      final Rect b = parseSvgPath('M 0 0 A 0 5 0 0 1 10 0').getBounds();
      expect(b.width, closeTo(10, 0.001));
      expect(b.height, closeTo(0, 0.001), reason: '半径为 0 的弧应退化成直线');
    });

    test('相对弧 a 以当前点为基准', () {
      final Offset mid = pointAt('M 10 10 a 5 5 0 0 1 10 0', 0.5);
      expect(mid.dx, closeTo(15, 0.05));
      expect(mid.dy, closeTo(5, 0.05));
    });
  });

  group('参数扫描（曾经在这里静默画残）', () {
    test('连写的两个标志位 00 要切成两个 0，不是一个数', () {
      // 厂商标里的真实写法：openai 的 a.797.797 0 00-.856 0。
      // 用「匹配数字」读会把 00 并成一个数，参数 7 → 6，弧整段丢掉。
      const String d = 'M 0 0 a.797.797 0 00-.856 0';
      expect(svgPathArgumentIssues(d), isEmpty,
          reason: '参数没被完整消费，说明标志位被当成数字了');

      // 而且这条弧必须真的画出来：中点不能落在弦上。
      final PathMetric m = parseSvgPath(d).computeMetrics().first;
      expect(m.length, greaterThan(0.856));
    });

    test('连写的三个标志位 011 也要正确切开', () {
      // A 5 5 0 | laf=0 | sf=1 | x=10 | y=0
      const String d = 'M 0 0 A5 5 0 0110 0';
      expect(svgPathArgumentIssues(d), isEmpty);
      final Offset mid = pointAt(d, 0.5);
      expect(mid.dx, closeTo(5, 0.05));
      expect(mid.dy, closeTo(-5, 0.05), reason: 'sf=1 应向上凸');
    });

    test('少一个参数的命令会被诊断出来（不是静默通过）', () {
      expect(svgPathArgumentIssues('M 0 0 L 10'), isNotEmpty,
          reason: 'L 只读到 1 个参数，不是 2 的整数倍');
      expect(svgPathArgumentIssues('M 0 0 L 10 20'), isEmpty);
    });

    test('科学计数法按一个数读', () {
      final Rect b = parseSvgPath('M 1e-5 2.5 L -3 0').getBounds();
      expect(b.left, closeTo(-3, 1e-9));
      expect(b.top, closeTo(0, 1e-9));
      expect(svgPathArgumentIssues('M 1e-5 2.5 L -3 0'), isEmpty);
    });

    test('省略整数部分的写法（.5 / -.5）能解析', () {
      final Rect b = parseSvgPath('M .5 -.5 L 1.5 2.5').getBounds();
      expect(b.left, closeTo(0.5, 1e-9));
      expect(b.top, closeTo(-0.5, 1e-9));
    });
  });

  group('平滑曲线 S / T 的控制点反射', () {
    test('S 的第一控制点是上一段第二控制点关于当前点的镜像', () {
      // 两段三次曲线关于 x=10 对称：正确反射时后半段中点在 (15,-7.5)，
      // 不反射（直接拿当前点当控制点）会落在 (15,-3.75)。
      final Offset q = pointAt('M 0 0 C 0 10 10 10 10 0 S 20 -10 20 0', 0.75);
      expect(q.dx, closeTo(15, 0.05));
      expect(q.dy, closeTo(-7.5, 0.05), reason: '未做反射时这里会是 -3.75');
    });

    test('T 的控制点反射同样生效', () {
      final Offset q = pointAt('M 0 0 Q 5 10 10 0 T 20 0', 0.75);
      expect(q.dx, closeTo(15, 0.05));
      expect(q.dy, closeTo(-5, 0.05));
    });
  });

  group('基本命令', () {
    test('M 之后多余的坐标对按 L 处理', () {
      final Rect b = parseSvgPath('M 0 0 10 0 10 10').getBounds();
      expect(b.right, closeTo(10, 0.001));
      expect(b.bottom, closeTo(10, 0.001));
    });

    test('Z 闭合后当前点回到子路径起点（相对命令以此为基准）', () {
      final List<PathMetric> ms =
          parseSvgPath('M 5 5 L 10 5 L 10 10 Z m 1 1 l 2 0')
              .computeMetrics()
              .toList();
      expect(ms, hasLength(2), reason: 'z 后应起一条新的子路径');
      final Offset secondStart = ms[1].getTangentForOffset(0)!.position;
      expect(secondStart.dx, closeTo(6, 0.001),
          reason: 'z 把当前点带回 (5,5)，m 1 1 应落到 (6,6)');
      expect(secondStart.dy, closeTo(6, 0.001));
    });

    test('fillType 会传给返回的 Path', () {
      expect(
          parseSvgPath('M 0 0 L 1 1', fillType: PathFillType.evenOdd).fillType,
          PathFillType.evenOdd);
      expect(parseSvgPath('M 0 0 L 1 1').fillType, PathFillType.nonZero);
    });
  });

  group('解析不变量：源文件的参数必须被完整消费', () {
    test('四个厂商标都没有参数残缺的命令', () {
      for (final MapEntry<String, String> entry in kBrandSvgPaths.entries) {
        final String key = entry.key;
        expect(svgPathArgumentIssues(entry.value), isEmpty,
            reason: '$key 有命令的参数没被读完，图形会静默残缺');
      }
    });

    test('应用标的 13 段 path 同样没有参数残缺', () {
      expect(LogoPainter.svgPaths, hasLength(13));
      for (int i = 0; i < LogoPainter.svgPaths.length; i++) {
        expect(svgPathArgumentIssues(LogoPainter.svgPaths[i]), isEmpty,
            reason: '应用标第 $i 段参数没读完，启动页会画残');
      }
    });

    test('至少三个厂商标用到圆弧 —— 这就是必须支持 A/a 的原因', () {
      final int withArc = kBrandSvgPaths.values
          .where((String d) => RegExp('[Aa]').hasMatch(d))
          .length;
      expect(withArc, greaterThanOrEqualTo(3),
          reason: '若哪天 A/a 支持被拿掉，这几个图标会静默画残');
    });

    for (final MapEntry<String, String> entry in kBrandSvgPaths.entries) {
      final String key = entry.key;
      test('厂商标 $key 解析出有效且非退化的路径', () {
        final Path p =
            parseSvgPath(entry.value, fillType: PathFillType.evenOdd);
        final Rect b = p.getBounds();
        expect(b.isEmpty, isFalse, reason: '路径为空说明命令没被解析');
        // 图标集是按 24x24 画的，坐标不该跑出 viewBox。原先把 00 当数字的
        // bug 会让当前点漂移，后续相对命令越画越偏，这条就会先炸。
        expect(b.left, greaterThanOrEqualTo(-0.5), reason: 'bounds=$b');
        expect(b.top, greaterThanOrEqualTo(-0.5), reason: 'bounds=$b');
        expect(b.right, lessThanOrEqualTo(kBrandSvgViewBox + 0.5),
            reason: 'bounds=$b');
        expect(b.bottom, lessThanOrEqualTo(kBrandSvgViewBox + 0.5),
            reason: 'bounds=$b');
        // 图形要真的铺开：横向跨度太小说明只解析出零头。
        expect(b.width, greaterThan(12), reason: 'bounds=$b');
        expect(b.height, greaterThan(8), reason: 'bounds=$b');
        final double total = p
            .computeMetrics()
            .fold<double>(0, (double s, PathMetric m) => s + m.length);
        expect(total, greaterThan(20), reason: '总长为 $total');
      });
    }
  });
}
