import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/models/teapost.dart';
import 'package:dna/island_app/teahouse_compose_page.dart';
import 'package:dna/island_app/teahouse_post_page.dart';
import 'package:dna/island_app/teahouse_topics_page.dart';
import 'package:dna/island_app/utils/post_like_fav.dart';
import 'package:dna/widgets/load_more_list.dart';
import 'package:dna/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/teahouse_post_tile.dart';
import 'package:dna/widgets/wide_body.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/utils/error_display.dart';
import 'package:dna/widgets/paged_controller.dart';

/// 茶馆 Feed 加载回调（默认走 [ApiClient.getTeahousePosts]）。
typedef TeahouseFeedLoader =
    Future<
      ({
        List<Map<String, dynamic>> items,
        int page,
        int pages,
        int total,
        bool hasNext,
      })
    >
    Function({int page, String sort, int? topicId});

/// 茶馆主页：排序（热门/最新）切换 + 帖子流 + 下拉刷新 + 无限分页。
///
/// 顶栏提供「话题」「我的收藏」入口；右下 FAB 发帖。点帖子打开详情页。
class TeahouseBody extends StatefulWidget {
  const TeahouseBody({
    super.key,
    this.feedLoader,
    this.composeOpener,
    this.postOpener,
  });

  /// 注入用：Feed 加载器（测试替换为 stub）。
  final TeahouseFeedLoader? feedLoader;

  /// 打开发帖页；为 null 时默认 push [TeahouseComposePage]。
  final ValueChanged<BuildContext>? composeOpener;

  /// 打开帖子详情；为 null 时默认 push [TeahousePostPage]。
  final ValueChanged<(BuildContext, int)>? postOpener;

  @override
  State<TeahouseBody> createState() => _TeahouseBodyState();
}

class _TeahouseBodyState extends State<TeahouseBody>
    with PostLikeFavMixin<TeahouseBody> {
  static const List<(String, String)> _sorts = <(String, String)>[
    ('hot', '热门'),
    ('new', '最新'),
  ];

  String _sort = 'hot';
  final ScrollController _scrollController = ScrollController();

  /// 分页状态（加载中 / 加载更多 / 有没有下一页 / 页码 / 错误）交给共享
  /// [PagedController]；本页只提供「怎么取一页」。
  late final PagedController<TeaPost> _paged = PagedController<TeaPost>(
    fetch: (int page) async {
      final result = await _loader(page: page, sort: _sort, topicId: null);
      return PagedResult<TeaPost>(
        // 软删除的帖子照旧不进列表。
        items: result.items
            .map((Map<String, dynamic> e) => TeaPost.fromJson(e))
            .where((TeaPost p) => !p.isDeleted)
            .toList(),
        hasMore: result.hasNext,
      );
    },
    onChanged: () {
      if (mounted) setState(() {});
    },
    firstLoadError: '茶馆帖子加载失败，请稍后重试',
  );

  TeahouseFeedLoader get _loader =>
      widget.feedLoader ?? ApiClient.instance.getTeahousePosts;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _paged.refresh();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _paged.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 阈值与判定公式来自共享分页工具（内容流用 300，非列表页的 400）。
    if (isNearScrollEnd(
      _scrollController.position,
      threshold: kLoadMoreFeedThreshold,
    )) {
      _paged.loadMore();
    }
  }

  void _selectSort(String sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    _paged.refresh();
  }

  void _openPost(int postId) {
    final opener = widget.postOpener;
    if (opener != null) {
      opener((context, postId));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TeahousePostPage(postId: postId)),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    showSnack(context, msg);
  }

  /// 在列表里按 id 更新某条帖子的统计。
  void _updatePost(int id, TeaPostStats Function(TeaPostStats) change) {
    final int i = _paged.items.indexWhere((TeaPost p) => p.idInt == id);
    if (i < 0) return;
    setState(() {
      _paged.items[i] = _paged.items[i].copyWith(
        stats: change(_paged.items[i].stats),
      );
    });
  }

  @override
  void onPostLikeResult(int postId, ({bool liked, int count}) result) {
    _updatePost(
      postId,
      (s) => s.copyWith(liked: result.liked, likeCount: result.count),
    );
  }

  @override
  void onPostFavoriteResult(int postId, bool favorited) {
    _updatePost(
      postId,
      (s) => s.copyWith(favorited: favorited, likeCount: s.likeCount),
    );
    _snack(favorited ? '已收藏' : '已取消收藏');
  }

  void _openCompose() {
    final opener = widget.composeOpener;
    if (opener != null) {
      opener(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TeahouseComposePage()),
    );
  }

  void _openTopics() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const TeahouseTopicsPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppRefreshIndicator(
        onRefresh: _paged.refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      // 排序：互斥 2 项、常显 → SegmentedButton（与角色卡探索、
                      // 世界、评论区、搜索用同一个控件；原来这里是 ChoiceChip）。
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<String>(
                          segments: <ButtonSegment<String>>[
                            for (final (String key, String label) in _sorts)
                              ButtonSegment<String>(
                                value: key,
                                label: Text(label),
                              ),
                          ],
                          selected: <String>{_sort},
                          onSelectionChanged: (Set<String> picked) =>
                              _selectSort(picked.first),
                          // 不压密度：保留 M3 默认的 40dp 高度。

                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.local_offer_outlined),
                      tooltip: '话题',
                      onPressed: _openTopics,
                    ),
                    IconButton(
                      icon: const Icon(Icons.bookmark_outline),
                      tooltip: '我的收藏',
                      onPressed: _openFavorites,
                    ),
                  ],
                ),
              ),
            ),
            if (_paged.isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_paged.error != null && _paged.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorState(
                  message: _paged.error!,
                  onRetry: _paged.refresh,
                ),
              )
            else if (_paged.items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('还没有茶馆帖子，来发一条吧～')),
              )
            else ...<Widget>[
              //版心：桌面上面把帖子列居中收窄，否则一行文字横跨整屏、行长不可读。
              //用 SliverPadding而不是 ConstrainedBox：滚动/下拉刷新行为不变。
              SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: wideInset(
                    MediaQuery.sizeOf(context).width,
                    maxWidth: WideContent.reading.maxWidth,
                  ),
                ),
                sliver: SliverList.builder(
                  itemCount: _paged.items.length,
                  itemBuilder: (context, i) {
                    final post = _paged.items[i];
                    return TeahousePostTile(
                      post: post,
                      onTap: () => _openPost(post.idInt),
                      onCardTap: () => _openLinkedCard(context, post.card?.id),
                      onLike: () => togglePostLike(post.idInt),
                      onFavorite: () => togglePostFavorite(post.idInt),
                    );
                  },
                ),
              ),
              if (_paged.isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: AppInsets.card,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              // 与旧语义一致：首屏加载完且确实没有下一页才提示「没有更多了」。
              if (!_paged.hasMore && _paged.items.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: AppInsets.card,
                    child: Center(
                      child: Text(
                        '没有更多了',
                        // 语义色而不是裸 Colors.grey（审计 4.4）。
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCompose,
        tooltip: '发帖',
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }

  void _openFavorites() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TeahouseFavoritesPage()),
    );
  }

  void _openLinkedCard(BuildContext context, String? cardId) {
    if (cardId == null || cardId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CardDetailPage(cardId: cardId)),
    );
  }
}

