import 'package:flutter/material.dart';

import '../island_app/theme/app_dimensions.dart';
import '../island_app/widgets/load_more_list.dart';
import '../island_app/widgets/refreshable.dart';
import '../island_app/widgets/state_views.dart';
import '../island_app/widgets/wide_body.dart';
import 'paged_controller.dart';

/// 分页列表的**五种状态骨架**（首载 / 错误 / 空 / 列表 / 触底加载中）。
///
/// 2026-11 审计把这套状态机收进了 [PagedController]，但那之后每个页面仍在
/// 手抄同样一段『loading ? LoadingState : error ? ErrorState : empty ? Empty :
/// LoadMoreListView(...)』的接线。这一层把接线也收掉：页面只给
/// 「一条数据怎么画」，其余交给这里。
///
/// 列表形态用 [PagedListBody]，网格/瀑布流形态用 [PagedGridBody]。
class PagedListBody<T> extends StatelessWidget {
  const PagedListBody({
    super.key,
    required this.controller,
    required this.itemBuilder,
    required this.empty,
    this.separator,
    this.padding,
    this.wide = WideContent.list,
  });

  final PagedController<T> controller;
  final IndexedWidgetBuilder itemBuilder;

  /// 空状态（调用方给文案与图标，同原来各页的写法）。
  final Widget empty;
  final IndexedWidgetBuilder? separator;
  final EdgeInsetsGeometry? padding;
  final WideContent? wide;

  @override
  Widget build(BuildContext context) {
    return LoadMoreListView(
      loading: controller.isLoading,
      itemCount: controller.items.length,
      // 空列表时不要再报「还有更多」，否则会显示一个永远转圈的底栏。
      hasMore: controller.hasMore && controller.items.isNotEmpty,
      onLoadMore: controller.loadMore,
      onRefresh: controller.refresh,
      error: controller.error,
      onRetry: controller.refresh,
      separatorBuilder: separator,
      padding: padding,
      wide: wide,
      empty: empty,
      itemBuilder: itemBuilder,
    );
  }
}

/// 网格 / 瀑布流形态的分页列表骨架。
///
/// 与 [PagedListBody] 的差别只在最后一层：这里把「怎么排」交给调用方的
/// [sliverBuilder]（各页用的网格算法不同，不强行统一），
/// 其余四种状态与下拉刷新、触底加载都由这里负责。
class PagedGridBody<T> extends StatelessWidget {
  const PagedGridBody({
    super.key,
    required this.controller,
    required this.sliverBuilder,
    required this.empty,
  });

  final PagedController<T> controller;

  /// 把当前条目排成 sliver（通常包一层 SliverPadding）。
  final Widget Function(BuildContext context, List<T> items) sliverBuilder;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    return AppStateTransition(child: _buildState(context));
  }

  Widget _buildState(BuildContext context) {
    if (controller.isLoading && controller.items.isEmpty) {
      return const LoadingState();
    }
    if (controller.error != null && controller.items.isEmpty) {
      return ErrorState(
        message: controller.error!,
        onRetry: controller.refresh,
      );
    }
    if (controller.items.isEmpty) {
      return empty;
    }
    return AppRefreshIndicator(
      onRefresh: controller.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification n) {
          if (n.metrics.pixels >=
              n.metrics.maxScrollExtent - kLoadMoreThreshold) {
            controller.loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            sliverBuilder(context, controller.items),
            if (controller.isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
