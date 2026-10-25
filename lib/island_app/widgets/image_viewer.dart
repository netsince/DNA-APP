import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'drag_scroll_behavior.dart';
import '../utils/save_image.dart';
import '../../theme/tokens.dart';

/// 基于生态名库 [extended_image] 构建的高品质全屏图片查看器。
///
/// 特性：
/// - 下滑拖拽退出（自带的 [_VerticalDismiss]：**只认纵向占优的拖拽**，
///   横向滑动完整留给画廊翻页 —— 不再用包里的 `ExtendedImageSlidePage`，
///   原因见文件末尾那段说明）
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
          // 套一层 DragScrollBehavior：画廊本身是个 PageView，电脑版上不放开
          // 鼠标拖拽的话鼠标根本翻不动图（与「刷一刷」同一个坑）。
          //
          // 退出层不在这里：由 ImageViewerPage 自己包（见 _VerticalDismiss），
          // 因为"这次拖拽该不该退出"要看画廊当前的缩放比例，而那个状态在页面内部。
          return ScrollConfiguration(
            behavior: const DragScrollBehavior(),
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

  /// 正在保存：避免连点弹出多个系统保存对话框。
  bool _saving = false;

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

  /// 保存当前这张为 PNG（系统「保存到…」对话框，Android 默认落到 Download，
  /// 相册/文件应用都能看到；不再把 WebP 塞进临时目录让用户找不着）。
  Future<void> _saveCurrent() async {
    if (_saving || widget.urls.isEmpty) return;
    setState(() => _saving = true);
    await saveImageAsPng(
      context,
      url: widget.urls[_currentIndex],
      baseName: 'DNAISLAND_图片_${_currentIndex + 1}',
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // 退出层：**只接受「纵向占优」的拖拽**，横向滑动一律让给画廊翻页。
      // 详见文件末尾 _VerticalDismiss 的说明。
      body: _VerticalDismiss(
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
                  // 关掉包自带的「拖拽出页」：它由图片自身的 ScaleGestureRecognizer
                  // 驱动（任意方向、36px 就接管），会和画廊的横向翻页识别器抢手势 ——
                  // 斜着滑时退出逻辑赢，画面被上下拽着走、图也切不了（用户反馈）。
                  // 退出改由外层 _VerticalDismiss 负责。
                  enableSlideOutPage: false,
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
                                  fontSize: AppFontSize.caption,
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
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                          ),
                          tooltip: '保存为 PNG',
                          onPressed: _saveCurrent,
                        ),
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
                          fontSize: AppFontSize.caption,
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

/// 图片查看器的「拖拽退出」层：**只接受「纵向占优」的拖拽**。
///
/// ## 为什么不用 extended_image 自带的 `ExtendedImageSlidePage`
///
/// 包里的退出手势是「图片自身的 `ScaleGestureRecognizer`」驱动的：它**任意方向**
/// 都能接管（focalPoint 位移超过 36px 即接受），而画廊翻页用的是横向识别器
/// （横向 18px 即接受）。同一根手指上两者抢手势，斜着滑时退出逻辑经常先赢：
/// 画面被上下拽着走、翻页也被吞掉 —— 就是用户反馈的「左右滑动时被上下滑动的
/// 退出动作影响」。`slideAxis: SlideAxis.vertical` 只能约束"位移只累计 dy"，
/// **抢手势它管不了**（上一轮没修干净的原因）。
///
/// ## 现在怎么做
///
/// * 用 [_VerticalDismissRecognizer]：纵向位移**明显占优**（≥ 横向 1.2 倍）才接受，
///   否则拒绝自己 —— 横向滑动因此完整留给画廊的翻页识别器；
/// * 图片被放大（scale > 1）时也拒绝自己：那时纵向拖拽应该归图片平移；
/// * 松手按包内同款阈值决定去留：|dy| > 屏幕高/6 或甩速 > 700 则退出，否则回弹；
/// * 背景透明度随位移线性淡出（与原来一致）。
class _VerticalDismiss extends StatefulWidget {
  const _VerticalDismiss({required this.child, required this.onTap});

  final Widget child;

  /// 单击（切换工具栏显隐）。
  final VoidCallback onTap;

  @override
  State<_VerticalDismiss> createState() => _VerticalDismissState();
}

class _VerticalDismissState extends State<_VerticalDismiss>
    with SingleTickerProviderStateMixin {
  /// 甩出速度阈值（px/s）：位移不够但甩得够快也退出。
  static const double _flingVelocity = 700;

  /// 位移阈值：屏幕高的 1/6（与包内 `defaultSlideEndHandler` 同款）。
  static const double _distanceRatio = 6;

  double _dy = 0;
  Offset? _start;

  /// 本次手势是否被判为「横向占优」：是则退出层全程不参与。
  bool _horizontal = false;
  bool _popping = false;
  double _settleFrom = 0;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => setState(() => _dy = _settleFrom * (1 - _settle.value)));

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  /// 当前图片是否处于放大状态（放大时纵向拖拽应归图片平移，不退出）。
  ///
  /// 为什么要走元素树找画廊 State：包里的 `ExtendedImageGesturePageView` 会把
  /// `key` 原样再传给内层 `GesturePageView`（其 build 里就是 `key: widget.key`），
  /// 同一个 GlobalKey 落在两个 widget 上会直接断言崩溃
  /// （"Multiple widgets used the same GlobalKey"，实测过），所以没法用 GlobalKey
  /// 拿 State。这里每次手势判定只查一次，开销可忽略。
  bool _isZoomed() {
    final ExtendedImageGesturePageViewState? state = _findGalleryState(context);
    final double scale =
        state?.extendedImageGestureState?.gestureDetails?.totalScale ?? 1.0;
    return scale > 1.01;
  }

  static ExtendedImageGesturePageViewState? _findGalleryState(
    BuildContext context,
  ) {
    ExtendedImageGesturePageViewState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement &&
          element.state is ExtendedImageGesturePageViewState) {
        found = element.state as ExtendedImageGesturePageViewState;
        return;
      }
      element.visitChildren(visit);
    }

    if (context is Element) {
      context.visitChildren(visit);
    }
    return found;
  }

  void _onStart(DragStartDetails details) {
    _settle.stop();
    _start = details.globalPosition;
    _horizontal = false;
  }

  void _onUpdate(DragUpdateDetails details) {
    final Offset start = _start ?? details.globalPosition;
    final Offset delta = details.globalPosition - start;
    // 方向占优：横向位移不亚于纵向 ⇒ 这是「切图」手势，退出层一律不参与。
    final bool horizontal = delta.dx.abs() >= delta.dy.abs();
    setState(() {
      _horizontal = horizontal;
      _dy = horizontal ? 0 : delta.dy;
    });
  }

  void _onEnd(DragEndDetails details) {
    final double height = MediaQuery.sizeOf(context).height;
    final double vy = details.velocity.pixelsPerSecond.dy;
    final bool shouldPop = !_horizontal &&
        (_dy.abs() > height / _distanceRatio || vy.abs() > _flingVelocity);
    if (shouldPop) {
      setState(() => _popping = true);
      Navigator.of(context).maybePop();
      return;
    }
    _settleFrom = _dy;
    _settle.forward(from: 0);
  }

  void _onCancel() {
    _settleFrom = _dy;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.sizeOf(context).height;
    final double progress =
        height <= 0 ? 0.0 : (_dy.abs() / height).clamp(0.0, 1.0);
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        _VerticalDismissRecognizer:
            GestureRecognizerFactoryWithHandlers<_VerticalDismissRecognizer>(
          () => _VerticalDismissRecognizer(
            canStart: () => !_isZoomed(),
            debugOwner: this,
          ),
          (_VerticalDismissRecognizer instance) {
            instance
              ..onStart = _onStart
              ..onUpdate = _onUpdate
              ..onEnd = _onEnd
              ..onCancel = _onCancel;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          children: <Widget>[
            // 背景随位移淡出
            Positioned.fill(
              child: ColoredBox(
                color: _popping
                    ? Colors.transparent
                    : Colors.black.withValues(alpha: 1 - progress),
              ),
            ),
            Transform.translate(offset: Offset(0, _dy), child: widget.child),
          ],
        ),
      ),
    );
  }
}

