import 'dart:typed_data';

import 'package:dna/utils/image_decode.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// 解码尺寸限制：**只给一条边**。
///
/// 回归的背景：聊天背景曾把「整屏最长边」同时传给 width 和 height，
/// `ResizeImage` 于是把图拉伸成正方形解码 —— 用户看到的是「裁剪把人拉变形了」。
void main() {
  group('decodeLimitFor', () {
    test('竖屏：只限高度', () {
      final ({int? width, int? height}) l = decodeLimitFor(const Size(390, 844));
      expect(l.width, isNull, reason: '宽度留给引擎按比例算');
      expect(l.height, 844);
    });

    test('横屏：只限宽度', () {
      final ({int? width, int? height}) l = decodeLimitFor(const Size(844, 390));
      expect(l.width, 844);
      expect(l.height, isNull);
    });

    test('超长边收到上限 2560', () {
      final ({int? width, int? height}) l = decodeLimitFor(const Size(4000, 2000));
      expect(l.width, 2560);
      expect(l.height, isNull);
    });

    test('极小视口抬到下限 800', () {
      final ({int? width, int? height}) l = decodeLimitFor(const Size(100, 200));
      expect(l.height, 800);
      expect(l.width, isNull);
    });

    test('窗口未布局（0 或 NaN）时不限制', () {
      expect(decodeLimitFor(Size.zero).width, isNull);
      expect(decodeLimitFor(Size.zero).height, isNull);
      expect(decodeLimitFor(const Size(double.nan, 100)).height, isNull);
    });

    test('任何输入下都不会同时给两条边（否则解码被拉伸）', () {
      const List<Size> sizes = <Size>[
        Size(390, 844),
        Size(844, 390),
        Size(500, 500),
        Size(4000, 3000),
        Size(1, 1),
        Size(0, 0),
      ];
      for (final Size size in sizes) {
        final ({int? width, int? height}) l = decodeLimitFor(size);
        expect(
          l.width == null || l.height == null,
          isTrue,
          reason: '视口 $size 同时给了宽(${l.width})和高(${l.height})，解码会被拉伸',
        );
      }
    });
  });

  group('limitDecode', () {
    test('包出来的 ResizeImage 只有一条边，且不放大', () {
      final ImageProvider base = MemoryImage(Uint8List.fromList(<int>[1, 2, 3]));
      final ResizeImage resized =
          limitDecode(base, const Size(390, 844)) as ResizeImage;
      expect(resized.width, isNull);
      expect(resized.height, 844);
      expect(resized.allowUpscaling, isFalse);
    });

    test('视口无效时原样返回，不包 ResizeImage', () {
      final ImageProvider base = MemoryImage(Uint8List.fromList(<int>[1, 2, 3]));
      expect(limitDecode(base, Size.zero), same(base));
    });
  });
}
