import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/widgets/responsive_card_grid.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/widgets/paged_controller.dart';
import 'package:dna/widgets/paged_list_body.dart';

/// 卡片分页加载回调（默认走 [ApiClient.getMyFavorites]/[getMyLikes]）。
typedef MyCardsLoader = Future<Map<String, dynamic>> Function({int page});

/// 「我的收藏 / 我的点赞」角色卡列表页。
///
/// 网格展示卡片（复用 [CardTile]），分页加载 + 下拉刷新，点击进入卡片详情。
class MyCollectionsPage extends StatefulWidget {
  const MyCollectionsPage({
    super.key,
    required this.title,
    required this.loader,
  });

  final String title;
  final MyCardsLoader loader;

  @override
  State<MyCollectionsPage> createState() => _MyCollectionsPageState();
}

class _MyCollectionsPageState extends State<MyCollectionsPage> {
  /// 分页状态（加载中 / 加载更多 / 没有更多 / 页码 / 错误）统一由
  /// [PagedController] 管，页面只提供「怎么取一页」。
  late final PagedController<Map<String, dynamic>> _paged =
      PagedController<Map<String, dynamic>>(
        fetch: (int page) async {
          final Map<String, dynamic> data = await widget.loader(page: page);
          final Object? raw = data['items'];
          final List<Map<String, dynamic>> items = raw is List
              ? raw
                    .whereType<Map>()
                    .map((Map e) => e.map((k, v) => MapEntry(k.toString(), v)))
                    .toList()
              : <Map<String, dynamic>>[];
          return PagedResult<Map<String, dynamic>>(
            items: items,
            hasMore: data['has_next'] == true,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        // 首屏失败不能被渲染成「暂无内容」（审计 3.5）；翻页中途失败由
        // 控制器保留已加载内容，不会把页面打成错误态。
        firstLoadError: '内容加载失败，请稍后重试',
      );

  @override
  void initState() {
    super.initState();
    _paged.refresh();
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  void _openCard(String cardId) {
    if (cardId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CardDetailPage(cardId: cardId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      // 五态 + 下拉刷新 + 触底加载由 [PagedGridBody] 统一负责；
      // 具体怎么排（ResponsiveCardGrid）仍留在本页，不强行统一布局算法。
      body: PagedGridBody<Map<String, dynamic>>(
        controller: _paged,
        empty: const EmptyState(icon: Icons.inbox_outlined, title: '暂无内容'),
        sliverBuilder: (BuildContext context, List<Map<String, dynamic>> items) {
          return SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.md),
            sliver: ResponsiveCardGrid(
              cards: items,
              minColumnWidth: 180,
              maxColumns: 6,
              onCardTap: _openCard,
            ),
          );
        },
      ),
    );
  }
}
