import 'package:dna/utils/version_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// 版本解析与比较的单元测试。
///
/// 这里刻意覆盖**不规范写法** —— GitHub tag 由人写,格式不受控,
/// 解析必须容错而不是崩溃或静默误判。
void main() {
  group('parseVersion 基本形式', () {
    test('标准 x.y.z', () {
      expect(parseVersion('1.2.3').parts, <int>[1, 2, 3]);
      expect(parseVersion('0.2.1').parts, <int>[0, 2, 1]);
    });

    test('前导 v', () {
      expect(parseVersion('v1.2.3').parts, <int>[1, 2, 3]);
      expect(parseVersion('V1.2.3').parts, <int>[1, 2, 3]);
    });

    test('位数不足', () {
      expect(parseVersion('1').parts, <int>[1]);
      expect(parseVersion('1.2').parts, <int>[1, 2]);
    });

    test('位数更多', () {
      expect(parseVersion('1.2.3.4').parts, <int>[1, 2, 3, 4]);
    });
  });

  group('parseVersion 截断规则(非数字非点即截断)', () {
    test('预发布后缀被截断', () {
      expect(parseVersion('1.2.3-beta').parts, <int>[1, 2, 3]);
      expect(parseVersion('1.2.3-rc.1').parts, <int>[1, 2, 3]);
      expect(parseVersion('1.2.3_alpha').parts, <int>[1, 2, 3]);
    });

    test('build 号 +aaa 不计入比较', () {
      expect(parseVersion('0.2.1+3').parts, <int>[0, 2, 1]);
      expect(parseVersion('1.2.3+999').parts, <int>[1, 2, 3]);
    });

    test('前置文字被跳过,从第一个数字开始', () {
      expect(parseVersion('release-1.2.3').parts, <int>[1, 2, 3]);
      expect(parseVersion('ver 1.2.3').parts, <int>[1, 2, 3]);
      expect(parseVersion('DNA v0.2.1').parts, <int>[0, 2, 1]);
    });

    test('中间夹文字则在那里停下', () {
      expect(parseVersion('1.2.beta').parts, <int>[1, 2]);
      expect(parseVersion('1.2.3 后续说明').parts, <int>[1, 2, 3]);
    });

    test('尾部多余的点不产生空段', () {
      expect(parseVersion('1.2.').parts, <int>[1, 2]);
      expect(parseVersion('1.2.3.').parts, <int>[1, 2, 3]);
    });

    test('连续的点按 0 处理', () {
      expect(parseVersion('1..3').parts, <int>[1, 0, 3]);
    });

    test('空白被忽略', () {
      expect(parseVersion('  1.2.3  ').parts, <int>[1, 2, 3]);
    });
  });

  group('parseVersion 无法解析', () {
    test('没有数字', () {
      expect(parseVersion('abc').isValid, isFalse);
      expect(parseVersion('latest').isValid, isFalse);
      expect(parseVersion('').isValid, isFalse);
    });
  });

  group('compareParts 补 0 比较', () {
    test('相等', () {
      expect(compareParts(<int>[1, 2, 3], <int>[1, 2, 3]), 0);
    });

    test('短的补 0 后相等', () {
      expect(compareParts(<int>[0, 2], <int>[0, 2, 0]), 0);
      expect(compareParts(<int>[1], <int>[1, 0, 0]), 0);
    });

    test('逐位大小', () {
      expect(compareParts(<int>[0, 2, 1], <int>[0, 3]), lessThan(0));
      expect(compareParts(<int>[0, 3], <int>[0, 2, 9]), greaterThan(0));
      expect(compareParts(<int>[1, 0], <int>[0, 99, 99]), greaterThan(0));
    });
  });

  group('isRemoteNewer(只比 x.y.z,忽略 +aaa)', () {
    test('远端更高', () {
      expect(isRemoteNewer('0.2.1+3', 'v0.3.0'), isTrue);
      expect(isRemoteNewer('0.2.1', '1.0.0'), isTrue);
    });

    test('相等时不提示(即使本地有 build 号)', () {
      // 这是最关键的一条:本地 0.2.1+3 vs 远端 0.2.1 —— 只比 x.y.z → 相等。
      expect(isRemoteNewer('0.2.1+3', '0.2.1'), isFalse);
      expect(isRemoteNewer('0.2.1+3', 'v0.2.1'), isFalse);
    });

    test('本地更高', () {
      expect(isRemoteNewer('0.3.0', 'v0.2.1'), isFalse);
      expect(isRemoteNewer('1.0.0+1', '0.9.9'), isFalse);
    });

    test('远端格式不规范但前几位可读', () {
      expect(isRemoteNewer('0.2.1', 'release-0.3.0-beta'), isTrue);
      expect(isRemoteNewer('0.2.1', 'v0.2.2+build.99'), isTrue);
      expect(isRemoteNewer('0.2.1', 'ver0.2.1'), isFalse);
    });

    test('Windows 真机场景:PackageInfo 返回带 build 号的 0.2.1+3', () {
      // Windows 上 PackageInfo.version 读的是 exe 版本资源,
      // 实测为 "0.2.1+3"(带 +build),与 Android/iOS 不同。
      // 必须确认这种形式同样被正确截断,否则线上会误报「有新版本」。
      expect(parseVersion('0.2.1+3').parts, <int>[0, 2, 1]);

      // 线上最新为 v0.2.1 -> 相等 -> 不提示。
      expect(isRemoteNewer('0.2.1+3', 'v0.2.1'), isFalse,
          reason: 'Windows 本地 0.2.1+3 与线上 0.2.1 必须判定为相同,'
              '否则每次启动都会误报有新版本');

      // 线上更高时仍要正确提示。
      expect(isRemoteNewer('0.2.1+3', 'v0.3.0'), isTrue);
    });

    test('任何一侧解析失败 -> 不提示(不误报)', () {
      expect(isRemoteNewer('0.2.1', 'latest'), isFalse);
      expect(isRemoteNewer('abc', '1.0.0'), isFalse);
      expect(isRemoteNewer('', ''), isFalse);
    });
  });
}
