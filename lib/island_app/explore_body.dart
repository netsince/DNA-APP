import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/widgets/responsive_card_grid.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 探索角色卡分页加载回调（默认走 [ApiClient.getExploreCards]）。
typedef ExploreCardsLoader =
    Future<ExploreCardsPage> Function({
  int page,
  String sort,
  String gender,
  String? tag,
});

/// 探索页元数据（性别列表 + 热门标签）加载回调（默认走 [ApiClient.getExploreMeta]）。
typedef ExploreMetaLoader = Future<ExploreMeta> Function();

/// 探索页：性别 / 排序 / 热门标签筛选 + 角色卡网格 + 无限分页。
///
/// 对齐网页版探索页（app/templates/explore.html）的交互：两行横划筛选胶囊栏
/// （性别+排序、标签），下方卡片网格按宽度自适应列数，滚动到底自动加载更多。
/// 筛选变化时重新拉取第一页；点卡片通过 [onOpenCard] 交给外壳打开内置详情页。
class ExploreBody extends StatefulWidget {
  const ExploreBody({super.key, this.onOpenCard, this.cardsLoader, this.metaLoader});

  /// 打开角色卡详情：优先交给外壳（保留侧边栏）；未提供时回退为 push 内置详情页。
  final ValueChanged<String>? onOpenCard;

  /// 注入用：卡片分页加载器（测试时替换为 stub）。
  final ExploreCardsLoader? cardsLoader;

  /// 注入用：探索元数据加载器（测试时替换为 stub）。
  final ExploreMetaLoader? metaLoader;

  @override
  State<ExploreBody> createState() => _ExploreBodyState();
}

class _ExploreBodyState extends State<ExploreBody> {
  /// 排序项：key 与后端约定一致（hot/new/likes）。
  static const List<(String, String)> _sorts = <(String, String)>[
    ('hot', '最热'),
    ('new', '最新'),
    ('likes', '最多赞'),
  ];

  String _sort = 'hot';
  String _gender = '';
  String? _tag;

  /// 元数据（性别列表 + 热门标签）；加载失败时为空，不阻塞列表。
  ExploreMeta _meta = (genders: const [], tags: const []);

  List<Map<String, dynamic>> _cards = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 1;
  String? _error;

  ExploreCardsLoader get _cardsLoader =>
      widget.cardsLoader ?? ApiClient.instance.getExploreCards;

  ExploreMetaLoader get _metaLoader =>
      widget.metaLoader ?? ApiClient.instance.getExploreMeta;

  @override
  void initState() {
    super.initState();
    _loadMeta();
    _reload();
  }

  /// 拉取探索元数据（性别 + 热门标签）；失败静默（列表仍可用）。
  Future<void> _loadMeta() async {
    try {
      final meta = await _metaLoader();
      if (!mounted) return;
      setState(() => _meta = meta);
    } catch (_) {
      // 元数据缺失时仅不展示筛选栏，不影响卡片列表。
    }
  }

