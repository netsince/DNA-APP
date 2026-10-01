import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/me_page.dart';
import 'package:dna/island_app/models/teapost.dart';
import 'package:dna/island_app/teahouse_post_page.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/card_tile.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/teahouse_post_tile.dart';
import 'package:dna/island_app/widgets/user_badge.dart';

/// 搜索结果类型。
enum SearchTab { all, cards, users, posts }

/// 全站搜索页：支持角色卡 / 用户 / 茶馆帖，对齐网页版 /search。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _controller;
  late String _query;

  SearchTab _tab = SearchTab.all;
  String _sort = 'relevance';

  // 卡片搜索结果。
  List<Map<String, dynamic>> _cards = const <Map<String, dynamic>>[];
  bool _cardsDone = false;
  int _cardsPage = 1;
  bool _cardsHasMore = false;
  bool _cardsLoadingMore = false;
  // 用户搜索结果。
  List<Map<String, dynamic>> _users = const <Map<String, dynamic>>[];
  bool _usersDone = false;
  int _usersPage = 1;
  bool _usersHasMore = false;
  bool _usersLoadingMore = false;
  // 茶馆帖搜索结果。
  List<Map<String, dynamic>> _posts = const <Map<String, dynamic>>[];
  bool _postsDone = false;
  int _postsPage = 1;
  bool _postsHasMore = false;
  bool _postsLoadingMore = false;

  bool _loading = false;
  bool _searched = false;
  String? _error;

  // —— 实时下拉建议 ——
  Timer? _suggestDebounce;
  List<Map<String, dynamic>> _suggestCards = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _suggestUsers = const <Map<String, dynamic>>[];
  bool _suggestLoading = false;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _query = widget.initialQuery;
    _controller.addListener(_onTextChanged);
    _scrollController.addListener(() => _onScroll(_scrollController));
    if (_query.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _suggestDebounce?.cancel();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _suggestDebounce?.cancel();
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() {
        _suggestCards = const <Map<String, dynamic>>[];
        _suggestUsers = const <Map<String, dynamic>>[];
        _suggestLoading = false;
      });
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 300), () => _loadSuggest(q));
  }

  Future<void> _loadSuggest(String q) async {
    setState(() => _suggestLoading = true);
    try {
      final r = await ApiClient.instance.getSearchSuggest(q);
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _suggestCards = r.cards;
        _suggestUsers = r.users;
        _suggestLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestCards = const <Map<String, dynamic>>[];
        _suggestUsers = const <Map<String, dynamic>>[];
        _suggestLoading = false;
      });
    }
  }

  bool get _showSuggest =>
      _controller.text.trim().isNotEmpty &&
      (!_searched || _controller.text.trim() != _query);

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() {
        _searched = false;
        _error = null;
        _cards = const <Map<String, dynamic>>[];
        _users = const <Map<String, dynamic>>[];
        _posts = const <Map<String, dynamic>>[];
        _cardsHasMore = false;
        _usersHasMore = false;
        _postsHasMore = false;
      });
      return;
    }
    setState(() {
      _query = q;
      _loading = true;
      _searched = true;
      _error = null;
      _cardsPage = 1;
      _usersPage = 1;
      _postsPage = 1;
    });
    try {
      final Future<void> cardsF = _loadCards(q, reset: true);
      final Future<void> usersF = _loadUsers(q, reset: true);
      final Future<void> postsF = _loadPosts(q, reset: true);
      await Future.wait(<Future<void>>[cardsF, usersF, postsF]);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadCards(String q, {bool reset = false}) async {
    try {
      final page = reset ? 1 : _cardsPage + 1;
      final r = await ApiClient.instance.searchCards(q, page: page, sort: _sort);
      if (!mounted) return;
      setState(() {
        _cards = reset ? r.items : <Map<String, dynamic>>[..._cards, ...r.items];
        _cardsPage = page;
        _cardsHasMore = r.hasNext;
        _cardsDone = true;
        _cardsLoadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _cardsDone = true;
          _cardsLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadUsers(String q, {bool reset = false}) async {
    try {
      final page = reset ? 1 : _usersPage + 1;
      final r = await ApiClient.instance.searchUsers(q, page: page);
      if (!mounted) return;
      setState(() {
        _users = reset ? r.items : <Map<String, dynamic>>[..._users, ...r.items];
        _usersPage = page;
        _usersHasMore = r.hasNext;
        _usersDone = true;
        _usersLoadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _usersDone = true;
          _usersLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadPosts(String q, {bool reset = false}) async {
    try {
      final page = reset ? 1 : _postsPage + 1;
      final r = await ApiClient.instance.searchTeahousePosts(q, page: page);
      if (!mounted) return;
      setState(() {
        _posts = reset ? r.items : <Map<String, dynamic>>[..._posts, ...r.items];
        _postsPage = page;
        _postsHasMore = r.hasNext;
        _postsDone = true;
        _postsLoadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _postsDone = true;
          _postsLoadingMore = false;
        });
      }
    }
  }

  /// 滚动接近底部时按当前 tab 加载下一页。
  void _onScroll(ScrollController c) {
    if (!c.hasClients) return;
    final pos = c.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      if (_tab == SearchTab.cards && _cardsHasMore && !_cardsLoadingMore && !_loading) {
        setState(() => _cardsLoadingMore = true);
        _loadCards(_query);
      } else if (_tab == SearchTab.users && _usersHasMore && !_usersLoadingMore && !_loading) {
        setState(() => _usersLoadingMore = true);
        _loadUsers(_query);
      } else if (_tab == SearchTab.posts && _postsHasMore && !_postsLoadingMore && !_loading) {
        setState(() => _postsLoadingMore = true);
        _loadPosts(_query);
      }
    }
  }

  void _openCard(Map<String, dynamic> card) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardDetailPage(cardId: (card['id'] ?? '').toString()),
      ),
    );
  }

  void _openUser(Map<String, dynamic> user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(
          username: (user['username'] ?? '').toString(),
        ),
      ),
    );
  }

  void _openPost(Map<String, dynamic> post) {
    final id = post['id'];
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeahousePostPage(
          postId: id is num ? id.toInt() : int.tryParse('$id') ?? 0,
        ),
      ),
    );
  }

  bool get _loggedIn => AuthSession.instance.isLoggedIn;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 更新搜索结果里某条帖的 stats。
  void _updatePostStats(int id, void Function(Map<String, dynamic>) apply) {
    setState(() {
      _posts = _posts.map((p) {
        final pid = p['id'] is num
            ? (p['id'] as num).toInt()
            : int.tryParse('${p['id']}');
        if (pid != id) return p;
        final stats = <String, dynamic>{
          if (p['stats'] is Map) ...((p['stats'] as Map).map(
              (k, v) => MapEntry(k.toString(), v))),
        };
        apply(stats);
        return <String, dynamic>{...p, 'stats': stats};
      }).toList();
    });
  }

  Future<void> _togglePostLike(Map<String, dynamic> post) async {
    if (!_loggedIn) {
      _snack('请先登录后再点赞');
      return;
    }
    final id = post['id'] is num
        ? (post['id'] as num).toInt()
        : int.tryParse('${post['id']}');
    if (id == null) return;
    try {
      final r = await ApiClient.instance.toggleTeahouseLike(id);
      if (!mounted) return;
      _updatePostStats(id, (s) {
        s['liked'] = r.liked;
        s['like_count'] = r.count;
      });
    } catch (_) {
      _snack('操作失败，请重试');
    }
  }

  Future<void> _togglePostFavorite(Map<String, dynamic> post) async {
    if (!_loggedIn) {
      _snack('请先登录后再收藏');
      return;
    }
    final id = post['id'] is num
        ? (post['id'] as num).toInt()
        : int.tryParse('${post['id']}');
    if (id == null) return;
    try {
      final r = await ApiClient.instance.toggleTeahouseFavorite(id);
      if (!mounted) return;
      _updatePostStats(id, (s) => s['favorited'] = r.favorited);
      _snack(r.favorited ? '已收藏' : '已取消收藏');
    } catch (_) {
      _snack('操作失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: _controller,
            autofocus: widget.initialQuery.isEmpty,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: '搜索角色卡 / 用户 / 茶馆帖',
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  _controller.clear();
                  setState(() {
                    _searched = false;
                    _error = null;
                    _cards = const <Map<String, dynamic>>[];
                    _users = const <Map<String, dynamic>>[];
                    _posts = const <Map<String, dynamic>>[];
                  });
                },
              ),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: _search, child: const Text('搜索')),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_showSuggest)
            _buildSuggestPanel()
          else ...[
            _buildTabs(),
            const Divider(height: 1),
            Expanded(child: _buildResults()),
          ],
        ],
      ),
    );
  }

  /// 实时下拉建议面板：匹配的角色卡 + 作者。
  Widget _buildSuggestPanel() {
    return Expanded(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: <Widget>[
          if (_suggestLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (!_suggestLoading &&
              _suggestCards.isEmpty &&
              _suggestUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('无匹配建议')),
            ),
          if (_suggestCards.isNotEmpty) ...<Widget>[
            const _SectionHeader('角色卡'),
            ..._suggestCards.map((c) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.badge_outlined, size: 20),
                  title: Text((c['name'] ?? '').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.north_west, size: 16),
                  onTap: () => _openCard(c),
                )),
          ],
          if (_suggestUsers.isNotEmpty) ...<Widget>[
            const _SectionHeader('作者'),
            ..._suggestUsers.map((u) => ListTile(
                  dense: true,
                  leading: Avatar(
                    avatar: (u['avatar'] ?? '').toString(),
                    radius: 18,
                  ),
                  title: UserBadge(
                    name: (u['nickname'] ?? '').toString(),
                    isSponsor: u['is_sponsor'] == true,
                    verified: u['verified'] == true,
                    verifiedLabel: (u['verified_label'] ?? '').toString(),
                  ),
                  subtitle: Text('@${u['username'] ?? ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.north_west, size: 16),
                  onTap: () => _openUser(u),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildTabs() {
    const tabs = <(SearchTab, String, IconData)>[
      (SearchTab.all, '全部', Icons.apps_outlined),
      (SearchTab.cards, '角色卡', Icons.badge_outlined),
      (SearchTab.users, '用户', Icons.person_outline),
      (SearchTab.posts, '茶馆帖', Icons.local_cafe_outlined),
    ];
    return SizedBox(
      height: 48,
      child: Row(
        children: tabs.map((t) {
          final selected = _tab == t.$1;
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _tab = t.$1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(t.$3,
                          size: 16,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        t.$2,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w500 : FontWeight.w500,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildResults() {
    if (!_searched) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('输入关键词开始搜索'),
          ],
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _search, child: const Text('重试')),
          ],
        ),
      );
    }

    switch (_tab) {
      case SearchTab.cards:
        return Column(children: <Widget>[
          _buildSortBar(),
          Expanded(child: _cardResults()),
        ]);
      case SearchTab.users:
        return _userResults();
      case SearchTab.posts:
        return _postResults();
      case SearchTab.all:
        return _allResults();
    }
  }

  /// 角色卡排序（相关度 / 最热 / 最新），对齐网页版 search。
  Widget _buildSortBar() {
    const sorts = <(String, String)>[
      ('relevance', '相关度'),
      ('hot', '最热'),
      ('new', '最新'),
    ];
    return SizedBox(
      height: 44,
      child: Row(
        children: sorts.map((s) {
          final selected = _sort == s.$1;
          return Expanded(
            child: InkWell(
              onTap: () {
                if (_sort == s.$1) return;
                setState(() => _sort = s.$1);
                _loadCards(_query, reset: true);
              },
              child: Center(
                child: Text(
                  s.$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w500,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _cardResults() {
    if (_cardsDone && _cards.isEmpty) {
      return const Center(child: Text('未找到相关角色卡'));
    }
    return AppRefreshIndicator(onRefresh: _search, child: _cardGrid());
  }

  Widget _cardGrid() {
    return GridView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.62,
      ),
      itemCount: _cards.length + (_cardsLoadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _cards.length) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return CardTile(
          card: _cards[i],
          onTap: () => _openCard(_cards[i]),
        );
      },
    );
  }

  Widget _userResults() {
    if (_usersDone && _users.isEmpty) {
      return const Center(child: Text('未找到相关用户'));
    }
    return AppRefreshIndicator(
      onRefresh: _search,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
      itemCount: _users.length + (_usersLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        if (i >= _users.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _userTile(_users[i]);
      },
      ),
    );
  }

  Widget _userTile(Map<String, dynamic> u) {
    final nickname = (u['nickname'] ?? '').toString();
    final username = (u['username'] ?? '').toString();
    final avatar = (u['avatar'] ?? '').toString();
    final verified = u['verified'] == true;
    final isFollowing = u['is_following'] == true;
    final isSelf = u['username'] == (AuthSession.instance.user?['username'] ?? '');
    return ListTile(
      leading: Stack(
        alignment: Alignment.bottomRight,
        children: <Widget>[
          Avatar(avatar: avatar, radius: 24),
          if (verified)
            Padding(
              padding: const EdgeInsets.only(right: 0, bottom: 0),
              child: Icon(Icons.verified,
                  size: 14, color: Theme.of(context).colorScheme.primary),
            ),
        ],
      ),
      title: UserBadge(
        name: nickname,
        isSponsor: u['is_sponsor'] == true,
        verified: verified,
        verifiedLabel: (u['verified_label'] ?? '').toString(),
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text('@$username',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: _loggedIn && !isSelf
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _toggleFollow(u),
              child: Text(isFollowing ? '已关注' : '关注'),
            )
          : const Icon(Icons.chevron_right),
      onTap: () => _openUser(u),
    );
  }

  Future<void> _toggleFollow(Map<String, dynamic> user) async {
    if (!_loggedIn) {
      _snack('请先登录后再关注');
      return;
    }
    final username = (user['username'] ?? '').toString();
    final isFollowing = user['is_following'] == true;
    // 乐观更新。
    setState(() {
      _users = _users.map((u) {
        if ((u['username'] ?? '') == username) {
          return <String, dynamic>{...u, 'is_following': !isFollowing};
        }
        return u;
      }).toList();
    });
    try {
      final nowFollowing = await ApiClient.instance.toggleFollow(username);
      if (!mounted) return;
      setState(() {
        _users = _users.map((u) {
          if ((u['username'] ?? '') == username) {
            return <String, dynamic>{...u, 'is_following': nowFollowing};
          }
          return u;
        }).toList();
      });
      _snack(nowFollowing ? '已关注' : '已取消关注');
    } catch (_) {
      if (!mounted) return;
      // 失败回滚。
      setState(() {
        _users = _users.map((u) {
          if ((u['username'] ?? '') == username) {
            return <String, dynamic>{...u, 'is_following': isFollowing};
          }
          return u;
        }).toList();
      });
      _snack('操作失败，请重试');
    }
  }

  Widget _postResults() {
    if (_postsDone && _posts.isEmpty) {
      return const Center(child: Text('未找到相关茶馆帖'));
    }
    return AppRefreshIndicator(
      onRefresh: _search,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _posts.length + (_postsLoadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _posts.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final post = TeaPost.fromJson(_posts[i]);
        return TeahousePostTile(
          post: post,
          onTap: () => _openPost(_posts[i]),
          onLike: () => _togglePostLike(_posts[i]),
          onFavorite: () => _togglePostFavorite(_posts[i]),
        );
      },
      ),
    );
  }

  Widget _allResults() {
    final bool nothing =
        _cardsDone && _usersDone && _postsDone && _cards.isEmpty && _users.isEmpty && _posts.isEmpty;
    if (nothing) {
      return const Center(child: Text('未找到相关结果'));
    }
    return AppRefreshIndicator(
      onRefresh: _search,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
        if (_cards.isNotEmpty) ...<Widget>[
          const _SectionHeader('角色卡'),
          ..._cards.map((c) => ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text((c['name'] ?? '').toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text((c['intro'] ?? '').toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openCard(c),
              )),
        ],
        if (_users.isNotEmpty) ...<Widget>[
          const _SectionHeader('用户'),
          ..._users.take(10).map((u) => ListTile(
                leading: Avatar(avatar: (u['avatar'] ?? '').toString()),
                title: Text((u['nickname'] ?? '').toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('@${u['username'] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openUser(u),
              )),
        ],
        if (_posts.isNotEmpty) ...<Widget>[
          const _SectionHeader('茶馆帖'),
          ..._posts.take(10).map((p) {
            final post = TeaPost.fromJson(p);
            return TeahousePostTile(
              post: post,
              onTap: () => _openPost(p),
              onLike: () => _togglePostLike(p),
              onFavorite: () => _togglePostFavorite(p),
            );
          }),
        ],
      ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }
}
