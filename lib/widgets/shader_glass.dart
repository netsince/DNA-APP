import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import 'glass_quality.dart';
import 'liquid_glass.dart';

/// Paint.shader 版液态玻璃。
///
/// 与 [LiquidGlass]（纯几何高光）的区别：它采样**真实后景纹理**，在边缘按圆弧截面
/// 做位移，并按七通道（红/橙/黄/绿/青/蓝/紫）分离采样后重组——所以背景真的被掰弯，
/// 边缘也会出现色散，而不是画几圈渐变。
///
/// 依赖：
/// * 后景纹理：祖先 [GlassBackdrop] 以约 15fps 抓取（0.5× 分辨率）；
/// * `shaders/liquid_glass.frag`，在 pubspec 的 `flutter: shaders:` 注册。
///
/// 缺任一项、或画质不是「高」时，自动回退几何版，界面不会变空白。
class ShaderGlass extends StatefulWidget {
  const ShaderGlass({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.tint = Colors.white,
    this.tintAlpha = 0.06,
    this.bevel = 14,
    this.amount = 9,
    this.dispersion = 0.6,
    this.specular = 0.8,
    this.padding = EdgeInsets.zero,
    this.fill,
    this.fallbackIntensity = 1,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color tint;
  final double tintAlpha;
  final double bevel;
  final double amount;
  final double dispersion;
  final double specular;
  final EdgeInsetsGeometry padding;
  final Color? fill;
  final double fallbackIntensity;

  @override
  State<ShaderGlass> createState() => _ShaderGlassState();
}

class _ShaderGlassState extends State<ShaderGlass> {
  static ui.FragmentProgram? _program;
  static bool _programTried = false;

  /// 本控件在纹理空间里的左上角（逻辑像素）。
  final ValueNotifier<Offset> _origin = ValueNotifier<Offset>(Offset.zero);

  @override
  void initState() {
    super.initState();
    _ensureProgram();
    GlassQualityStore.instance.addListener(_onQuality);
    _scheduleOriginUpdate();
  }

  @override
  void dispose() {
    GlassQualityStore.instance.removeListener(_onQuality);
    _origin.dispose();
    super.dispose();
  }

  void _onQuality() {
    if (mounted) setState(() {});
  }

  Future<void> _ensureProgram() async {
    if (_programTried) return;
    _programTried = true;
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
    } catch (_) {
      _program = null;
      GlassQualityStore.instance.markShaderUnavailable();
    }
    if (mounted) setState(() {});
  }

  void _scheduleOriginUpdate() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderObject? ro = context.findRenderObject();
      final Offset? base = GlassBackdrop.of(context)?.globalOffset;
      if (ro is RenderBox && base != null && ro.hasSize) {
        _origin.value = ro.localToGlobal(Offset.zero) - base;
      }
      _scheduleOriginUpdate();
    });
  }

  Widget _fallback() => LiquidGlass(
        borderRadius: widget.borderRadius,
        tint: widget.tint,
        fill: widget.fill,
        intensity: widget.fallbackIntensity,
        padding: widget.padding,
        child: widget.child,
      );

  @override
  Widget build(BuildContext context) {
    final GlassQuality quality = GlassQualityStore.instance.effective;
    final GlassBackdropState? backdrop = GlassBackdrop.of(context);
    final ui.Image? image = backdrop?.image.value;

    if (quality != GlassQuality.high || _program == null || image == null) {
      return _fallback();
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: CustomPaint(
        painter: _ShaderGlassPainter(
          shader: _program!.fragmentShader(),
          image: image,
          origin: _origin,
          borderRadius: widget.borderRadius,
          tint: widget.tint,
          tintAlpha: widget.tintAlpha,
          bevel: widget.bevel,
          amount: widget.amount,
          dispersion: widget.dispersion,
          specular: widget.specular,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
        child: Padding(padding: widget.padding, child: widget.child),
      ),
    );
  }
}

class _ShaderGlassPainter extends CustomPainter {
  _ShaderGlassPainter({
    required this.shader,
    required this.image,
    required this.origin,
    required this.borderRadius,
    required this.tint,
    required this.tintAlpha,
    required this.bevel,
    required this.amount,
    required this.dispersion,
    required this.specular,
    required this.dark,
  });

  final ui.FragmentShader shader;
  final ui.Image image;
  final ValueNotifier<Offset> origin;
  final BorderRadius borderRadius;
  final Color tint;
  final double tintAlpha;
  final double bevel;
  final double amount;
  final double dispersion;
  final double specular;
  final bool dark;

  static const double _kCaptureScale = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Offset o = origin.value;

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, image.width.toDouble())
      ..setFloat(3, image.height.toDouble())
      ..setFloat(4, o.dx * _kCaptureScale)
      ..setFloat(5, o.dy * _kCaptureScale)
      ..setFloat(6, _kCaptureScale)
      ..setFloat(7, borderRadius.topLeft.x)
      ..setFloat(8, bevel)
      ..setFloat(9, amount)
      ..setFloat(10, dispersion)
      ..setFloat(11, specular)
      ..setFloat(12, tintAlpha)
      ..setFloat(13, dark ? 1.0 : 0.0)
      // 采样 y 上限：玻璃自身的上沿以下一格之外不再采，避免把自己画进自己
      ..setFloat(14, (o.dy + size.height - 1.0) * _kCaptureScale)
      ..setFloat(15, tint.r)
      ..setFloat(16, tint.g)
      ..setFloat(17, tint.b)
      ..setFloat(18, tint.a)
      ..setImageSampler(0, image);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _ShaderGlassPainter old) =>
      old.image != image ||
      old.tint != tint ||
      old.amount != amount ||
      old.bevel != bevel ||
      old.dispersion != dispersion ||
      old.specular != specular;
}
