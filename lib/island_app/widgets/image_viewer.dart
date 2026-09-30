import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 基于生态名库 [extended_image] 构建的高品质全屏图片查看器。
///
/// 特性：
/// - 采用 [ExtendedImageSlidePage] 实现与微信/小红书完全一致的手势滑动拖拽退出
/// - 采用 [ExtendedImageGesturePageView] 解决多图切换与单图放大的手势冲突
/// - 支持 Hero 动画双向过度
/// - 支持双击手势点按放大/复原
/// - 沉浸式透明 UI 工具栏（单击切换显隐、复制链接功能）
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.heroTag,
  });

  /// 单图快捷构造。
  factory ImageViewerPage.single({
    Key? key,
    required String url,
    String? heroTag,
  }) {
    return ImageViewerPage(
      key: key,
      urls: <String>[url],
      initialIndex: 0,
      heroTag: heroTag,
    );
  }

  final List<String> urls;
  final int initialIndex;
  final String? heroTag;

  /// 静态打开方法。
  static void open(
    BuildContext context, {
    required List<String> urls,
    int initialIndex = 0,
    String? heroTag,
  }) {
    if (urls.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, animation, secondaryAnimation) {
          return ExtendedImageSlidePage(
            slidePageBackgroundHandler: (offset, pageSize) {
              final double opacity =
                  1.0 - (offset.dy.abs() / pageSize.height).clamp(0.0, 1.0);
              return Colors.black.withValues(alpha: opacity);
            },
            slideType: SlideType.wholePage,
            slideAxis: SlideAxis.both,
            child: ImageViewerPage(
              urls: urls,
              initialIndex: initialIndex,
              heroTag: heroTag,
            ),
          );
        },
      ),
    );
  }

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late ExtendedPageController _pageController;
  late int _currentIndex;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pageController = ExtendedPageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _copyUrl() {
    final url = widget.urls[_currentIndex];
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制图片链接'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: <Widget>[
            // 核心 ExtendedImageGesturePageView 手势画廊
            ExtendedImageGesturePageView.builder(
              controller: _pageController,
              itemCount: widget.urls.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                final url = widget.urls[index];
                final isHero = index == widget.initialIndex &&
                    widget.heroTag != null;

                Widget item = ExtendedImage.network(
                  url,
                  fit: BoxFit.contain,
                  mode: ExtendedImageMode.gesture,
                  enableSlideOutPage: true,
                  initGestureConfigHandler: (state) {
                    return GestureConfig(
                      minScale: 0.9,
                      animationMinScale: 0.7,
                      maxScale: 4.0,
                      animationMaxScale: 4.5,
                      speed: 1.0,
                      inertialSpeed: 100.0,
                      initialScale: 1.0,
                      inPageView: true,
                      initialAlignment: InitialAlignment.center,
                    );
                  },
                  onDoubleTap: (ExtendedImageGestureState state) {
                    final pointerDownPosition = state.pointerDownPosition;
                    final double? currentScale = state.gestureDetails?.totalScale;
                    if (currentScale != null && currentScale > 1.2) {
                      state.reset();
                    } else {
                      state.handleDoubleTap(
                        scale: 2.5,
                        doubleTapPosition: pointerDownPosition,
                      );
                    }
                  },
                  loadStateChanged: (ExtendedImageState state) {
                    switch (state.extendedImageLoadState) {
                      case LoadState.loading:
                        final loadingProgress = state.loadingProgress;
                        final double? progress =
                            loadingProgress?.expectedTotalBytes != null
                                ? loadingProgress!.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null;
                        return Center(
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 2.5,
                              color: Colors.white70,
                            ),
                          ),
                        );
                      case LoadState.failed:
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const <Widget>[
                              Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white38,
                                size: 64,
                              ),
                              SizedBox(height: 12),
                              Text(
                                '图片加载失败',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      case LoadState.completed:
                        return null;
                    }
                  },
                );

                if (isHero) {
                  item = Hero(
                    tag: widget.heroTag!,
                    child: item,
                  );
                }
                return item;
              },
            ),

            // 顶部沉浸式 AppBar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              top: _showControls ? 0 : -100,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        if (widget.urls.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_currentIndex + 1} / ${widget.urls.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(
                            Icons.link_rounded,
                            color: Colors.white,
                          ),
                          tooltip: '复制链接',
                          onPressed: _copyUrl,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 底部提示栏
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              bottom: _showControls ? 0 : -80,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: const SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        '双击放大 · 下滑拖拽退出',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
