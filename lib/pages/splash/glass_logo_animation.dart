import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:flutter/scheduler.dart';

import 'glass_logo_choreography.dart';
import 'splash_clock.dart';
import 'logo_painter.dart';

/// 液态玻璃用的 logo 纹理资源（白色墨、透明底、512²）。
const String kGlassLogoAsset = 'assets/splash/dna_logo.png';

/// 液态玻璃 logo 开场动画（移植自 reactdrops 的 liquid-glass-logo，MIT）。
///
/// 渲染路径：LogoPainter 先栅格成一张纹理 → 每帧把「时间 + 编排算出的 uniform」
/// 喂给 `shaders/glass_logo.frag` → 在画布上铺一层带 shader 的矩形。
///
/// 与 React 版的差别都写在 shader 文件头（单 pass、12 档光谱、无 wordmark），
/// 动画节奏（五条关键帧曲线）原样保留。
class GlassLogoAnimation extends StatefulWidget {
  const GlassLogoAnimation({
    super.key,
    required this.durationMs,
    required this.onComplete,
    this.tuning = const GlassLogoTuning(),
  });

  /// 测试用：跳过「等首帧上屏」这道闸。
  ///
  /// 测试环境不派发 FrameTiming 回调，靠着色器/纹理走完就永远等不到动画开始；
  /// 生产路径必须保留这道闸（它决定窗口什么时候出现）。
  @visibleForTesting
  static bool debugSkipFirstFrameGate = false;

  final int durationMs;
  final VoidCallback onComplete;
  final GlassLogoTuning tuning;

  @override
  State<GlassLogoAnimation> createState() => _GlassLogoAnimationState();
}

class _GlassLogoAnimationState extends State<GlassLogoAnimation>
    with SingleTickerProviderStateMixin {
  static ui.FragmentProgram? _program;

  late final SplashClock _clock = SplashClock(
    vsync: this,
    duration: Duration(milliseconds: widget.durationMs),
  );

  /// logo 纹理：只栅格一次（换绑定/尺寸才重画）。
  ui.Image? _logo;
  bool _imageLoading = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// 等「着色器 + logo 纹理」都就绪才开播。
  ///
  /// 以前是对着空白先起播：前两三百毫秒在编译着色器 / 栅格 logo，用户看到的是
  /// 一段"什么都没有"，然后动画突然跳进来 —— 这就是「一瞬间压根看不见」的来源。
  Future<void> _boot() async {
    // 等首帧真正上屏再做这两件事：实测它们各自会把首帧卡住约 6 秒
    //（Impeller-GLES 上首次建着色器管线 / 解码并上传纹理），而窗口是首帧上屏后
    // 才 Show 的。endOfFrame 不够，它在「本帧画完」就返回，仍在首帧上屏之前。
    await _firstFramePresented();
    await Future.wait<void>(<Future<void>>[_loadProgram(), _rasterizeLogo()]);
    if (!mounted) return;
    // 就绪后再起钟，而且等首帧真正上屏才走时间：第一次绘制要建着色器管线，
    // 那一帧可能几百毫秒 —— 之前正是它把动画开头吃掉了。
    setState(() {});
    _clock.startAfterFirstFrame(onComplete: widget.onComplete);
  }

  /// 等到「首帧被真正合成上屏」。
  ///
  /// 主路径靠 FrameTiming（回调代表已经上屏的帧）；再加一条「三帧兜底」，
  /// 因为测试环境（以及某些后端）不会派发 timings 回调，否则动画永远不开始。
  Future<void> _firstFramePresented() async {
    if (_firstFrameSeen || GlassLogoAnimation.debugSkipFirstFrameGate) return;
    final Completer<void> done = Completer<void>();
    late final TimingsCallback callback;
    void finish() {
      if (done.isCompleted) return;
      _firstFrameSeen = true;
      done.complete();
    }

    callback = (List<FrameTiming> timings) => finish();
    WidgetsBinding.instance.addTimingsCallback(callback);
    unawaited(() async {
      for (int i = 0; i < 3; i++) {
        await WidgetsBinding.instance.endOfFrame;
      }
      finish();
    }());
    await done.future;
    WidgetsBinding.instance.removeTimingsCallback(callback);
  }
  static bool _firstFrameSeen = false;

  Future<void> _loadProgram() async {
    if (_program != null) return;
    try {
      final ui.FragmentProgram program =
          await ui.FragmentProgram.fromAsset('shaders/glass_logo.frag');
      _program = program;
      if (mounted) setState(() {});
    } catch (e) {
      // 着色器加载失败（极端平台/降级构建）：直接播完，不要卡在空白上。
      debugPrint('[glass-logo] 着色器加载失败，跳过动画: $e');
      _clock.finishNow();
    }
  }

  /// logo 纹理：随包发布的 PNG（由 tool/generate_logo_png.dart 生成）。
  ///
  /// 以前是运行时用 Picture 现画一张 512² 图，再转成 ui.Image —— 那条路在
  /// Impeller-GLES 上会把首帧卡住约 6 秒（实测窗口 2.6s → 9.4s），而它只是一张
  /// 静态图。改成资源解码后就是一次普通图片加载。
  Future<void> _rasterizeLogo() async {
    if (_imageLoading) return;
    _imageLoading = true;
    try {
      final ByteData data = await rootBundle.load(kGlassLogoAsset);
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _logo?.dispose();
        _logo = frame.image;
      });
    } catch (e) {
      debugPrint('[glass-logo] logo 资源加载失败: $e');
    }
  }
  @override
  void dispose() {
    _clock.dispose();
    _logo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.FragmentProgram? program = _program;
    if (program == null || _logo == null) {
      // 还没就绪：先画一枚静态 logo（Painter 很快），别让用户盯着黑屏等。
      return SizedBox(
        width: widget.tuning.logoSize * 0.72,
        height: widget.tuning.logoSize * 0.72,
        child: CustomPaint(
          painter: LogoPainter(drawProgress: 1, fillProgress: 1),
        ),
      );
    }
    return SizedBox(
      width: widget.tuning.logoSize * 1.25,
      height: widget.tuning.logoSize * 1.25,
      child: CustomPaint(
        painter: _GlassLogoPainter(
          program: program,
          animation: _clock,
          tuning: widget.tuning,
          logo: _logo,
          durationSeconds: widget.durationMs / 1000,
        ),
      ),
    );
  }
}

