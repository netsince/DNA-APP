import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:dna/island_app/utils/save_image.dart';

/// 社区「保存图片」的两件事：**转成 PNG** + **文件名可辨认**。
///
/// 用户反馈：保存下来是 WebP，而且写进了系统临时目录 —— 相册看不到、手机上找不到。
/// 现在统一走 `saveImageAsPng`：WebP → PNG（转码在 isolate 里做），再交给系统
/// 「保存到…」对话框（Android 默认落到 Download，相册/文件应用都能看到）。
///
/// 这里测的是不依赖平台通道的部分（转码与命名）；系统对话框由 file_picker 负责。
void main() {
  /// 一张真实的**有损 WebP**（8×8，VP8 块，66 字节）—— 与服务端生图产出的格式完全一致
  /// （服务端就是 `PIL.save(format="WEBP", quality=...)`，有损）。用真数据而不是
  /// 手搓的字节，才能真的验证解码路径。
  final Uint8List tinyWebp = base64Decode(
    'UklGRjoAAABXRUJQVlA4IC4AAAAQAgCdASoIAAgAAUAmJaACdLoB+AH4AAPIAP7tTd/9QWCsy/ew/+jBcBwPeEAA',
  );

  final List<int> pngMagic = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  test('WebP 会被转成 PNG（相册/图片应用都认）', () {
    // 前提：输入确实是 WebP（RIFF....WEBP）
    expect(String.fromCharCodes(tinyWebp.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(tinyWebp.sublist(8, 12)), 'WEBP');

    final Uint8List out = pngBytesFrom(tinyWebp);
    expect(
      out.sublist(0, 8),
      pngMagic,
      reason: '输出必须是 PNG 魔数，否则相册里还是显示不出来',
    );
    expect(out.length, greaterThan(8));
    // 能被真正解码回一张图
    expect(img.decodePng(out), isNotNull);
  });

  test('本来就是 PNG 的输入照样可用', () {
    final Uint8List png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));
    final Uint8List out = pngBytesFrom(png);
    expect(out.sublist(0, 8), pngMagic);
  });

  test('解不开的字节原样返回：宁可格式不对，也不能保存出坏文件', () {
    final Uint8List garbage = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    expect(pngBytesFrom(garbage), garbage);
  });

  test('文件名取提示词并清理不安全字符', () {
    expect(pngFileName('一只在窗边的猫'), '一只在窗边的猫.png');
    expect(pngFileName('猫/狗:图*片?'), '猫_狗_图_片_.png');
    expect(pngFileName('  '), 'artwork.png', reason: '空名字要有兜底');
    expect(pngFileName(''), 'artwork.png');
  });

  test('文件名最长 30 个字符，避免超出文件系统限制', () {
    final String name = pngFileName('猫' * 80);
    expect(name.endsWith('.png'), isTrue);
    expect(name.length, 34, reason: '30 个字符 + ".png"');
  });
}
