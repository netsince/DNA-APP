import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/models/teapost.dart';
import 'package:dna/island_app/teahouse_post_page.dart';
import 'package:dna/utils/error_display.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/teahouse_post_tile.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/island_app/widgets/wide_body.dart';
import 'package:dna/widgets/paged_controller.dart';

/// 茶馆话题列表（GET /teahouse/topics）。
class TeahouseTopicsPage extends StatefulWidget {
  const TeahouseTopicsPage({super.key});

  @override
  State<TeahouseTopicsPage> createState() => _TeahouseTopicsPageState();
}

class _TeahouseTopicsPageState extends State<TeahouseTopicsPage> {
  List<Map<String, dynamic>> _topics = const <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final topics = await ApiClient.instance.getTeahouseTopics();
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 人话前缀 + 原始原因：只留一句「请稍后重试」会把真正的原因丢掉。
        _error = '话题加载失败：${describeError(e)}';
      });
    }
  }

  void _openTopic(Map<String, dynamic> t) {
    final id = t['id'];
    final name = (t['name'] ?? '').toString();
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeahouseTopicPage(
          topicId: (id is num ? id.toInt() : int.tryParse('$id') ?? 0),
          topicName: name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('话题')),
      body: _loading
          ? const LoadingState()
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : _topics.isEmpty
          ? const EmptyState(icon: Icons.tag, title: '暂无话题')
          : AppRefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: wideInset(
                    MediaQuery.sizeOf(context).width,
                    maxWidth: WideContent.reading.maxWidth,
                  ),
                ),
                itemCount: _topics.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: scheme.outlineVariant),
                itemBuilder: (context, i) {
                  final t = _topics[i];
                  final name = (t['name'] ?? '').toString();
                  final count = (t['post_count'] as num?)?.toInt() ?? 0;
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(name.isNotEmpty ? name[0] : '#'),
                    ),
                    title: Text(name),
                    subtitle: Text('$count 帖'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openTopic(t),
                  );
                },
              ),
            ),
    );
  }
}

/// 话题详情：展示该话题下的帖子列表（分页）。
class TeahouseTopicPage extends StatefulWidget {
  const TeahouseTopicPage({
    super.key,
    required this.topicId,
    required this.topicName,
  });

  final int topicId;
  final String topicName;

  @override
  State<TeahouseTopicPage> createState() => _TeahouseTopicPageState();
}

class _TeahouseTopicPageState extends State<TeahouseTopicPage> {
  final ScrollController _scrollController = ScrollController();

  /// 分页状态（加载中 / 加载更多 / 有没有下一页 / 页码 / 错误）交给共享
  /// [PagedController]；本页只提供「怎么取一页」。
  late final PagedController<TeaPost> _paged = PagedController<TeaPost>(
    fetch: (int page) async {
      final r = await ApiClient.instance.getTeahouseTopicPosts(
        widget.topicId,
        page: page,
      );
      return PagedResult<TeaPost>(
        items: r.items
            .map((Map<String, dynamic> e) => TeaPost.fromJson(e))
            .toList(),
        hasMore: r.hasNext,
      );
    },
    onChanged: () {
      if (mounted) setState(() {});
    },
    firstLoadError: '帖子加载失败，请稍后重试',
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
    if (_scrollController.position.extentAfter < 300) {
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
      appBar: AppBar(title: Text('#${widget.topicName}')),
      body: _paged.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _paged.error != null && _paged.items.isEmpty
          ? ErrorState(message: _paged.error!, onRetry: _paged.refresh)
          : _paged.items.isEmpty
          ? const Center(child: Text('该话题下还没有帖子'))
          : AppRefreshIndicator(
              onRefresh: _paged.refresh,
              child: ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: wideInset(
                    MediaQuery.sizeOf(context).width,
                    maxWidth: WideContent.reading.maxWidth,
                  ),
                ),
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