class _GlassLogoPainter extends CustomPainter {
  _GlassLogoPainter({
    required this.program,
    required this.animation,
    required this.tuning,
    required this.logo,
    required this.durationSeconds,
  }) : super(repaint: animation);

  final ui.FragmentProgram program;
  final SplashClock animation;
  final GlassLogoTuning tuning;
  final ui.Image? logo;
  final double durationSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? texture = logo;
    if (texture == null) return;
    final double dpr =
        SchedulerBinding.instance.platformDispatcher.views.first
                .devicePixelRatio;
    final ui.FragmentShader shader = program.fragmentShader();
    final double t = animation.value * durationSeconds;
    final GlassLogoFrame frame = glassLogoFrameAt(
      t,
      unitPx: tuning.unitPx,
      finalLogoScale: tuning.finalLogoScale,
      dropStrength: tuning.dropStrength,
      showDrop: tuning.showDrop,
    );
    final double w = size.width;
    final double h = size.height;
    final List<double> floats = <double>[
      // uResolution
      w * dpr,
      h * dpr,
      // uDpr
      dpr,
      // uUnit
      tuning.unitPx,
      // uLogoBox
      tuning.logoSize * tuning.logoScale,
      tuning.logoSize * tuning.logoScale,
      // uLogoTexSize
      texture.width.toDouble(),
      texture.height.toDouble(),
      // uTime / uSettle / uArtScale
      frame.time,
      frame.settle,
      frame.artScale,
      // uTile
      tuning.tileColor.r,
      tuning.tileColor.g,
      tuning.tileColor.b,
      // uTileEnabled / uPageLight
      tuning.tileEnabled ? 1 : 0,
      _pageLight(tuning.background),
      // uDepth / uDispersion / uRelief / uCaustics / uHighlights / uEchoTint /
      // uInnerWallFocus / uDropSize / uDropStrength / uDecay
      tuning.depth,
      tuning.dispersion,
      tuning.relief,
      tuning.caustics,
      tuning.highlights,
      tuning.echoTint,
      tuning.innerWallFocus,
      tuning.dropSize,
      tuning.dropStrength,
      tuning.decay,
      // uDrop / uDropLens / uDropWave
      ...frame.drop,
      ...frame.dropLens,
      ...frame.dropWave,
      // uBloom / uDropOpacity
      tuning.bloom,
      frame.dropOpacity,
    ];
    for (int i = 0; i < floats.length; i++) {
      shader.setFloat(i, floats[i]);
    }
    shader.setImageSampler(0, texture);
    final Paint paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
    shader.dispose();
  }

  /// 背景亮度：原实现用 luminance 判断「深底/浅底」，决定底板是渐深还是融进页面。
  static double _pageLight(Color background) {
    return (0.299 * background.r + 0.587 * background.g + 0.114 * background.b)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  @override
  bool shouldRepaint(_GlassLogoPainter old) =>
      old.logo != logo ||
      old.program != program ||
      old.tuning != tuning ||
      old.durationSeconds != durationSeconds;
}
