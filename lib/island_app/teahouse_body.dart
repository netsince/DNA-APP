import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/models/teapost.dart';
import 'package:dna/island_app/teahouse_compose_page.dart';
import 'package:dna/island_app/teahouse_post_page.dart';
import 'package:dna/island_app/teahouse_topics_page.dart';
import 'package:dna/island_app/utils/post_like_fav.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/teahouse_post_tile.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 茶馆 Feed 加载回调（默认走 [ApiClient.getTeahousePosts]）。
typedef TeahouseFeedLoader = Future<
    ({
      List<Map<String, dynamic>> items,
      int page,
      int pages,
      int total,
      bool hasNext,
    })> Function({int page, String sort, int? topicId});

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
  List<TeaPost> _posts = const <TeaPost>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 1;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  TeahouseFeedLoader get _loader =>
      widget.feedLoader ?? ApiClient.instance.getTeahousePosts;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _noMore = false;
    });
    try {
      final result = await _loader(page: 1, sort: _sort, topicId: null);
      if (!mounted) return;
      setState(() {
        _posts = result.items
            .map((e) => TeaPost.fromJson(e))
            .where((p) => !p.isDeleted)
            .toList();
        _page = 1;
        _loading = false;
        _noMore = !result.hasNext;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _noMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _loader(page: _page + 1, sort: _sort, topicId: null);
      if (!mounted) return;
      setState(() {
        _posts = <TeaPost>[
          ..._posts,
          ...result.items
              .map((e) => TeaPost.fromJson(e))
              .where((p) => !p.isDeleted),
        ];
        _page += 1;
        _loadingMore = false;
        if (!result.hasNext) _noMore = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _selectSort(String sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    _reload();
  }

  void _openPost(int postId) {
    final opener = widget.postOpener;
    if (opener != null) {
      opener((context, postId));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeahousePostPage(postId: postId),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 在列表里按 id 更新某条帖子的统计。
  void _updatePost(int id, TeaPostStats Function(TeaPostStats) change) {
    setState(() {
      _posts = _posts
          .map((p) => p.idInt == id ? p.copyWith(stats: change(p.stats)) : p)
          .toList();
    });
  }

  @override
  void onPostLikeResult(int postId, ({bool liked, int count}) result) {
    _updatePost(postId,
        (s) => s.copyWith(liked: result.liked, likeCount: result.count));
  }

  @override
  void onPostFavoriteResult(int postId, bool favorited) {
    _updatePost(postId,
        (s) => s.copyWith(favorited: favorited, likeCount: s.likeCount));
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TeahouseTopicsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppRefreshIndicator(
        onRefresh: _reload,
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
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _sorts.map((s) {
                          final selected = _sort == s.$1;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(s.$2),
                              selected: selected,
                              onSelected: (_) => _selectSort(s.$1),
                            ),
                          );
                        }).toList(),
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
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null && _posts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(message: _error!, onRetry: _reload),
            )
          else if (_posts.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('还没有茶馆帖子，来发一条吧～')),
            )
          else ...<Widget>[
            SliverList.builder(
              itemCount: _posts.length,
              itemBuilder: (context, i) {
                final post = _posts[i];
                return TeahousePostTile(
                  post: post,
                  onTap: () => _openPost(post.idInt),
                  onCardTap: () => _openLinkedCard(context, post.card?.id),
                  onLike: () => togglePostLike(post.idInt),
                  onFavorite: () => togglePostFavorite(post.idInt),
                );
              },
            ),
            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            if (_noMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text('没有更多了', style: TextStyle(color: Colors.grey)),
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
      MaterialPageRoute<void>(
        builder: (_) => CardDetailPage(cardId: cardId),
      ),
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
  List<TeaPost> _posts = const <TeaPost>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 1;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _noMore = false;
    });
    try {
      final result = await ApiClient.instance.getTeahouseFavorites(page: 1);
      if (!mounted) return;
      setState(() {
        _posts = result.items.map((e) => TeaPost.fromJson(e)).toList();
        _page = 1;
        _loading = false;
        _noMore = !result.hasNext;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _noMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await ApiClient.instance.getTeahouseFavorites(page: _page + 1);
      if (!mounted) return;
      setState(() {
        _posts = <TeaPost>[..._posts, ...result.items.map((e) => TeaPost.fromJson(e))];
        _page += 1;
        _loadingMore = false;
        if (!result.hasNext) _noMore = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _openPost(int postId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeahousePostPage(postId: postId),
      ),
    );
  }

  bool get _loggedIn => AuthSession.instance.isLoggedIn;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _updatePost(int id, TeaPostStats Function(TeaPostStats) change) {
    setState(() {
      _posts = _posts
          .map((p) => p.idInt == id ? p.copyWith(stats: change(p.stats)) : p)
          .toList();
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
      _updatePost(postId, (s) => s.copyWith(liked: r.liked, likeCount: r.count));
    } catch (_) {
      _snack('操作失败，请重试');
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
      _updatePost(postId,
          (s) => s.copyWith(favorited: r.favorited, likeCount: s.likeCount));
      _snack(r.favorited ? '已收藏' : '已取消收藏');
    } catch (_) {
      _snack('操作失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _posts.isEmpty
              ? ErrorState(message: _error!, onRetry: _reload)
              : _posts.isEmpty
                  ? const Center(child: Text('还没有收藏的帖子'))
                  : AppRefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _posts.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= _posts.length) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final post = _posts[i];
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