/// 茶馆收藏页。
class TeahouseFavoritesPage extends StatefulWidget {
  const TeahouseFavoritesPage({super.key});

  @override
  State<TeahouseFavoritesPage> createState() => _TeahouseFavoritesPageState();
}

class _TeahouseFavoritesPageState extends State<TeahouseFavoritesPage> {
  final ScrollController _scrollController = ScrollController();

  /// 收藏页是**另一套独立的分页**（数据源不同），所以另建一个控制器。
  late final PagedController<TeaPost> _paged = PagedController<TeaPost>(
    fetch: (int page) async {
      final result = await ApiClient.instance.getTeahouseFavorites(page: page);
      return PagedResult<TeaPost>(
        items: result.items
            .map((Map<String, dynamic> e) => TeaPost.fromJson(e))
            .toList(),
        hasMore: result.hasNext,
      );
    },
    onChanged: () {
      if (mounted) setState(() {});
    },
    firstLoadError: '收藏列表加载失败，请稍后重试',
  );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _paged.refresh();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _paged.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 阈值与判定公式来自共享分页工具（内容流用 300，非列表页的 400）。
    if (isNearScrollEnd(
      _scrollController.position,
      threshold: kLoadMoreFeedThreshold,
    )) {
      _paged.loadMore();
    }
  }

  void _openPost(int postId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TeahousePostPage(postId: postId)),
    );
  }

  bool get _loggedIn => AuthSession.instance.isLoggedIn;

  void _snack(String msg) {
    if (!mounted) return;
    showSnack(context, msg);
  }

  void _updatePost(int id, TeaPostStats Function(TeaPostStats) change) {
    final int i = _paged.items.indexWhere((TeaPost p) => p.idInt == id);
    if (i < 0) return;
    setState(() {
      _paged.items[i] = _paged.items[i].copyWith(
        stats: change(_paged.items[i].stats),
      );
    });
  }

  Future<void> _toggleLike(int postId) async {
    if (!_loggedIn) {
      _snack('请先登录后再点赞');
      return;
    }
    try {
      final r = await ApiClient.instance.toggleTeahouseLike(postId);
      if (!mounted) return;
      _updatePost(
        postId,
        (s) => s.copyWith(liked: r.liked, likeCount: r.count),
      );
    } catch (e) {
      _snack('操作失败：${describeError(e)}');
    }
  }

  Future<void> _toggleFavorite(int postId) async {
    if (!_loggedIn) {
      _snack('请先登录后再收藏');
      return;
    }
    try {
      final r = await ApiClient.instance.toggleTeahouseFavorite(postId);
      if (!mounted) return;
      _updatePost(
        postId,
        (s) => s.copyWith(favorited: r.favorited, likeCount: s.likeCount),
      );
      _snack(r.favorited ? '已收藏' : '已取消收藏');
    } catch (e) {
      _snack('操作失败：${describeError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: _paged.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _paged.error != null && _paged.items.isEmpty
          ? ErrorState(message: _paged.error!, onRetry: _paged.refresh)
          : _paged.items.isEmpty
          ? const Center(child: Text('还没有收藏的帖子'))
          : AppRefreshIndicator(
              onRefresh: _paged.refresh,
              child: ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _paged.items.length + (_paged.isLoadingMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= _paged.items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final post = _paged.items[i];
                  return TeahousePostTile(
                    post: post,
                    onTap: () => _openPost(post.idInt),
                    onLike: () => _toggleLike(post.idInt),
                    onFavorite: () => _toggleFavorite(post.idInt),
                  );
                },
              ),
            ),
    );
  }
}
