import 'package:flutter/material.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/responsive_card_grid.dart';
import 'package:dna/island_app/widgets/state_views.dart';

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
  final List<Map<String, dynamic>> _cards = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loadingMore || (!reset && _noMore)) return;
    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final data = await widget.loader(page: reset ? 1 : _page + 1);
      if (!mounted) return;
      final raw = data['items'];
      final items = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        if (reset) _cards.clear();
        _cards.addAll(items);
        _page = reset ? 1 : _page + 1;
        _noMore = items.isEmpty || data['has_next'] != true;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _openCard(String cardId) {
    if (cardId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardDetailPage(cardId: cardId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: _loading && _cards.isEmpty
          ? const LoadingState()
          : _cards.isEmpty
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: '暂无内容',
                )
              : AppRefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
                        _load();
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: <Widget>[
                        SliverPadding(
                          padding: const EdgeInsets.all(12),
                          sliver: ResponsiveCardGrid(
                            cards: _cards,
                            minColumnWidth: 180,
                            maxColumns: 6,
                            onCardTap: _openCard,
                          ),
                        ),
                        if (_loadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
