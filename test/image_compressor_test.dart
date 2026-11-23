import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/services/image_compressor.dart';
import 'package:dna/services/ta_export_import_service.dart';

/// 造一张指定尺寸的真图（空白图也够用：测的是尺寸与格式，不是画面）。
Uint8List imageBytes(int width, int height, {String format = 'png'}) {
  final img.Image image = img.Image(width: width, height: height);
  switch (format) {
    case 'gif':
      return Uint8List.fromList(img.encodeGif(image));
    case 'jpg':
      return Uint8List.fromList(img.encodeJpg(image));
    default:
      return Uint8List.fromList(img.encodePng(image));
  }
}

/// 在指定平台上跑一段代码（结束后还原）。
Future<T> onPlatform<T>(TargetPlatform platform, Future<T> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    return await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  // ===================================================================
  // 这一组测试锁住的是「图片缩放只有一个入口」这条不变量：
  // 入口在任何平台都必须能出结果（不许出现「平台未实现」），
  // 且输出必须等比、不放大、长边不超过上限。
  //
  // 它直接来自线上问题：Windows 桌面端导出角色卡报
  // 「导出失败: UnimplementedError: FlutterImageCompress.compressWithList
  // is not available.」——旧代码按 kIsWeb 判平台，桌面端落进了「有原生实现」
  // 的分支，调到一个 Windows 上根本没注册的方法。
  // ===================================================================

  group('缩放语义（fitInside）', () {
    test('等比装盒：横图缩到长边 = 上限', () {
      expect(
        ImageCompressor.fitInside(const ImageSize(4000, 3000), 1024),
        const ImageSize(1024, 768),
      );
    });

    test('等比装盒：竖图长边 = 上限（不是短边）', () {
      // 插件旧的 minWidth/minHeight 是「至少」语义，竖图会算出 768x1365；
      // 这里钉住「长边才是上限」。
      final ImageSize out = ImageCompressor.fitInside(const ImageSize(3000, 4000), 1024);
      expect(out, const ImageSize(768, 1024));
      expect(out.longSide, 1024);
    });

    test('不放大：长边本来就小于上限时原样返回', () {
      expect(
        ImageCompressor.fitInside(const ImageSize(400, 200), 1024),
        const ImageSize(400, 200),
      );
    });

    test('长宽永远不会被拉成同一个数（旧的 copyResize(width,height) 会）', () {
      final ImageSize out = ImageCompressor.fitInside(const ImageSize(1600, 200), 800);
      expect(out, const ImageSize(800, 100));
      expect(out.width, isNot(out.height));
    });
  });

  group('压缩入口 compress', () {
    test('Windows（无原生实现）不抛异常，走纯 Dart 且等比缩放', () async {
      final CompressedImage? out = await onPlatform(
        TargetPlatform.windows,
        () => ImageCompressor.compress(imageBytes(600, 300), maxSide: 150),
      );

      expect(ImageCompressor.nativePlatforms.contains(TargetPlatform.windows), isFalse);
      expect(out, isNotNull, reason: 'Windows 上必须能压出来（旧实现这里抛 UnimplementedError）');
      expect(out!.size, const ImageSize(150, 75));
      expect(ImageCompressor.probeSize(out.bytes), const ImageSize(150, 75));
    });

    test('Linux 同样走纯 Dart（同一类平台的另一处入口）', () async {
      final CompressedImage? out = await onPlatform(
        TargetPlatform.linux,
        () => ImageCompressor.compress(imageBytes(400, 400), maxSide: 100),
      );
      expect(out, isNotNull);
      expect(out!.size, const ImageSize(100, 100));
    });

    test('小图不放大', () async {
      final CompressedImage? out = await onPlatform(
        TargetPlatform.windows,
        () => ImageCompressor.compress(imageBytes(100, 80), maxSide: 1024),
      );
      expect(out, isNotNull);
      expect(out!.size, const ImageSize(100, 80));
    });

    test('GIF 返回 null（压成 JPEG 会丢逐帧动画，调用方保留原图）', () async {
      final CompressedImage? out = await onPlatform(
        TargetPlatform.windows,
        () => ImageCompressor.compress(imageBytes(64, 64, format: 'gif'), maxSide: 32),
      );
      expect(out, isNull);
    });

    test('不是图片的字节返回 null，而不是抛异常', () async {
      final CompressedImage? out = await onPlatform(
        TargetPlatform.windows,
        () => ImageCompressor.compress(Uint8List.fromList(<int>[1, 2, 3, 4]), maxSide: 64),
      );
      expect(out, isNull);
    });
  });

  group('调用点（导出角色卡）', () {
    test('Windows 上导出带图角色卡不再失败，图片等比缩放且声明为 JPEG', () async {
      final Directory dir = Directory.systemTemp.createTempSync('dna_export_test');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final File source = File('${dir.path}/square.png')
        ..writeAsBytesSync(imageBytes(1600, 800));

      final TA ta = TA(
        id: 'ta_export',
        name: '导出测试',
        gender: '女',
        persona: 'persona',
        intro: 'intro',
        opening: 'opening',
        tags: const <String>[],
        images: <String, String>{'square': source.path},
        dialogueStyle: const <DialogueTurn>[],
      );

      final ExportImportResult<String> result = await onPlatform(
        TargetPlatform.windows,
        () => TaExportImportService.exportCharacter(ta),
      );

      expect(result.success, isTrue, reason: '导出失败：${result.message}');

      final Map<String, dynamic> json = jsonDecode(result.data!) as Map<String, dynamic>;
      final Map<String, dynamic> character = json['character'] as Map<String, dynamic>;
      final Map<String, dynamic> square =
          (character['images'] as Map<String, dynamic>)['square'] as Map<String, dynamic>;

      // 默认 maxImageDimension = 1024：1600x800 → 1024x512（等比，不是 1024x1024）。
      expect(square['width'], 1024);
      expect(square['height'], 512);

      final String dataUri = square['data'] as String;
      expect(
        dataUri.startsWith('data:image/jpeg;base64,'),
        isTrue,
        reason: '压缩后字节是 JPEG，MIME 不能还按原文件扩展名（.png）声明：${dataUri.substring(0, 32)}',
      );

      final Uint8List exported = base64Decode(dataUri.split(',').last);
      expect(ImageCompressor.probeSize(exported), const ImageSize(1024, 512));
    });
  });

  group('唯一入口守卫', () {
    test('lib 下只有 image_compressor.dart 允许 import flutter_image_compress', () {
      const String entry = 'lib/services/image_compressor.dart';
      final List<String> offenders = <String>[];

      for (final File file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final String path = file.path.replaceAll('\\', '/');
        if (!path.endsWith('.dart') || path == entry) continue;
        for (final String line in file.readAsLinesSync()) {
          final String code = line.trim();
          if (!code.startsWith('import')) continue;
          if (code.contains('flutter_image_compress')) offenders.add('$path: $code');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: '图片压缩只能走 $entry（平台差异在那里判一次，别在调用点再判）：$offenders',
      );
    });
  });
}
