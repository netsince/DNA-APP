import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dna/pages/splash/logo_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 生成开场动画用的 logo 纹理（白色墨、透明底、512×512）。
///
/// 为什么要预渲染：运行时用 Picture -> Image 现画一张 512² 纹理，在
/// Impeller-GLES 上会把首帧卡住约 6 秒（实测窗口 2.6s → 9.4s），而那只是一张
/// 静态图。改成随包发布的 PNG 后就只是一次普通解码。
///
/// 跑法：flutter test tool/generate_logo_png.dart
void main() {
  testWidgets('生成 assets/splash/dna_logo.png', (WidgetTester tester) async {
    const int px = 512;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    LogoPainter(drawProgress: 1, fillProgress: 1).paint(
      canvas,
      const Size(512, 512),
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(px, px);
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    expect(data, isNotNull);
    final Directory dir = Directory('assets/splash');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final File out = File('assets/splash/dna_logo.png');
    out.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('已写入 ' + out.path + ' (' + out.lengthSync().toString() + ' 字节)');
    image.dispose();
    picture.dispose();
  });
}
