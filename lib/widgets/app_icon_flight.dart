import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

/// 飞行中的图标在 widget 树里的 key(测试据此量它的尺寸/位置)。
const ValueKey<String> kAppBarIconFlightKey = ValueKey<String>(
  'appbar-icon-flight',
);

/// 图标飞行的相位(占整段时长的比例)。
///
/// * 位移:0 → [_kTravelEnd],图标从点击处平移到屏幕中央;
/// * 页面:后段淡入 —— 图标先到位,页面再显形;
/// * 图标淡出:与页面淡入交叠,页面实心后图标已经消失,
///   不会出现"图标压在页面上"的残影。
const double _kTravelEnd = 0.60;
const double _kPageFadeStart = 0.60;
const double _kPageFadeEnd = 0.90;
const double _kIconFadeStart = 0.75;
const double _kIconFadeEnd = 0.92;

/// 右上角图标按钮:**图标原样飞到屏幕中央,然后页面出现**;
/// 返回时页面隐去、同一个图标飞回原位。
///
/// ## 与容器变换([AppContainer])的区别
///
/// 容器变换把"关闭态容器"整块放大成整页(卡片 → 详情页很合适),
/// 但用在标题栏图标上会把那颗 24px 的图标一路撑到全屏,很怪。
/// 这里只做**平移**:图标尺寸全程不变(就是点下去时的大小),
/// 飞到屏幕中央后淡出,页面随即淡入。
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

  /// 目标页。飞行前段页面透明度为 0(透出原页,图标在其上飞过),
  /// 后段淡入。
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
    final Offset sourceCenter = box.localToGlobal(box.size.center(Offset.zero));
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
        sourceCenter: sourceCenter,
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

/// 图标飞行路由:透明路由,原页始终可见,图标在其上平移。
///
/// 与容器变换一样是 `opaque: false`(飞行中要透出原页),
/// 页面由自己的 Scaffold 铺底,所以落定后不会看到下面的内容。
class _IconFlightRoute<T> extends PageRouteBuilder<T> {
  _IconFlightRoute({
    required this.icon,
    required this.iconSize,
    required this.iconColor,
    required this.sourceCenter,
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
               Animation<double> __,
             ) => pageBuilder(context),
       );

  final IconData icon;
  final double iconSize;
  final Color iconColor;

  /// 图标起点(点击时那颗图标的屏幕坐标中心)。
  final Offset sourceCenter;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Size screen = MediaQuery.sizeOf(context);
    final Offset targetCenter = Offset(screen.width / 2, screen.height / 2);

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? _) {
        final double t = animation.value;

        // 位移:恒定尺寸,只算中心点。用与栏目切换同一条
        // 非线性曲线(慢起—掠过—长收),全应用动感一致。
        final double travel = (t / _kTravelEnd).clamp(0.0, 1.0);
        final Offset center = Offset.lerp(
          sourceCenter,
          targetCenter,
          AppMotion.travel.transform(travel),
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
            Positioned.fill(
              child: Opacity(opacity: pageOpacity, child: child),
            ),
            if (iconOpacity > 0)
              Positioned(
                key: kAppBarIconFlightKey,
                left: center.dx - iconSize / 2,
                top: center.dy - iconSize / 2,
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
