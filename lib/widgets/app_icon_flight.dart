import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

/// 飞行中的图标在 widget 树里的 key(测试据此量它的尺寸/位置)。
const ValueKey<String> kAppBarIconFlightKey = ValueKey<String>(
  'appbar-icon-flight',
);

/// 放大中的方块在 widget 树里的 key(测试据此量它的尺寸)。
const ValueKey<String> kAppBarBlockFlightKey = ValueKey<String>(
  'appbar-block-flight',
);

/// 图标飞行的相位(占整段时长的比例)。
///
/// * 方块:0 → [_kTravelEnd] 从按钮大小长到整屏(页面"材料"本身);
/// * 图标:同一段里从点击处平移到屏幕中央,**尺寸始终不变**;
/// * 页面内容:后段淡入 —— 方块先铺满,内容再显形;
/// * 图标淡出:与内容淡入交叠,页面实心后图标已消失,不留残影。
const double _kTravelEnd = 0.60;
const double _kPageFadeStart = 0.60;
const double _kPageFadeEnd = 0.90;
const double _kIconFadeStart = 0.75;
const double _kIconFadeEnd = 0.92;

/// 右上角图标按钮:**方块长大成整页,图标自己飞到屏幕中央**。
///
/// ## 两件事同时发生
///
/// 1. **方块放大**:以按钮的位置和大小(48×48 方块、小圆角)为起点,
///    一路长到铺满整屏(圆角同步收到 0)——页面背景不是"淡入"的,
///    而是从按钮那里长出来的;
/// 2. **图标平移**:那颗图标**保持点击时的大小不变**(24px),
///    从右上角滑到屏幕中央;方块铺满后,页面内容淡入、图标淡出。
///
/// 返回时同一段动画反向播放:内容隐去 → 方块缩回按钮大小 →
/// 图标从中央滑回原位。
///
/// ## 为什么不直接用容器变换([AppContainer])
///
/// 容器变换把"关闭态容器"整块(含其中的图标)放大,图标会跟着
/// 一路撑大到全屏,很怪。这里把**载体(方块)与图标拆开**:
/// 方块负责长大,图标只负责位移。
///
/// ## 用在哪
///
/// AppBar 上「新建 / 搜索」这类有明确源图标的入口。
/// **不要用在**:栏目切换(抽屉/底栏,那是胶片滑动)、
/// 纯视图切换(归档开关,原页不跳转)。
class AppBarIconAction<T extends Object?> extends StatefulWidget {
  const AppBarIconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.pageBuilder,
    this.onClosed,
  });

  final String tooltip;
  final IconData icon;

  /// 目标页。飞行前段内容透明度为 0(此时只有方块在长大),
  /// 后段随方块铺满淡入。
  final WidgetBuilder pageBuilder;

  /// 目标页关闭时回传的结果(约定:页面内是否发生了修改)。
  final void Function(T? result)? onClosed;

  @override
  State<AppBarIconAction<T>> createState() => _AppBarIconActionState<T>();
}

class _AppBarIconActionState<T> extends State<AppBarIconAction<T>> {
  /// 飞行/打开期间隐藏原位图标:飞行中的图标由路由绘制,
  /// 若原位那颗还在,画面上会同时出现两颗。
  bool _flying = false;

  Future<void> _fly() async {
    if (_flying) {
      return;
    }
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    // 方块与图标的共同起点:按钮自身的矩形。
    final Rect sourceRect = box.localToGlobal(Offset.zero) & box.size;
    final IconThemeData iconTheme = IconTheme.of(context);
    final ThemeData theme = Theme.of(context);
    final Color iconColor =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;

    setState(() => _flying = true);
    final T? result = await Navigator.of(context).push<T>(
      _IconFlightRoute<T>(
        icon: widget.icon,
        iconSize: iconTheme.size ?? 24,
        iconColor: iconColor,
        sourceRect: sourceRect,
        pageBuilder: widget.pageBuilder,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _flying = false);
    widget.onClosed?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      onPressed: _fly,
      // 用 Opacity 而不是换 widget:占位保持不变,
      // 飞行期间标题栏布局不会因为少了这颗按钮而跳动。
      icon: Opacity(opacity: _flying ? 0 : 1, child: Icon(widget.icon)),
    );
  }
}

/// 图标飞行路由:透明路由,原页始终可见,方块在其上长大、图标在其上平移。
///
/// 与容器变换一样是 `opaque: false`(飞行中要透出原页),
/// 页面由自己的 Scaffold 铺底,所以落定后不会看到下面的内容。
class _IconFlightRoute<T> extends PageRouteBuilder<T> {
  _IconFlightRoute({
    required this.icon,
    required this.iconSize,
    required this.iconColor,
    required this.sourceRect,
    required WidgetBuilder pageBuilder,
  }) : super(
         transitionDuration: AppMotion.transform,
         reverseTransitionDuration: AppMotion.transform,
         opaque: false,
         barrierDismissible: false,
         pageBuilder:
             (
               BuildContext context,
               Animation<double> _,
               Animation<double> _,
             ) => pageBuilder(context),
       );

  final IconData icon;
  final double iconSize;
  final Color iconColor;

  /// 方块与图标的起点(点击时按钮的屏幕矩形)。
  final Rect sourceRect;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Size screen = MediaQuery.sizeOf(context);
    final Rect targetRect = Offset.zero & screen;
    final ThemeData theme = Theme.of(context);
    // 方块颜色 = 页面背景:方块长成整屏时与页面本身无缝衔接。
    final Color blockColor = theme.scaffoldBackgroundColor;

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? _) {
        final double t = animation.value;

        // 一条进度同时驱动两层:方块从按钮矩形长到整屏,
        // 图标从按钮中心平移到屏幕中央。用与栏目切换同一条
        // 非线性曲线(慢起—掠过—长收),全应用动感一致。
        final double travel = (t / _kTravelEnd).clamp(0.0, 1.0);
        final double eased = AppMotion.travel.transform(travel);

        final Rect blockRect = Rect.lerp(sourceRect, targetRect, eased)!;
        final double blockRadius = lerpDouble(
          AppRadius.sm,
          0,
          eased,
        )!.clamp(0.0, AppRadius.sm);
        final Offset iconCenter = Offset.lerp(
          sourceRect.center,
          targetRect.center,
          eased,
        )!;

        final double pageOpacity =
            ((t - _kPageFadeStart) / (_kPageFadeEnd - _kPageFadeStart)).clamp(
              0.0,
              1.0,
            );
        final double iconOpacity = t <= _kIconFadeStart
            ? 1.0
            : (1 - (t - _kIconFadeStart) / (_kIconFadeEnd - _kIconFadeStart))
                  .clamp(0.0, 1.0);

        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // 1. 放大中的方块(页面"材料"):页面内容铺满后即撤掉,
            //    不必整页生命周期都挂一块无用的底色。
            if (pageOpacity < 1.0)
              Positioned.fromRect(
                key: kAppBarBlockFlightKey,
                rect: blockRect,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(blockRadius),
                    ),
                  ),
                ),
              ),
            // 2. 页面内容:方块铺满后淡入。
            Positioned.fill(
              child: Opacity(opacity: pageOpacity, child: child),
            ),
            // 3. 图标:尺寸恒定,只做位移。
            if (iconOpacity > 0)
              Positioned(
                key: kAppBarIconFlightKey,
                left: iconCenter.dx - iconSize / 2,
                top: iconCenter.dy - iconSize / 2,
                width: iconSize,
                height: iconSize,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: iconOpacity,
                    child: Icon(icon, size: iconSize, color: iconColor),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
