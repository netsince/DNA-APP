import 'package:material_ui/material_ui.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/widgets/load_more_list.dart';
import 'package:dna/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/responsive_card_grid.dart';
import 'package:dna/island_app/widgets/shimmer.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/island_app/widgets/world_card_tile.dart';
import 'package:dna/island_app/world_detail_page.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/paged_controller.dart';

/// 世界卡列表的筛选条件：排序 / 标签。
///
/// **没有搜索词** —— 找世界书走全站搜索（搜索页的「世界」tab），栏目里再放一个
/// 搜索框，等于同一个动作有两个入口，两边还会各自演化。
class WorldsQuery {
  const WorldsQuery({this.sort = 'new', this.tag = ''});

  final String sort;
  final String tag;

  WorldsQuery copyWith({String? sort, String? tag}) =>
      WorldsQuery(sort: sort ?? this.sort, tag: tag ?? this.tag);

  bool get hasFilter => tag.trim().isNotEmpty;
}

/// 世界卡列表加载器（测试可注入）。返回分页对象（items / has_next）。
typedef WorldsLoader =
    Future<Map<String, dynamic>> Function(int page, WorldsQuery query);

/// 社区「世界」栏目：探索页形态 —— 排序 / 标签筛选 + 卡片网格 + 无限分页。
///
/// 与角色卡探索页同一套交互（横划胶囊筛选条 + 自适应列数网格 + 滚到底加载），
/// 差别只在卡片：世界卡没有封面，用「简介 + 词条名 + 数据」立形态。
///
/// 列表项只有元信息，**不含正文** —— 正文在详情页点「导入」时才单独取。
class WorldsBody extends StatefulWidget {
  const WorldsBody({
    super.key,
    this.importSink,
    this.loader,
    this.tagsLoader,
    this.onOpenWorld,
  });

  /// 导入落地用的窄接口（见 [WorldImportSink]）。为空时详情页不给导入按钮
  /// —— 岛独立运行时没有主应用可写。
  final WorldImportSink? importSink;

  /// 列表加载器。为空时走 [ApiClient.getWorlds]；测试注入假数据。
  final WorldsLoader? loader;

  /// 标签筛选条的标签来源。为空时走 [ApiClient.getWorldTags]。
  final Future<List<({String tag, int count})>> Function()? tagsLoader;

  /// 打开详情（外壳可注入，保持侧边栏）；为空时 push 详情页。
  final ValueChanged<String>? onOpenWorld;

  @override
  State<WorldsBody> createState() => _WorldsBodyState();
}

class _WorldsBodyState extends State<WorldsBody> {
  /// 排序项：key 与后端约定一致（new | copies）。
  static const List<(String, String)> _sorts = <(String, String)>[
    ('new', '最新'),
    ('copies', '最多复制'),
  ];

  /// 世界卡列表的分页状态（首屏 / 加载更多 / 没有更多 / 错误）统一由
  /// [PagedController] 管，页面只提供「怎么取一页」。
  late final PagedController<WorldCardSummary> _paged =
      PagedController<WorldCardSummary>(
        fetch: (int page) async {
          final Map<String, dynamic> data = await _fetch(page);
          return PagedResult<WorldCardSummary>(
            items: _parse(data),
            hasMore: data['has_next'] == true,
          );
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        firstLoadError: '世界列表加载失败，下拉重试',
      );

  /// 标签筛选条的标签：**一次性全量**拉取，不是分页列表，所以不套
  /// [PagedController]（见 [_loadTags]）。
  List<({String tag, int count})> _tags = const <({String tag, int count})>[];

  WorldsQuery _query = const WorldsQuery();

  @override
  void initState() {
    super.initState();
    _loadTags();
    _paged.refresh();
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final loader = widget.tagsLoader ?? ApiClient.instance.getWorldTags;
      final List<({String tag, int count})> tags = await loader();
      if (!mounted) return;
      setState(() => _tags = tags);
    } catch (_) {
      // 标签条拉不到就不显示 —— 筛选条是锦上添花，不该让整个列表报错。
      if (mounted) setState(() => _tags = const <({String tag, int count})>[]);
    }
  }

