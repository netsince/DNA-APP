import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 元素背景：给「一组内容」一个可辨认的底。
///
/// 为什么需要它：前一轮审计把「每组一张卡片」全部去掉，改用语号与间距表达层级。
/// 结果是所有内容都直接铺在页面底色上 —— 设置分组、列表行、卡片之间只剩间距差异，
/// 元素边界很难辨认（原话：「非常难以辨认」）。
///
/// 这里恢复的是**底色**而不是描边卡片：`surfaceContainerLow` + 16 圆角 + 卡片内边距，
/// 没有 border、没有 elevation。层级仍然靠间距和字号，底色只负责「这一块是一组」。
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = AppInsets.card,
    this.margin = EdgeInsets.zero,
    this.radius = AppRadius.md,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    // 用 Material 而不是 DecoratedBox：ListTile 的水波纹与背景画在最近的
    // Material 上，中间隔一层带底色的 DecoratedBox 会被断言拦下（也会让点击反馈消失）。
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 列表放进一张底里的形态：行保持自己的内边距，卡片只负责底色与圆角裁剪。
///
/// 用在「一组行」上（设置分组的入口行、消息列表），不是每个行各一张卡。
class AppSurfaceList extends StatelessWidget {
  const AppSurfaceList({
    super.key,
    required this.children,
    this.margin = EdgeInsets.zero,
    this.radius = AppRadius.md,
    this.color,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
