import 'package:flutter/material.dart';
import '../../theme/tokens.dart';

import 'package:dna/island_app/theme/app_dimensions.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/island_app/widgets/wide_body.dart';

// ---------------------------------------------------------------------------
// 触底加载：阈值 + 监听器（全模块唯一实现，审计 5 节「分页 2 套」）
// ---------------------------------------------------------------------------
//
// 以前 explore / worlds / teahouse / search 各自手写
// `NotificationListener<ScrollNotification>` 或 `ScrollController` 监听，
// 阈值 400 / 300 也各写一遍。现在：
// * 列表/网格页的 400 统一用 [kLoadMoreThreshold]（定义在 app_dimensions）；
// * 内容流（茶馆 feed）的 300 统一用 [kLoadMoreFeedThreshold]；
// * 监听本身用 [loadMoreListener] 包一层。

/// 内容流（茶馆 feed）的触底阈值：300px。
///
/// 比列表页的 [kLoadMoreThreshold]（400）更小：feed 的帖子卡片很高，
/// 一屏只有 2-3 条，400 的提前量会让「刚滚动就开始加载」的感觉太急。
///
/// **语义保持不变**：原来 teahouse 用 300、其余页用 400，只是把数字集中到
/// 这里并写明为什么不同。
const double kLoadMoreFeedThreshold = 300;

/// 判断某个 [ScrollPosition] 是否已经接近底部。
///
/// 给**自带 ScrollController** 的页面用（茶馆那三页的 controller 还兼作别用，
/// 直接把监听换成 widget 包装只会多一层缩进）：它们只需要把「多少算接近底部」
/// 这半件事交给这里，阈值与判定公式和 [loadMoreListener] 完全一致。
bool isNearScrollEnd(
  ScrollPosition position, {
  double threshold = kLoadMoreThreshold,
}) =>
    position.extentAfter <= threshold;

/// 把「滚动接近底部 → 加载下一页」包成一个组件。
///
/// 用法：可滚动视图作为 [child] 传进来；[onReachEnd] 里**只判断**
/// 「还有没有下一页 / 是否正在加载」，阈值不在这里重复写。
///
/// 返回 false 让通知继续冒泡（外层还可能挂着别的监听）。
Widget loadMoreListener({
  required Widget child,
  required VoidCallback onReachEnd,
  double threshold = kLoadMoreThreshold,
}) {
  return NotificationListener<ScrollNotification>(
    onNotification: (ScrollNotification notification) {
      if (notification.metrics.pixels >=
          notification.metrics.maxScrollExtent - threshold) {
        onReachEnd();
      }
      return false;
    },
    child: child,
  );
}

/// 统一的分页列表：封装「下拉刷新 + 触底加载 + 空态 / 错误态 / 加载态」。
///
/// 各列表页只需提供 [itemCount] / [itemBuilder] 与 [loadMore] 回调，即可获得
/// 全局一致的分页体验，避免每页重复写 `NotificationListener + _loadMore()`。
///
/// 用法：
/// ```dart
/// LoadMoreListView(
///   itemCount: items.length,
///   itemBuilder: (c, i) => MyTile(items[i]),
///   hasMore: hasMore,
///   onLoadMore: _loadMore,
///   onRefresh: _refresh,
///   empty: EmptyState(icon: Icons.inbox, title: '暂无数据'),
/// )
/// ```
class LoadMoreListView extends StatelessWidget {
  const LoadMoreListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.hasMore,
    required this.onLoadMore,
    this.onRefresh,
    this.separatorBuilder,
    this.empty,
    this.error,
    this.onRetry,
    this.loading = false,
    this.padding,
    this.loadingFooter,
    this.wide = WideContent.list,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final Future<void> Function()? onRefresh;
  final IndexedWidgetBuilder? separatorBuilder;
  final Widget? empty;
  final String? error;
  final VoidCallback? onRetry;
  final bool loading;
  final EdgeInsetsGeometry? padding;
  final Widget? loadingFooter;

  ///宽窗口下的版心宽度。桌面上面单列列表不能被拉成一条横跨整屏的文字。
  ///传 null可关闭（确实需要铺满的列表）。
  final WideContent? wide;

  @override
  Widget build(BuildContext context) {
    if (loading && itemCount == 0) {
      return const LoadingState();
    }
    if (error != null && itemCount == 0) {
      return ErrorState(message: error!, onRetry: onRetry);
    }
    if (itemCount == 0 && !hasMore) {
      return empty ??
          const EmptyState(icon: Icons.inbox_outlined, title: '暂无数据');
    }

    final itemCountWithFooter = itemCount + (hasMore ? 1 : 0);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        //版心：把多余宽度变成左右留白。不能在外层包 ConstrainedBox ——
        //那会让列表失去滚动语义（ListView拿不到有界高度）。
        final EdgeInsetsGeometry base =
            padding ?? const EdgeInsets.symmetric(vertical: kListGap);
        final double inset = wide == null
            ? 0
            : wideInset(constraints.maxWidth, maxWidth: wide!.maxWidth);
        final EdgeInsetsGeometry effective = inset <= 0
            ? base
            : (base as EdgeInsets).add(EdgeInsets.symmetric(horizontal: inset));
        return _buildList(context, itemCountWithFooter, effective);
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    int itemCountWithFooter,
    EdgeInsetsGeometry effective,
  ) {
    final list = ListView.separated(
      padding: effective,
      itemCount: itemCountWithFooter,
      separatorBuilder: separatorBuilder ?? (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= itemCount) {
          // 触底加载条。
          return Padding(
            padding: AppInsets.card,
            child: Center(
              child:
                  loadingFooter ??
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
            ),
          );
        }
        return itemBuilder(context, index);
      },
    );

    // 触底自动加载。
    final withLoadMore = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - kLoadMoreThreshold) {
          if (hasMore) onLoadMore();
        }
        return false;
      },
      child: list,
    );

    if (onRefresh == null) return withLoadMore;
    return AppRefreshIndicator(onRefresh: onRefresh!, child: withLoadMore);
  }
}
