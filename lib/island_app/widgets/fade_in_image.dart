import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 网络图片"模糊 → 清晰"渐显动画，对齐网页版 `.dna-img-fade` 的实现。
///
/// 加载期间展示 [placeholder]（纯色块）；图片解码完成后，以较长曲线让图片
/// 从**高斯模糊 + 半透明 + 轻微放大** 平滑过渡到**清晰完整**（模糊散去、淡入、
/// 缩放归位，曲线刻意拉长，消除硬切）。
class FadeInNetworkImage extends StatefulWidget {
  const FadeInNetworkImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.fit,
    this.cacheWidth,
    this.alignment = Alignment.center,
  });

  final String url;

  /// 加载中/失败时的占位组件。
  final Widget placeholder;

  final BoxFit? fit;

  /// 解码宽度（配合 cacheWidth 降低解码内存，避免卡顿）。
  final int? cacheWidth;

  /// 图片在绘制框内的对齐方式（配合 `BoxFit.cover` 实现封面焦点定位）。
  final Alignment alignment;

  @override
  State<FadeInNetworkImage> createState() => _FadeInNetworkImageState();
}

class _FadeInNetworkImageState extends State<FadeInNetworkImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;

  @override
  void initState() {
    super.initState();
    // 在 initState 中主动创建，避免用 late 延迟到 dispose 才初始化导致崩溃。
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _resolve();
  }

  @override
  void didUpdateWidget(FadeInNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.cacheWidth != widget.cacheWidth) {
      _teardown();
      _resolve();
    }
  }

  void _resolve() {
    ImageProvider provider = NetworkImage(widget.url);
    // 按目标宽度解码，降低内存占用与解码耗时。
    if (widget.cacheWidth != null) {
      provider = ResizeImage(provider, width: widget.cacheWidth);
    }
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted) {
          info.dispose();
          return;
        }
        setState(() {
          _info?.dispose();
          _info = info;
        });
        _controller.forward(from: 0);
      },
      onError: (error, stackTrace) {
        // 失败时保持占位，无需额外标记。
      },
    );
    _listener = listener;
    _stream = provider.resolve(ImageConfiguration.empty)..addListener(listener);
  }

  void _teardown() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
    _info?.dispose();
    _info = null;
    _controller.value = 0;
  }

  @override
  void dispose() {
    _teardown();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    // 解码成功后才叠加"模糊 → 清晰"动画层；否则只显示占位色块。
    final Widget? image;
    if (info != null) {
      // 分层缓动：模糊散去（慢）与淡入、缩放错峰收尾，模拟网页版效果。
      final curve = Curves.easeOutCubic;
      image = AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = CurvedAnimation(
            parent: _controller,
            curve: curve,
          ).value; // 0..1
          final blur = 18.0 * (1 - t);
          final opacity = t;
          final scale = 1.05 - 0.05 * t;
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                ),
                child: child,
              ),
            ),
          );
        },
        child: RawImage(
          image: info.image,
          fit: widget.fit,
          alignment: widget.alignment,
          filterQuality: FilterQuality.medium,
        ),
      );
    } else {
      image = null;
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.placeholder,
        // 加载中：原生转圈动画（图片解码完成前显示）。
        if (info == null)
          const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ?image,
      ],
    );
  }
}
