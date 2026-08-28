import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../services/image_storage.dart';

/// 聊天背景图组件：静态立绘 / GIF 动态背景（支持暂停首帧 / 继续播放）。
///
/// - 静态图片（非 GIF）：始终以 [BoxFit.cover] 铺满，忽略 [animate]。
/// - GIF 动态背景：当 [animate] 为 true 时用 [Image] 自动逐帧播放动画；
///   为 false（暂停）时手动解码第一帧并用 [RawImage] 静态显示，
///   真正停止 GIF 解码，避免持续耗电/占内存（默认状态即暂停第一帧）。
class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({
    super.key,
    required this.image,
    required this.path,
    required this.animate,
  });

  /// 图片 provider（FileImage / MemoryImage 等）。
  final ImageProvider image;

  /// 图片文件路径，用于判断是否为 GIF 及读取原始字节。
  final String path;

  /// 是否为动画播放状态（仅对 GIF 生效）。
  final bool animate;

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground> {
  bool get _isGif => widget.path.toLowerCase().endsWith('.gif');

  ui.Image? _firstFrame;

  @override
  void didUpdateWidget(covariant AnimatedBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    // GIF 文件或播放状态变化时，重置缓存的首帧（重新解码）。
    if (oldWidget.path != widget.path || oldWidget.animate != widget.animate) {
      _firstFrame = null;
    }
  }

  Future<void> _loadFirstFrame() async {
    if (!_isGif) return;
    if (_firstFrame != null) return;
    final bytes = await ImageStorage.instance.readBytes(widget.path);
    if (bytes == null || bytes.isEmpty) return;
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        _firstFrame = frame.image;
      });
    } catch (_) {
      // 解码失败：回退为普通 Image 显示。
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isGif) {
      // 静态立绘
      return Image(image: widget.image, fit: BoxFit.cover);
    }
    if (widget.animate) {
      // 播放 GIF 动画
      return Image(image: widget.image, fit: BoxFit.cover);
    }
    // 暂停：显示第一帧（静态）
    if (_firstFrame != null) {
      return RawImage(
        image: _firstFrame,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    // 首帧尚未解码：触发异步解码，期间回退为普通 Image 显示首帧
    _loadFirstFrame();
    return Image(image: widget.image, fit: BoxFit.cover, frameBuilder: (context, child, frame, wasSync) {
      // 动画解码中：始终显示第 0 帧（首帧），避免跳动
      if (frame == null || frame == 0) {
        return child;
      }
      return const SizedBox.shrink();
    });
  }
}