  /// 拉取第一页（筛选变化后调用）：清空旧数据并重置分页状态。
  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _noMore = false;
    });
    try {
      final result = await _cardsLoader(
        page: 1,
        sort: _sort,
        gender: _gender,
        tag: _tag,
      );
      if (!mounted) return;
      setState(() {
        _cards = result.items;
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

  /// 追加下一页（滚动接近底部时调用）。
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _noMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _cardsLoader(
        page: _page + 1,
        sort: _sort,
        gender: _gender,
        tag: _tag,
      );
      if (!mounted) return;
      setState(() {
        _cards = <Map<String, dynamic>>[..._cards, ...result.items];
        _page += 1;
        _loadingMore = false;
        if (!result.hasNext) _noMore = true;
      });
    } catch (_) {
      // 加载更多失败：静默，允许下次滚动再试。
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// 更新筛选条件并重新加载第一页。
  void _setFilter({String? sort, String? gender, String? tag}) {
    final nextSort = sort ?? _sort;
    final nextGender = gender ?? _gender;
    final nextTag = tag ?? _tag;
    if (nextSort == _sort && nextGender == _gender && nextTag == _tag) return;
    setState(() {
      _sort = nextSort;
      _gender = nextGender;
      _tag = nextTag;
    });
    _reload();
  }

  void _clearFilter() => _setFilter(gender: '', tag: null);

  void _openCard(String id) {
    final cb = widget.onOpenCard;
    if (cb != null) {
      cb(id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardDetailPage(cardId: id),
      ),
    );
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppRefreshIndicator(
      onRefresh: _reload,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _onScrollNotification(notification);
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: _buildSlivers(context),
        ),
      ),
    );
  }

  List<Widget> _buildSlivers(BuildContext context) {
    final List<Widget> slivers = <Widget>[
      // 性别 + 排序筛选行。
      SliverToBoxAdapter(
        child: _FilterBar(
          sorts: _sorts,
          sort: _sort,
          onSort: (s) => _setFilter(sort: s),
          genders: _meta.genders,
          gender: _gender,
          onGender: (g) => _setFilter(gender: g),
          hasFilter: _gender.isNotEmpty || (_tag?.isNotEmpty ?? false),
          onClear: _clearFilter,
        ),
      ),
      // 热门标签行。
      if (_meta.tags.isNotEmpty)
        SliverToBoxAdapter(
          child: _TagBar(
            tags: _meta.tags,
            selected: _tag,
            onSelect: (t) => _setFilter(tag: t),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ];

    if (_loading) {
      slivers.add(_skeletonSliver(context));
    } else if (_error != null) {
      slivers.add(SliverToBoxAdapter(
        child: ErrorState(onRetry: _reload),
      ));
    } else if (_cards.isEmpty) {
      slivers.add(const SliverToBoxAdapter(
        child: EmptyState(
          icon: Icons.search_off,
          title: '没有符合条件的角色卡，换个筛选试试～',
        ),
      ));
    } else {
      slivers.add(SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: ResponsiveCardGrid(
          cards: _cards,
          onCardTap: _openCard,
        ),
      ));
      if (_loadingMore) {
        slivers.add(const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ));
      }
      if (_noMore && _cards.length > 24) {
        slivers.add(const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text('到底啦',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ),
        ));
      }
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return slivers;
  }

  /// 加载中的骨架屏网格：与真实卡片同列宽、同间隙。
  Widget _skeletonSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = (width ~/ 200).clamp(2, 6);
            const spacing = 12.0;
            final itemWidth = (width - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List<Widget>.generate(
                columns * 3,
                (_) => SizedBox(
                  width: itemWidth,
                  child: const _SkeletonCard(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 骨架卡片：3:4 封面块 + 两行文字条，用于加载中的占位。
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final block = Theme.of(context).colorScheme.surfaceContainerHighest;
    final radius = BorderRadius.circular(12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            decoration: BoxDecoration(color: block, borderRadius: radius),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 96,
          height: 14,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: 12,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ],
    );
  }
}

/// 第 1 行筛选栏：性别 + 排序 单行横划胶囊栏，右侧提供「清除筛选」。
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.sorts,
    required this.sort,
    required this.onSort,
    required this.genders,
    required this.gender,
    required this.onGender,
    required this.hasFilter,
    required this.onClear,
  });

  final List<(String, String)> sorts;
  final String sort;
  final ValueChanged<String> onSort;
  final List<String> genders;
  final String gender;
  final ValueChanged<String> onGender;
  final bool hasFilter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: _HSliceScroll(
        child: Row(
          children: <Widget>[
            if (hasFilter)
              _FilterPill(
                label: '清除筛选',
                icon: Icons.close,
                selected: false,
                onTap: onClear,
              )
            else
              const Text('筛选',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 4),
            // 性别：全部 + 各性别。
            _FilterPill(
              label: '全部',
              selected: gender.isEmpty,
              onTap: () => onGender(''),
            ),
            const SizedBox(width: 4),
            for (final g in genders) ...[
              _FilterPill(
                label: g,
                selected: gender == g,
                onTap: () => onGender(gender == g ? '' : g),
              ),
              const SizedBox(width: 4),
            ],
            const SizedBox(width: 12),
            // 排序：最热 / 最新 / 最多赞。
            for (final (key, label) in sorts) ...[
              _FilterPill(
                label: label,
                selected: sort == key,
                onTap: () => onSort(key),
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }
}

/// 第 2 行标签栏：热门标签横划胶囊栏（#标签 + 计数）。
class _TagBar extends StatelessWidget {
  const _TagBar({
    required this.tags,
    required this.selected,
    required this.onSelect,
  });

  final List<ExploreTag> tags;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: _HSliceScroll(
        child: Row(
          children: <Widget>[
            _FilterPill(
              label: '#全部',
              selected: selected == null,
              onTap: () => onSelect(null),
            ),
            const SizedBox(width: 4),
            for (final t in tags) ...[
              _FilterPill(
                label: '#${t.tag} ${t.count}',
                selected: selected == t.tag,
                onTap: () => onSelect(selected == t.tag ? null : t.tag),
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }
}

/// 横向可滚动容器：底部滚动条（桌面/Web 可见可拖动）+ 鼠标滚轮横向滚动。
///
/// 原生 `SingleChildScrollView` 横向列表不响应鼠标滚轮（滚轮只产生纵向
/// delta），桌面/Web 上只能拖拽，用户会觉得「无法左右滑动」。这里把滚轮
/// 纵向位移转成横向滚动，并挂上滚动条让可滑动范围一目了然。
class _HSliceScroll extends StatefulWidget {
  const _HSliceScroll({required this.child});

  final Widget child;

  @override
  State<_HSliceScroll> createState() => _HSliceScrollState();
}

class _HSliceScrollState extends State<_HSliceScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _controller.hasClients) {
      final delta = event.scrollDelta.dy;
      if (delta == 0) return;
      final target = (_controller.offset + delta)
          .clamp(0.0, _controller.position.maxScrollExtent);
      if (target != _controller.offset) {
        _controller.jumpTo(target);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: Scrollbar(
        controller: _controller,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 单个筛选胶囊：选中态用主色容器，未选中用描边。
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...[
              Icon(icon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