  Future<Map<String, dynamic>> _fetch(int page) {
    final WorldsLoader? loader = widget.loader;
    if (loader != null) return loader(page, _query);
    return ApiClient.instance.getWorlds(
      page: page,
      sort: _query.sort,
      tag: _query.tag,
    );
  }

  List<WorldCardSummary> _parse(Map<String, dynamic> data) {
    final Object? raw = data['items'];
    if (raw is! List) return <WorldCardSummary>[];
    return raw
        .whereType<Map>()
        .map((Map e) => WorldCardSummary.fromJson(e.cast<String, dynamic>()))
        .where((WorldCardSummary w) => w.id.isNotEmpty)
        .toList();
  }

  void _setFilter({String? sort, String? tag}) {
    final String nextSort = sort ?? _query.sort;
    final String nextTag = tag ?? _query.tag;
    if (nextSort == _query.sort && nextTag == _query.tag) return;
    setState(() => _query = WorldsQuery(sort: nextSort, tag: nextTag));
    // 换了筛选，旧结果立即作废：控制器「失败不清列表」是给翻页用的，
    // 这里必须清掉，否则新筛选失败会把上一个筛选的卡留在屏幕上。
    _paged.items.clear();
    _paged.refresh();
  }

  void _openDetail(WorldCardSummary item) {
    final ValueChanged<String>? cb = widget.onOpenWorld;
    if (cb != null) {
      cb(item.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorldDetailPage(
          id: item.id,
          fallbackName: item.name,
          importSink: widget.importSink,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppRefreshIndicator(
      onRefresh: () => _paged.refresh(),
      // 触底加载走共享封装（阈值 = 列表页默认的 kLoadMoreThreshold）。
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
      SliverToBoxAdapter(child: _filterBar(context)),
      if (_tags.isNotEmpty) SliverToBoxAdapter(child: _tagBar(context)),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
    ];

    if (_paged.isLoading) {
      slivers.add(SliverToBoxAdapter(child: _skeleton(context)));
    } else if (_paged.error != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: ErrorState(
            message: _paged.error!,
            onRetry: () => _paged.refresh(),
          ),
        ),
      );
    } else if (_paged.items.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: _query.hasFilter
                ? EmptyState(
                    icon: Icons.search_off,
                    title: '这个标签下还没有世界卡',
                    actionLabel: '看全部',
                    onAction: () => _setFilter(tag: ''),
                  )
                : const EmptyState(
                    icon: Icons.public_outlined,
                    title: '还没有人发布世界卡',
                    message: '发布一个世界书，让别人也能用上你的设定',
                  ),
          ),
        ),
      );
    } else {
      slivers.add(_gridSliver(context));
      if (_paged.isLoadingMore) {
        slivers.add(
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        );
      }
      if (!_paged.hasMore && _paged.items.length > 12) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: Text(
                  '到底啦',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    slivers.add(
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
    );
    return slivers;
  }

  /// 第 1 行：排序。互斥 2 项、常显 → SegmentedButton。
  ///
  /// 第 1 行：排序与「清除筛选」在**同一行**（回滚 R6：此前被拆成两行，
  /// 还把「清除筛选」挪到了标签行）。
  ///
  /// 控件换型保留（比较排序用 SegmentedButton，与探索/茶馆/评论/搜索一致），
  /// 命中区也保留 ≥40dp（不套 compact，默认就是 40）。
  Widget _filterBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      child: _HorizontalPills(
        children: <Widget>[
          if (_query.hasFilter)
            // 「清除筛选」是动作不是筛选项：低强调 TextButton（审计 3.5）。
            TextButton.icon(
              onPressed: () => _setFilter(tag: ''),
              icon: const Icon(Icons.close, size: AppSize.iconInline),
              label: const Text('清除筛选'),
            )
          else
            Text(
              '排序',
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          AppSpacing.wXs,
          SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              for (final (String key, String label) in _sorts)
                ButtonSegment<String>(value: key, label: Text(label)),
            ],
            selected: <String>{_query.sort},
            onSelectionChanged: (Set<String> picked) =>
                _setFilter(sort: picked.first),
          ),
        ],
      ),
    );
  }

  /// 第 2 行：热门标签（集合筛选 → FilterChip）。
  Widget _tagBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: _HorizontalPills(
        children: <Widget>[
          // 「清除筛选」回到第 1 行（与排序同行），标签行只放标签 ——
          // 这是回滚 R6 前的原结构。
          FilterChip(
            label: const Text('#全部'),
            selected: _query.tag.isEmpty,
            onSelected: (_) => _setFilter(tag: ''),
          ),
          AppSpacing.wXs,
          for (final ({String tag, int count}) t in _tags) ...<Widget>[
            FilterChip(
              label: Text('#${t.tag} ${t.count}'),
              selected: _query.tag == t.tag,
              onSelected: (_) =>
                  _setFilter(tag: _query.tag == t.tag ? '' : t.tag),
            ),
            AppSpacing.wXs,
          ],
        ],
      ),
    );
  }

  /// 瀑布流（真正的 sliver）：列间错落交给 [SliverMasonryGrid]。
  ///
  /// 以前是「`Row` 里塞 N 个 `Column`，按 `i % columns` 分桶」，整块套在
  /// `SliverToBoxAdapter` 里：
  /// * **没有懒构建** —— 一次性把所有卡片都建出来；
  /// * **读屏顺序错** —— 按列读，用户听到的是「第 1 列全部、再第 2 列全部」；
  /// * 列高靠手工对齐，卡片改版就得跟着改分桶逻辑。
  /// 换成 sliver 后三件事一起解决（审计 3.3）。
  ///
  /// 列数仍走全模块唯一那套算法（[cardGridMetrics]），只是这里卡片高度由
  /// 内容决定，所以只取它的 `columns`。
  Widget _gridSliver(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final int columns = cardGridMetrics(
            constraints.crossAxisExtent,
            minColumnWidth: 220,
            maxColumns: kCardGridMaxColumns,
          ).columns;
          return SliverMasonryGrid.count(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childCount: _paged.items.length,
            itemBuilder: (BuildContext context, int index) {
              final WorldCardSummary w = _paged.items[index];
              return WorldCardTile(world: w, onTap: () => _openDetail(w));
            },
          );
        },
      ),
    );
  }

  /// 加载中的骨架网格：与真实卡片同列宽、同间隙。
  Widget _skeleton(BuildContext context) {
    final Color block = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          // 列数与真实瀑布流共用 cardGridMetrics（同一套算法，不再手写）。
          final int columns = cardGridMetrics(
            width,
            minColumnWidth: 220,
            maxColumns: kCardGridMaxColumns,
          ).columns;
          const double spacing = AppSpacing.md;
          final double itemWidth = (width - spacing * (columns - 1)) / columns;
          return Shimmer(
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List<Widget>.generate(
                columns * 3,
                (_) => SizedBox(
                  width: itemWidth,
                  height: 188,
                  child: Container(
                    decoration: BoxDecoration(
                      color: block,
                      borderRadius: AppRadius.mdAll,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 横向可滚动的胶囊栏（桌面端可拖、可用滚轮）。
class _HorizontalPills extends StatelessWidget {
  const _HorizontalPills({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: children),
    );
  }
}

// 筛选胶囊（_Pill）已删除：排序改用 SegmentedButton、标签筛选用 M3 原生
// FilterChip（与角色卡探索页同一套控件）。
