import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'crop_math.dart';

/// 纯 Flutter 裁剪页（桌面端 / 没有原生裁剪器的平台用）。
///
/// 交互：拖动平移、双指/滚轮缩放；裁剪框固定居中且锁定比例（[aspect] 为 null 时自由）。
/// 返回裁剪后的 PNG 字节；用户取消返回 null。
///
/// 为什么不用 image_cropper：它只实现了 Android / iOS / Web，桌面端没有实现。
Future<Uint8List?> showFlutterCropPage(
  BuildContext context, {
  required Uint8List source,
  required double? aspect,
  String title = '裁剪图片',
}) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute<Uint8List>(
      builder: (BuildContext _) => FlutterCropPage(
        source: source,
        aspect: aspect,
        title: title,
      ),
    ),
  );
}

class FlutterCropPage extends StatefulWidget {
  const FlutterCropPage({
    super.key,
    required this.source,
    required this.aspect,
    this.title = '裁剪图片',
  });

  final Uint8List source;

  /// 锁定的宽高比；null 表示自由（按整图输出）。
  final double? aspect;

  final String title;

  @override
  State<FlutterCropPage> createState() => _FlutterCropPageState();
}

class _FlutterCropPageState extends State<FlutterCropPage> {
  ui.Image? _image;
  Object? _error;

  /// 相对「铺满视口」的额外缩放（1.0 起）。
  double _zoom = 1.0;
  Offset _pan = Offset.zero;

  /// 视口尺寸与裁剪框（屏幕坐标）。
  Size _viewport = Size.zero;
  Rect _cropRect = Rect.zero;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  /// 解码并把长边限制在 2048，避免 4K 图直接吃满内存。
  Future<void> _decode() async {
    try {
      final ui.ImmutableBuffer buffer =
          await ui.ImmutableBuffer.fromUint8List(widget.source);
      final ui.ImageDescriptor desc =
          await ui.ImageDescriptor.encoded(buffer);
      final int longSide = desc.width > desc.height ? desc.width : desc.height;
      final int target = longSide > 2048 ? 2048 : longSide;
      final ui.Codec codec = await desc.instantiateCodec(
        targetWidth: desc.width >= desc.height ? target : null,
        targetHeight: desc.height > desc.width ? target : null,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _image = frame.image);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// 图像当前缩放（把图片「铺满」视口后再乘 _zoom）。
  double get _scale {
    final ui.Image? image = _image;
    if (image == null || _viewport.isEmpty) return 1;
    final double cover = _max(
      _viewport.width / image.width,
      _viewport.height / image.height,
    );
    return cover * _zoom;
  }

  static double _max(double a, double b) => a > b ? a : b;

  /// 把平移量限制在「图片始终盖住裁剪框」的范围内。
  Offset _clampPan(Offset pan, double scale) {
    final ui.Image? image = _image;
    if (image == null) return Offset.zero;
    final double dw = image.width * scale;
    final double dh = image.height * scale;
    final double minDx = _cropRect.right - dw;
    final double maxDx = _cropRect.left;
    final double minDy = _cropRect.bottom - dh;
    final double maxDy = _cropRect.top;
    return Offset(
      pan.dx.clamp(minDx, maxDx),
      pan.dy.clamp(minDy, maxDy),
    );
  }

  /// 按视口与比例算出居中裁剪框。
  Rect _computeCropRect() => computeCropRect(_viewport, widget.aspect);

  /// 屏幕裁剪框 → 图片像素矩形。
  Rect _sourceRect() {
    final ui.Image image = _image!;
    final double s = _scale;
    final double left = (_cropRect.left - _pan.dx) / s;
    final double top = (_cropRect.top - _pan.dy) / s;
    final double w = _cropRect.width / s;
    final double h = _cropRect.height / s;
    return Rect.fromLTWH(
      left.clamp(0.0, image.width - 1.0),
      top.clamp(0.0, image.height - 1.0),
      w.clamp(1.0, image.width.toDouble()),
      h.clamp(1.0, image.height.toDouble()),
    );
  }

  Future<void> _confirm() async {
    final ui.Image? image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    final Rect src = _sourceRect();
    // 输出尺寸：长边不超过 1600，且保持比例（服务端按比例校验）。
    final ({int width, int height}) size = outputSizeFor(src);
    final int outW = size.width;
    final int outH = size.height;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image out = await picture.toImage(outW, outH);
    final ByteData? data =
        await out.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.of(context).pop(data?.buffer.asUint8List());
  }

  /// 鼠标滚轮 / 触控板双指滚动：以光标为中心缩放。
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final double dy = event.scrollDelta.dy;
    if (dy == 0) return;
    setState(() {
      final double oldZoom = _zoom;
      _zoom = (_zoom * (dy > 0 ? 0.9 : 1.1)).clamp(1.0, 6.0);
      if (_zoom == oldZoom) return;
      // 保持光标下的那张图不动：newPan = focal - (focal - pan) * factor
      final double factor = _zoom / oldZoom;
      final Offset focal = event.localPosition;
      _pan = _clampPan(focal - (focal - _pan) * factor, _scale);
    });
  }

  @override
  void dispose() {
    // 释放解码出来的图（RawImage 不接管所有权）。
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _confirm,
            child: Text(
              _saving ? '处理中…' : '确定',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_error != null) {
      return Center(
        child: Text(
          '这张图片无法读取，请换一张',
          style: TextStyle(color: cs.error),
        ),
      );
    }
    final ui.Image? image = _image;
    if (image == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final Size viewport = Size(c.maxWidth, c.maxHeight);
        if (viewport != _viewport) {
          _viewport = viewport;
          _cropRect = _computeCropRect();
          _pan = _clampPan(_pan, _scale);
        }
        final double s = _scale;
        return GestureDetector(
          onScaleStart: (_) {},
          onScaleUpdate: (ScaleUpdateDetails d) {
            setState(() {
              if (d.scale != 1.0) {
                _zoom = (_zoom * d.scale).clamp(1.0, 6.0);
              }
              _pan = _clampPan(_pan + d.focalPointDelta, _scale);
            });
          },
          child: Listener(
            onPointerSignal: _handlePointerSignal,
            child: Stack(
              fit: StackFit.expand,
            children: <Widget>[
              Positioned(
                left: _pan.dx,
                top: _pan.dy,
                width: image.width * s,
                height: image.height * s,
                // 用 RawImage 直接画已解码的 ui.Image：不走 ImageCache，避免被缓存 dispose 后再 clone。
                child: RawImage(
                  image: image,
                  fit: BoxFit.fill,
                  width: image.width * s,
                  height: image.height * s,
                ),
              ),
              // 裁剪框外的遮罩 + 边框
              IgnorePointer(
                child: CustomPaint(
                  painter: _CropOverlayPainter(crop: _cropRect),
                ),
              ),
            ],
            ),
          ),
        );
      },
    );
  }

}


/// 裁剪框外的压暗遮罩 + 边框 + 三分线。
class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({required this.crop});

  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final Path outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(crop)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawRect(
      crop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    final Paint grid = Paint()
      ..strokeWidth = 0.5
      ..color = Colors.white54;
    for (int i = 1; i < 3; i++) {
      final double dx = crop.left + crop.width * i / 3;
      final double dy = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(dx, crop.top), Offset(dx, crop.bottom), grid);
      canvas.drawLine(Offset(crop.left, dy), Offset(crop.right, dy), grid);
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) => old.crop != crop;
}

