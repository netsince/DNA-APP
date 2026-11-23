import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/widgets/load_more_list.dart';
import 'package:dna/island_app/widgets/responsive_card_grid.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/widgets/paged_controller.dart';
import '../theme/tokens.dart';

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
  const ExploreBody({
    super.key,
    this.onOpenCard,
    this.cardsLoader,
    this.metaLoader,
  });

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

  /// 角色卡网格的分页状态（首屏 / 加载更多 / 没有更多 / 错误）统一由
  /// [PagedController] 管，页面只提供「怎么取一页」。
  late final PagedController<Map<String, dynamic>> _paged =
      PagedController<Map<String, dynamic>>(
        fetch: (int page) async {
          // 接口返回记录类型（items / hasNext），交给类型推断，不自造类型名。
          final result = await _cardsLoader(
            page: page,
            sort: _sort,
            gender: _gender,
            tag: _tag,
          );
          return PagedResult<Map<String, dynamic>>(
            items: result.items,
            hasMore: result.hasNext,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        firstLoadError: '角色卡列表加载失败，请稍后重试',
      );

  ExploreCardsLoader get _cardsLoader =>
      widget.cardsLoader ?? ApiClient.instance.getExploreCards;

  ExploreMetaLoader get _metaLoader =>
      widget.metaLoader ?? ApiClient.instance.getExploreMeta;

  @override
  void initState() {
    super.initState();
    _loadMeta();
    _paged.refresh();
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
    // 换了筛选，旧结果立即作废：控制器「失败不清列表」是给翻页用的，
    // 这里必须清掉，否则新筛选失败会把上一个筛选的卡留在屏幕上。
    _paged.items.clear();
    _paged.refresh();
  }

  void _clearFilter() => _setFilter(gender: '', tag: null);

  void _openCard(String id) {
    final cb = widget.onOpenCard;
    if (cb != null) {
      cb(id);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => CardDetailPage(cardId: id)));
  }

  @override
  Widget build(BuildContext context) {
    return AppRefreshIndicator(
      onRefresh: () => _paged.refresh(),
      // 触底加载走共享封装（阈值用列表页默认的 kLoadMoreThreshold=400）。
      child: loadMoreListener(
        onReachEnd: () => _paged.loadMore(),
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

    if (_paged.isLoading) {
      slivers.add(_skeletonSliver(context));
    } else if (_paged.error != null) {
      slivers.add(
        SliverToBoxAdapter(child: ErrorState(onRetry: () => _paged.refresh())),
      );
    } else if (_paged.items.isEmpty) {
      slivers.add(
        const SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.search_off,
            title: '没有符合条件的角色卡，换个筛选试试～',
          ),
        ),
      );
    } else {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: ResponsiveCardGrid(cards: _paged.items, onCardTap: _openCard),
        ),
      );
      if (_paged.isLoadingMore) {
        slivers.add(
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        );
      }
      if (!_paged.hasMore && _paged.items.length > 24) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: Text(
                  '到底啦',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    // 语义色而不是裸 Colors.grey（审计 4.4）。
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return slivers;
  }

  /// 加载中的骨架屏：列数/格子尺寸都取自 [cardGridMetrics]，
  /// 与真实网格**同构** —— 否则内容一到位卡片会重排、页面跳一下（审计 3.3）。
  Widget _skeletonSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final CardGridMetrics m = cardGridMetrics(constraints.maxWidth);
            return Wrap(
              spacing: kCardGridSpacing,
              runSpacing: kCardGridSpacing,
              children: List<Widget>.generate(
                m.columns * 3,
                (_) => SizedBox(
                  width: m.cellWidth,
                  height: m.cellHeight,
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
    final radius = BorderRadius.circular(AppRadius.sm);
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
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: 12,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(AppRadius.xs),
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
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      // 排序与筛选**同一行**（回滚 R6：此前被拆成两行，把一个本来就紧凑的
      // 筛选条撑成了两条）。控件换型保留：排序用 SegmentedButton、集合筛选用
      // FilterChip，语义比原来的自绘胶囊清楚；命中区也保留 ≥40dp
      // （原胶囊只有 30dp）。
      child: _HSliceScroll(
        child: Row(
          children: <Widget>[
            if (hasFilter)
              // 「清除筛选」是**动作**，不是又一个筛选项：低强调 TextButton，
              // 不与 FilterChip 同权重（审计 3.5）。
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.close, size: AppSize.iconInline),
                label: const Text('清除筛选'),
              )
            else
              Text(
                '筛选',
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: cs.onSurfaceVariant,
                ),
              ),
            AppSpacing.wXs,
            // 排序：不套 visualDensity.compact —— compact 会把高度压到 36，
            // 低于回滚要求的 40dp 命中区（默认 40）。
            SegmentedButton<String>(
              segments: <ButtonSegment<String>>[
                for (final (String key, String label) in sorts)
                  ButtonSegment<String>(value: key, label: Text(label)),
              ],
              selected: <String>{sort},
              onSelectionChanged: (Set<String> picked) => onSort(picked.first),
            ),
            AppSpacing.wSm,
            // 性别：集合筛选 → FilterChip（自带 48dp 命中盒）。
            FilterChip(
              label: const Text('全部'),
              selected: gender.isEmpty,
              onSelected: (_) => onGender(''),
            ),
            AppSpacing.wXs,
            for (final String g in genders) ...<Widget>[
              FilterChip(
                label: Text(g),
                selected: gender == g,
                onSelected: (_) => onGender(gender == g ? '' : g),
              ),
              AppSpacing.wXs,
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: _HSliceScroll(
        child: Row(
          children: <Widget>[
            // 标签是**集合筛选** → FilterChip（保留勾选标记，不再手搓胶囊）。
            FilterChip(
              label: const Text('#全部'),
              selected: selected == null,
              onSelected: (_) => onSelect(null),
            ),
            AppSpacing.wXs,
            for (final ExploreTag t in tags) ...<Widget>[
              FilterChip(
                label: Text('#${t.tag} ${t.count}'),
                selected: selected == t.tag,
                onSelected: (_) => onSelect(selected == t.tag ? null : t.tag),
              ),
              AppSpacing.wXs,
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
      final target = (_controller.offset + delta).clamp(
        0.0,
        _controller.position.maxScrollExtent,
      );
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

// 筛选胶囊（_FilterPill）已删除：排序改用 SegmentedButton、集合筛选用 M3 原生
// FilterChip，全模块不再有自绘胶囊（审计 5 节「排序控件 5 种」的收口点）。
