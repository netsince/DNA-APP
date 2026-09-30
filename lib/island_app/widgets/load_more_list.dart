import 'package:flutter/material.dart';

import 'package:dna/island_app/theme/app_dimensions.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/state_views.dart';

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

  @override
  Widget build(BuildContext context) {
    if (loading && itemCount == 0) {
      return const LoadingState();
    }
    if (error != null && itemCount == 0) {
      return ErrorState(message: error!, onRetry: onRetry);
    }
    if (itemCount == 0 && !hasMore) {
      return empty ?? const EmptyState(icon: Icons.inbox_outlined, title: '暂无数据');
    }

    final itemCountWithFooter = itemCount + (hasMore ? 1 : 0);
    final list = ListView.separated(
      padding: padding ?? const EdgeInsets.symmetric(vertical: kListGap),
      itemCount: itemCountWithFooter,
      separatorBuilder: separatorBuilder ?? (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= itemCount) {
          // 触底加载条。
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: loadingFooter ??
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
