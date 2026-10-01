import 'package:flutter/material.dart';

/// 全局统一的下拉刷新回调类型：返回的 Future 在刷新完成后 resolve，
/// `RefreshIndicator` 据此收起指示器。各页面把自己的刷新逻辑实现为
/// 一个 `Future<void> Function()`，通过 [AppRefreshIndicator] 注入。
typedef RefreshCallback = Future<void> Function();

/// 全局统一的下拉刷新容器。
///
/// 包住任意可滚动内容（`ListView` / `CustomScrollView` /
/// `NestedScrollView` / `SingleChildScrollView` 等），下拉即触发
/// [onRefresh]，并统一刷新指示器样式（主色、间距、背景）。
///
/// 所有需要下拉刷新的页面都应引用本组件，保证全局刷新交互一致，
/// 后续调整刷新样式只需改这一处。
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement = 40,
    this.edgeOffset = 0,
  });

  /// 下拉刷新的回调（标准命名：各页面实现自己的刷新逻辑后传入）。
  final RefreshCallback onRefresh;

  /// 可滚动的内容（必须是可滚动 widget，否则下拉刷新不生效）。
  final Widget child;

  /// 指示器距顶部的位移量。
  final double displacement;

  /// 指示器距滚动视图顶部边缘的偏移。
  final double edgeOffset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: displacement,
      edgeOffset: edgeOffset,
      color: scheme.primary,
      backgroundColor: scheme.surface,
      child: child,
    );
  }
}
