import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/me_page.dart';
import 'package:dna/island_app/models/teapost.dart';
import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/island_app/teahouse_post_page.dart';
import 'package:dna/widgets/wide_body.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/card_tile.dart';
import 'package:dna/widgets/load_more_list.dart';
import 'package:dna/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/responsive_card_grid.dart';
import 'package:dna/island_app/widgets/teahouse_post_tile.dart';
import 'package:dna/island_app/widgets/user_badge.dart';
import 'package:dna/island_app/widgets/world_list_tile.dart';
import 'package:dna/island_app/world_detail_page.dart';
import 'package:dna/utils/error_display.dart';
import 'package:dna/widgets/paged_controller.dart';
import '../theme/tokens.dart';

/// 搜索结果类型。
enum SearchTab { all, cards, worlds, users, posts }

/// 全站搜索页：支持角色卡 / 世界卡 / 用户 / 茶馆帖。
///
/// 世界卡此前**完全不在全站搜索里** —— 后端一直在给世界卡建倒排索引
/// （search_service.DOC_WORLD，含词条名与触发词），但搜索页没有这个 tab，
/// 于是「找一本世界书」只能去世界栏目里一页页翻。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;

  /// 已提交的搜索词（≠ 输入框里正在编辑的文字）。
  ///
  /// 同时兼任「搜没搜过」：空串 = 还没搜，结果区显示「输入关键词开始搜索」。
  /// 原来是一个独立的 `_searched` 布尔，和 `_query` 会各自漂移（清空输入框时
  /// 一处清了一处没清），现在只留一个真源。
  String _query = '';

  /// tab 元数据：顺序既是 TabBar 顺序，也是 TabBarView 的顺序。
  ///
  /// 以前这里是裸 int 状态 + 手搭一条「SizedBox(48) + Row + Expanded + InkWell」
  /// 的假 tab 条：没有指示器、选中态只靠颜色、读屏也念不出「选项卡」
  /// （审计 3.1）。现在交给 M3 的 TabBar + TabBarView。
  static const List<(SearchTab, String, IconData)> _tabMeta =
      <(SearchTab, String, IconData)>[
        (SearchTab.all, '全部', Icons.apps_outlined),
        (SearchTab.cards, '角色卡', Icons.badge_outlined),
        (SearchTab.worlds, '世界', Icons.public_outlined),
        (SearchTab.users, '用户', Icons.person_outline),
        (SearchTab.posts, '茶馆帖', Icons.local_cafe_outlined),
      ];

  late final TabController _tabController = TabController(
    length: _tabMeta.length,
    vsync: this,
  );

  /// 角色卡排序（只作用于角色卡这一支，与改造前一致）。
  String _sort = 'relevance';

  // —— 四类结果的分页状态 ——
  //
  // 「加载中 / 加载更多 / 有没有下一页 / 页码 / 错误」这 16 个字段以前每个 tab
  // 各抄一份（`_cardsDone/_cardsPage/_cardsHasMore/_cardsLoadingMore` × 4），
  // 外加 4 份 `_loadXxx` 和 4 支 `_onScroll` 里的手写守卫。现在四类各自只是
  // 一个共享 [PagedController]，本页只回答「怎么取第 page 页」。
  //
  // 分页语义**逐支保持原样**：角色卡 / 用户 / 茶馆帖走接口的 `hasNext`
  // （页码从 1 开始），世界卡那支走裸 Map 的 `has_next`。

  late final PagedController<Map<String, dynamic>> _cardsPaged =
      PagedController<Map<String, dynamic>>(
        fetch: (int page) async {
          final r = await ApiClient.instance.searchCards(
            _query,
            page: page,
            sort: _sort,
          );
          return PagedResult<Map<String, dynamic>>(
            items: r.items,
            hasMore: r.hasNext,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        firstLoadError: '角色卡搜索失败，请稍后重试',
      );

  late final PagedController<WorldCardSummary> _worldsPaged =
      PagedController<WorldCardSummary>(
        fetch: (int page) async {
          final Map<String, dynamic> data = await ApiClient.instance.getWorlds(
            page: page,
            query: _query,
          );
          final Object? raw = data['items'];
          final List<WorldCardSummary> items = raw is List
              ? raw
                    .whereType<Map>()
                    .map(
                      (Map e) => WorldCardSummary.fromJson(
                        e.cast<String, dynamic>(),
                      ),
                    )
                    .where((WorldCardSummary w) => w.id.isNotEmpty)
                    .toList()
              : <WorldCardSummary>[];
          return PagedResult<WorldCardSummary>(
            items: items,
            // 世界卡接口这一支用 has_next，别跟上面三支统一掉。
            hasMore: data['has_next'] == true,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        firstLoadError: '世界卡搜索失败，请稍后重试',
      );

  late final PagedController<Map<String, dynamic>> _usersPaged =
      PagedController<Map<String, dynamic>>(
        fetch: (int page) async {
          final r = await ApiClient.instance.searchUsers(_query, page: page);
          return PagedResult<Map<String, dynamic>>(
            items: r.items,
            hasMore: r.hasNext,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        firstLoadError: '用户搜索失败，请稍后重试',
      );

  late final PagedController<Map<String, dynamic>> _postsPaged =
      PagedController<Map<String, dynamic>>(
        fetch: (int page) async {
          final r = await ApiClient.instance.searchTeahousePosts(
            _query,
            page: page,
          );
          return PagedResult<Map<String, dynamic>>(
            items: r.items,
            hasMore: r.hasNext,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        firstLoadError: '茶馆帖搜索失败，请稍后重试',
      );

  // —— 实时下拉建议 ——
  Timer? _suggestDebounce;
  List<Map<String, dynamic>> _suggestCards = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _suggestUsers = const <Map<String, dynamic>>[];
  bool _suggestLoading = false;

  /// 分页滚动回调是按 tab 走的，而 TabBarView 会让相邻 tab 同时挂在树上
  /// （滑动过渡期间两页都在场）。因此每个分页 tab 各拿一个 ScrollController：
  /// 共用一个会在过渡帧里触发「attached to multiple scroll views」断言。
  final ScrollController _cardsScroll = ScrollController();
  final ScrollController _worldsScroll = ScrollController();
  final ScrollController _usersScroll = ScrollController();
  final ScrollController _postsScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _query = widget.initialQuery;
    _controller.addListener(_onTextChanged);
    _cardsScroll.addListener(() => _onScroll(_cardsScroll));
    _worldsScroll.addListener(() => _onScroll(_worldsScroll));
    _usersScroll.addListener(() => _onScroll(_usersScroll));
    _postsScroll.addListener(() => _onScroll(_postsScroll));
    if (_query.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _suggestDebounce?.cancel();
    _tabController.dispose();
    _cardsScroll.dispose();
    _worldsScroll.dispose();
    _usersScroll.dispose();
    _postsScroll.dispose();
    _cardsPaged.dispose();
    _worldsPaged.dispose();
    _usersPaged.dispose();
    _postsPaged.dispose();
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
    _suggestDebounce = Timer(AppMotion.medium, () => _loadSuggest(q));
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

  /// 输入框里正在编辑的文字与「已提交的搜索词」不一致时，展示实时下拉建议。
  bool get _showSuggest =>
      _controller.text.trim().isNotEmpty && _controller.text.trim() != _query;

  /// 提交搜索：换了搜索词 ⇒ 四类结果**先清空、再按新条件重取**。
  ///
  /// 为什么先 `items.clear()` 再 `refresh()`：[PagedController] 刷新失败时按
  /// 设计保留旧列表（翻页中途失败用户还能看已有内容），换成新搜索词时那就会把
  /// 上一个关键词的结果留在屏幕上。清空是页面级语义，放在页面里做。
  ///
  /// 四类并发跑：一次搜索 = 一次请求打底，四个 tab 同时就绪。
  Future<void> _search() async {
    final String q = _controller.text.trim();
    if (q.isEmpty) {
      _clearResults();
      return;
    }
    setState(() {
      _query = q;
      _cardsPaged.items.clear();
      _worldsPaged.items.clear();
      _usersPaged.items.clear();
      _postsPaged.items.clear();
    });
    await Future.wait(<Future<void>>[
      _cardsPaged.refresh(),
      _worldsPaged.refresh(),
      _usersPaged.refresh(),
      _postsPaged.refresh(),
    ]);
  }

  /// 搜索词被清空：回到「输入关键词开始搜索」，四类结果一起清掉。
  ///
  /// 旧实现在这里漏清 `_worlds`（只清了另三类），现在四类一起清。
  void _clearResults() {
    setState(() {
      _query = '';
      _cardsPaged.items.clear();
      _worldsPaged.items.clear();
      _usersPaged.items.clear();
      _postsPaged.items.clear();
    });
  }

  /// 换了排序：先把旧排序的结果清掉再重取（失败不残留旧排序的列表）。
  void _reloadCards() {
    setState(() => _cardsPaged.items.clear());
    _cardsPaged.refresh();
  }

  void _openWorld(WorldCardSummary w) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorldDetailPage(id: w.id, fallbackName: w.name),
      ),
    );
  }

  /// 滚动接近底部时给**这个滚动视图所属的 tab** 加载下一页。
  ///
  /// 判断依据从「当前 tab 是哪个」换成「是哪个 ScrollController 在滚」：
  /// TabBarView 过渡期间两页都可能在场，只有真正在滚的那一页该翻页。
  ///
  /// 「还有没有下一页 / 是不是正在加载」这些守卫都收进了
  /// [PagedController.loadMore]（幂等），这里只负责把球传给对应的那一支。
  void _onScroll(ScrollController c) {
    if (!c.hasClients) return;
    final pos = c.position;
    // 阈值与判定公式来自共享分页工具（原来是就地写死的 -300）。
    if (!isNearScrollEnd(pos, threshold: kLoadMoreFeedThreshold)) return;
    if (identical(c, _cardsScroll)) {
      _cardsPaged.loadMore();
    } else if (identical(c, _worldsScroll)) {
      _worldsPaged.loadMore();
    } else if (identical(c, _usersScroll)) {
      _usersPaged.loadMore();
    } else if (identical(c, _postsScroll)) {
      _postsPaged.loadMore();
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
        builder: (_) =>
            UserProfilePage(username: (user['username'] ?? '').toString()),
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
    showSnack(context, msg);
  }

  /// 更新搜索结果里某条帖的 stats（就地替换控制器里的那一项）。
  void _updatePostStats(int id, void Function(Map<String, dynamic>) apply) {
    setState(() {
      final List<Map<String, dynamic>> items = _postsPaged.items;
      for (int i = 0; i < items.length; i++) {
        final Map<String, dynamic> p = items[i];
        final pid = p['id'] is num
            ? (p['id'] as num).toInt()
            : int.tryParse('${p['id']}');
        if (pid != id) continue;
        final stats = <String, dynamic>{
          if (p['stats'] is Map)
            ...((p['stats'] as Map).map((k, v) => MapEntry(k.toString(), v))),
        };
        apply(stats);
        items[i] = <String, dynamic>{...p, 'stats': stats};
      }
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
    } catch (e) {
      _snack('操作失败：${describeError(e)}');
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
    } catch (e) {
      _snack('操作失败：${describeError(e)}');
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
              hintText: '搜索角色卡 / 世界卡 / 用户 / 茶馆帖',
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  _controller.clear();
                  _clearResults();
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
        padding: EdgeInsets.symmetric(
          horizontal: wideInset(
            MediaQuery.sizeOf(context).width,
            maxWidth: WideContent.list.maxWidth,
          ),
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: <Widget>[
          if (_suggestLoading)
            const Padding(
              padding: AppInsets.card,
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
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: Text('无匹配建议')),
            ),
          if (_suggestCards.isNotEmpty) ...<Widget>[
            const _SectionHeader('角色卡'),
            ..._suggestCards.map(
              (c) => ListTile(
                dense: true,
                leading: const Icon(Icons.badge_outlined, size: 20),
                title: Text(
                  (c['name'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.north_west, size: 16),
                onTap: () => _openCard(c),
              ),
            ),
          ],
          if (_suggestUsers.isNotEmpty) ...<Widget>[
            const _SectionHeader('作者'),
            ..._suggestUsers.map(
              (u) => ListTile(
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
                subtitle: Text(
                  '@${u['username'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.north_west, size: 16),
                onTap: () => _openUser(u),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 五个平级视图（同一次查询的不同切面）⇒ M3 的 tab。
  ///
  /// 旧实现是手搭的一条 48 高 Row + InkWell：没有指示器、选中态只有颜色，
  /// 而且两支字重都写了 w500（死代码）。TabBar 自带指示器、选中态、
  /// 「选项卡 / 已选中」的读屏语义与键盘左右切换（审计 3.1）。
  /// 图标 + 文字是 M3 primary tabs 的标准形态。
  Widget _buildTabs() {
    return TabBar(
      controller: _tabController,
      tabs: <Widget>[
        for (final (SearchTab, String, IconData) t in _tabMeta)
          Tab(icon: Icon(t.$3), text: t.$2),
      ],
    );
  }

  Widget _buildResults() {
    // 五个 tab 是同一查询的平级切面：交给 TabBarView 负责切换动画、
    // 懒构建（不可见的 tab 不会建），以及左右滑动。
    return TabBarView(
      controller: _tabController,
      children: <Widget>[
        _resultsShell(
          // 「全部」是四类的汇总：还没全回来就别画半张，任一支还在首屏
          // 加载/刷新就整体转圈（与改造前的全局 loading 一致）。
          loading: _anyLoading,
          error: _allError,
          empty:
              _cardsPaged.isEmpty &&
              _worldsPaged.isEmpty &&
              _usersPaged.isEmpty &&
              _postsPaged.isEmpty,
          emptyText: '未找到相关结果',
          body: _allResults,
        ),
        _resultsShell(
          loading: _cardsPaged.isLoading,
          error: _cardsPaged.error,
          empty: _cardsPaged.isEmpty,
          emptyText: '未找到相关角色卡',
          withSortBar: true,
          body: _cardResults,
        ),
        _resultsShell(
          loading: _worldsPaged.isLoading,
          error: _worldsPaged.error,
          empty: _worldsPaged.isEmpty,
          emptyText: '未找到相关世界卡',
          body: _worldResults,
        ),
        _resultsShell(
          loading: _usersPaged.isLoading,
          error: _usersPaged.error,
          empty: _usersPaged.isEmpty,
          emptyText: '未找到相关用户',
          body: _userResults,
        ),
        _resultsShell(
          loading: _postsPaged.isLoading,
          error: _postsPaged.error,
          empty: _postsPaged.isEmpty,
          emptyText: '未找到相关茶馆帖',
          body: _postResults,
        ),
      ],
    );
  }

  /// 四类里还有没有在首屏/刷新加载的。
  bool get _anyLoading =>
      _cardsPaged.isLoading ||
      _worldsPaged.isLoading ||
      _usersPaged.isLoading ||
      _postsPaged.isLoading;

  /// 「全部」tab 的错误：**四类都空**才算整体失败。
  ///
  /// 只有一支挂了时其余能看的先给用户看（单类错误切到对应 tab 去看）。
  /// 旧实现在这里其实没有错误态（`_error` 只在一段永远走不到的 try/catch 里
  /// 赋值），现在才真正生效。
  String? get _allError {
    if (_cardsPaged.items.isNotEmpty ||
        _worldsPaged.items.isNotEmpty ||
        _usersPaged.items.isNotEmpty ||
        _postsPaged.items.isNotEmpty) {
      return null;
    }
    return _cardsPaged.error ??
        _worldsPaged.error ??
        _usersPaged.error ??
        _postsPaged.error;
  }

  /// 五个 tab 共用的「未搜索 / 加载中 / 出错 / 空 / 结果」外壳。
  ///
  /// 搜索是一次请求打底（_search 并发拉四类），四个结果 tab 的状态判断必须
  /// 长得一样；把状态判断收在这一处，body 仍是各 tab 原本的结果视图，状态数据
  /// 则全部来自各自的分页控制器。排序条只属于「角色卡」，位置与改造前一致
  /// （tab 下、结果上；加载中 / 出错时不显示，只在展示结果时有意义）。
  Widget _resultsShell({
    required Widget Function() body,
    required bool loading,
    required bool empty,
    required String emptyText,
    String? error,
    bool withSortBar = false,
  }) {
    if (_query.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 8),
            const Text('输入关键词开始搜索'),
          ],
        ),
      );
    }
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _search, child: const Text('重试')),
          ],
        ),
      );
    }
    final Widget content = empty ? Center(child: Text(emptyText)) : body();
    if (!withSortBar) {
      return content;
    }
    return Column(
      children: <Widget>[_buildSortBar(), Expanded(child: content)],
    );
  }

  /// 角色卡排序（相关度 / 最热 / 最新），对齐网页版 search。
  ///
  /// 排序：互斥 3 项、常显 → SegmentedButton（与探索 / 世界 / 茶馆 / 评论区
  /// 同一个控件）。原来这里是一行手搭的等宽 InkWell —— 选中态只有颜色，
  /// 而且两个分支的字重都写成 w500（死代码）。
  Widget _buildSortBar() {
    const sorts = <(String, String)>[
      ('relevance', '相关度'),
      ('hot', '最热'),
      ('new', '最新'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<String>(
          segments: <ButtonSegment<String>>[
            for (final (String key, String label) in sorts)
              ButtonSegment<String>(value: key, label: Text(label)),
          ],
          selected: <String>{_sort},
          onSelectionChanged: (Set<String> picked) {
            final String next = picked.first;
            if (next == _sort) return;
            setState(() => _sort = next);
            _reloadCards();
          },
          // 不压密度：M3 默认高度 40dp 就是本项目的行为下限
          // （与探索/世界页的排序控件一致；compact 会把它压到 36）。

        ),
      ),
    );
  }

  Widget _cardResults() {
    return AppRefreshIndicator(onRefresh: _search, child: _cardGrid());
  }

  Widget _cardGrid() {
    // 列数与格子比例来自 [cardGridMetrics]（与 explore / 我的收藏 / 骨架屏同一套
    // 算法）。原来这里写死 maxCrossAxisExtent 220 + childAspectRatio 0.62，
    // 算出来的格子比别处矮一截，同一张卡在不同页面高宽比都不一样（审计 3.3）。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final CardGridMetrics m = cardGridMetrics(
          constraints.maxWidth - AppInsets.card.horizontal,
          // 搜索结果比浏览页更密一档：单列最小 220 而不是 200。
          minColumnWidth: 220,
        );
        return GridView.builder(
          controller: _cardsScroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppInsets.card,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: m.columns,
            mainAxisSpacing: kCardGridSpacing,
            crossAxisSpacing: kCardGridSpacing,
            childAspectRatio: m.childAspectRatio,
          ),
          itemCount:
              _cardsPaged.items.length + (_cardsPaged.isLoadingMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= _cardsPaged.items.length) {
              return const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return CardTile(
              card: _cardsPaged.items[i],
              onTap: () => _openCard(_cardsPaged.items[i]),
            );
          },
        );
      },
    );
  }

  Widget _worldResults() {
    return AppRefreshIndicator(
      onRefresh: _search,
      child: ListView.separated(
        controller: _worldsScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount:
            _worldsPaged.items.length + (_worldsPaged.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
        itemBuilder: (context, i) {
          if (i >= _worldsPaged.items.length) {
            return const Padding(
              padding: AppInsets.card,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _worldTile(_worldsPaged.items[i]);
        },
      ),
    );
  }

  /// 世界卡搜索结果一行。
  ///
  /// 与「我的」页共用 [WorldListTile]：同一实体、同一语境（列表 / 定位）
  /// 就该是同一种行；搜索这边只是多一个 leading 图标（提示「这是一条世界」）
  /// 和「作者名」这段补充元信息（审计 3.3：世界卡曾有三种形态）。
  Widget _worldTile(WorldCardSummary w) {
    return WorldListTile(
      world: w,
      leadingIcon: Icons.public_outlined,
      extraMeta: w.authorName.isEmpty ? null : w.authorName,
      onTap: () => _openWorld(w),
    );
  }

  Widget _userResults() {
    return AppRefreshIndicator(
      onRefresh: _search,
      child: ListView.separated(
        controller: _usersScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          vertical: 8,
          horizontal: wideInset(
            MediaQuery.sizeOf(context).width,
            maxWidth: WideContent.grid.maxWidth,
          ),
        ),
        itemCount:
            _usersPaged.items.length + (_usersPaged.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) {
          if (i >= _usersPaged.items.length) {
            return const Padding(
              padding: AppInsets.card,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _userTile(_usersPaged.items[i]);
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
    final isSelf =
        u['username'] == (AuthSession.instance.user?['username'] ?? '');
    return ListTile(
      leading: Stack(
        alignment: Alignment.bottomRight,
        children: <Widget>[
          Avatar(avatar: avatar, radius: 24),
          if (verified)
            Padding(
              padding: const EdgeInsets.only(right: 0, bottom: 0),
              child: Icon(
                Icons.verified,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
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
      subtitle: Text(
        '@$username',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _loggedIn && !isSelf
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: () => _toggleFollow(u),
              child: Text(isFollowing ? '已关注' : '关注'),
            )
          : const Icon(Icons.chevron_right),
      onTap: () => _openUser(u),
    );
  }

  /// 就地改控制器里该用户的关注态（乐观更新 / 失败回滚都走这里）。
  void _setUserFollowing(String username, bool following) {
    setState(() {
      final List<Map<String, dynamic>> items = _usersPaged.items;
      for (int i = 0; i < items.length; i++) {
        final Map<String, dynamic> u = items[i];
        if ((u['username'] ?? '') != username) continue;
        items[i] = <String, dynamic>{...u, 'is_following': following};
      }
    });
  }

  Future<void> _toggleFollow(Map<String, dynamic> user) async {
    if (!_loggedIn) {
      _snack('请先登录后再关注');
      return;
    }
    final username = (user['username'] ?? '').toString();
    final isFollowing = user['is_following'] == true;
    // 乐观更新。
    _setUserFollowing(username, !isFollowing);
    try {
      final nowFollowing = await ApiClient.instance.toggleFollow(username);
      if (!mounted) return;
      _setUserFollowing(username, nowFollowing);
      _snack(nowFollowing ? '已关注' : '已取消关注');
    } catch (e) {
      if (!mounted) return;
      // 失败回滚。
      _setUserFollowing(username, isFollowing);
      _snack('操作失败：${describeError(e)}');
    }
  }

  Widget _postResults() {
    return AppRefreshIndicator(
      onRefresh: _search,
      child: ListView.builder(
        controller: _postsScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount:
            _postsPaged.items.length + (_postsPaged.isLoadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _postsPaged.items.length) {
            return const Padding(
              padding: AppInsets.card,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final post = TeaPost.fromJson(_postsPaged.items[i]);
          return TeahousePostTile(
            post: post,
            onTap: () => _openPost(_postsPaged.items[i]),
            onLike: () => _togglePostLike(_postsPaged.items[i]),
            onFavorite: () => _togglePostFavorite(_postsPaged.items[i]),
          );
        },
      ),
    );
  }

  Widget _allResults() {
    return AppRefreshIndicator(
      onRefresh: _search,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          if (_cardsPaged.items.isNotEmpty) ...<Widget>[
            const _SectionHeader('角色卡'),
            ..._cardsPaged.items.map(
              (c) => ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(
                  (c['name'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  (c['intro'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openCard(c),
              ),
            ),
          ],
          if (_worldsPaged.items.isNotEmpty) ...<Widget>[
            const _SectionHeader('世界卡'),
            ..._worldsPaged.items.take(10).map(
              (w) => ListTile(
                leading: const Icon(Icons.public_outlined),
                title: Text(
                  w.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  w.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openWorld(w),
              ),
            ),
          ],
          if (_usersPaged.items.isNotEmpty) ...<Widget>[
            const _SectionHeader('用户'),
            ..._usersPaged.items.take(10).map(
              (u) => ListTile(
                leading: Avatar(avatar: (u['avatar'] ?? '').toString()),
                title: Text(
                  (u['nickname'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '@${u['username'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openUser(u),
              ),
            ),
          ],
          if (_postsPaged.items.isNotEmpty) ...<Widget>[
            const _SectionHeader('茶馆帖'),
            ..._postsPaged.items.take(10).map((p) {
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
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }
}