/// 只接受「纵向占优」拖拽的垂直拖拽识别器。
///
/// Flutter 自带的 `VerticalDragGestureRecognizer` 只看**纵向位移**是否超过 slop：
/// 斜着滑（横向 100px、纵向 30px）它照样接受，于是把横向翻页的手势抢走。
/// 这里覆盖 `hasSufficientGlobalDistanceToAccept`（基类的公开方法），额外要求
/// 纵向位移 ≥ 横向位移的 1.2 倍；不满足就**拒绝自己**，手势完整留给画廊。
class _VerticalDismissRecognizer extends VerticalDragGestureRecognizer {
  _VerticalDismissRecognizer({this.canStart, super.debugOwner});

  /// 额外前置条件（例如「图片没被放大」）：为假时一律不接受。
  final bool Function()? canStart;

  /// 纵向相对横向的占优倍数。
  static const double _dominance = 1.2;

  double _dx = 0;
  double _dy = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _dx = 0;
    _dy = 0;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _dx += event.delta.dx;
      _dy += event.delta.dy;
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    if (canStart != null && !canStart!()) {
      return false;
    }
    if (_dx.abs() * _dominance >= _dy.abs()) {
      return false; // 横向不亚于纵向：让给画廊翻页
    }
    return super.hasSufficientGlobalDistanceToAccept(
      pointerDeviceKind,
      deviceTouchSlop,
    );
  }
}
