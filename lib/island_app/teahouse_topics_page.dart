import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/models/teapost.dart';
import 'package:dna/island_app/teahouse_post_page.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/teahouse_post_tile.dart';
import 'package:dna/island_app/widgets/state_views.dart';

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
        _error = '$e';
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
                  ? const EmptyState(
                      icon: Icons.tag,
                      title: '暂无话题',
                    )
                  : AppRefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _topics.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: scheme.outlineVariant),
                        itemBuilder: (context, i) {
                          final t = _topics[i];
                          final name = (t['name'] ?? '').toString();
                          final count =
                              (t['post_count'] as num?)?.toInt() ?? 0;
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
      final r = await ApiClient.instance
          .getTeahouseTopicPosts(widget.topicId, page: 1);
      if (!mounted) return;
      setState(() {
        _posts = r.items.map((e) => TeaPost.fromJson(e)).toList();
        _page = 1;
        _loading = false;
        _noMore = !r.hasNext;
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
      final r = await ApiClient.instance
          .getTeahouseTopicPosts(widget.topicId, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _posts = <TeaPost>[..._posts, ...r.items.map((e) => TeaPost.fromJson(e))];
        _page += 1;
        _loadingMore = false;
        if (!r.hasNext) _noMore = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
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
      appBar: AppBar(title: Text('#${widget.topicName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _posts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _reload, child: const Text('重试')),
                    ],
                  ),
                )
              : _posts.isEmpty
                  ? const Center(child: Text('该话题下还没有帖子'))
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
