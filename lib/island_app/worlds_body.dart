import 'package:flutter/material.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/shimmer.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/island_app/widgets/world_card_tile.dart';
import 'package:dna/island_app/world_detail_page.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/theme/tokens.dart';

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
typedef WorldsLoader = Future<Map<String, dynamic>> Function(
  int page,
  WorldsQuery query,
);

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

  final List<WorldCardSummary> _items = <WorldCardSummary>[];
  List<({String tag, int count})> _tags = const <({String tag, int count})>[];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = false;
  int _page = 1;
  String? _error;

  WorldsQuery _query = const WorldsQuery();

  @override
  void initState() {
    super.initState();
    _loadTags();
    _reload();
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

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _hasNext = false;
    });
    try {
      final Map<String, dynamic> data = await _fetch(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(_parse(data));
        _page = 1;
        _hasNext = data['has_next'] == true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '世界列表加载失败，下拉重试';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasNext) return;
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic> data = await _fetch(_page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(_parse(data));
        _page += 1;
        _hasNext = data['has_next'] == true;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _setFilter({String? sort, String? tag}) {
    final String nextSort = sort ?? _query.sort;
    final String nextTag = tag ?? _query.tag;
    if (nextSort == _query.sort && nextTag == _query.tag) return;
    setState(() => _query = WorldsQuery(sort: nextSort, tag: nextTag));
    _reload();
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
      onRefresh: _reload,
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
            _loadMore();
          }
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
      SliverToBoxAdapter(child: _filterBar(context)),
      if (_tags.isNotEmpty) SliverToBoxAdapter(child: _tagBar(context)),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
    ];

    if (_loading) {
      slivers.add(SliverToBoxAdapter(child: _skeleton(context)));
    } else if (_error != null) {
      slivers.add(
        SliverToBoxAdapter(child: ErrorState(message: _error!, onRetry: _reload)),
      );
    } else if (_items.isEmpty) {
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
      slivers.add(SliverToBoxAdapter(child: _grid(context)));
      if (_loadingMore) {
        slivers.add(
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        );
      }
      if (!_hasNext && _items.length > 12) {
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

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)));
    return slivers;
  }

  /// 第 1 行：排序（与角色卡探索页同一套胶囊样式）。
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
            _Pill(
              label: '清除筛选',
              icon: Icons.close,
              selected: false,
              onTap: () => _setFilter(tag: ''),
            )
          else
            Text(
              '排序',
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: AppSpacing.xs),
          for (final (String key, String label) in _sorts) ...<Widget>[
            _Pill(
              label: label,
              selected: _query.sort == key,
              onTap: () => _setFilter(sort: key),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }

  /// 第 2 行：热门标签。
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
          _Pill(
            label: '#全部',
            selected: _query.tag.isEmpty,
            onTap: () => _setFilter(tag: ''),
          ),
          const SizedBox(width: AppSpacing.xs),
          for (final ({String tag, int count}) t in _tags) ...<Widget>[
            _Pill(
              label: '#${t.tag} ${t.count}',
              selected: _query.tag == t.tag,
              onTap: () => _setFilter(tag: _query.tag == t.tag ? '' : t.tag),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }

  /// 瀑布流：按列轮流投放，每列高度自然参差。
  ///
  /// 不用 GridView / Wrap：前者每行等高（长简介被裁），后者按行对齐（留白很丑）。
  /// 这里让卡片按内容自己长，列与列之间错落。
  Widget _grid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          final int columns = (width ~/ 220).clamp(2, 6);
          const double spacing = AppSpacing.md;
          final double itemWidth =
              (width - spacing * (columns - 1)) / columns;

          final List<List<Widget>> buckets = List<List<Widget>>.generate(
            columns,
            (_) => <Widget>[],
          );
          for (int i = 0; i < _items.length; i++) {
            final WorldCardSummary w = _items[i];
            buckets[i % columns].add(
              Padding(
                padding: const EdgeInsets.only(bottom: spacing),
                child: WorldCardTile(
                  world: w,
                  onTap: () => _openDetail(w),
                ),
              ),
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int c = 0; c < columns; c++) ...<Widget>[
                if (c > 0) const SizedBox(width: spacing),
                SizedBox(
                  width: itemWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: buckets[c],
                  ),
                ),
              ],
            ],
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
          final int columns = (width ~/ 220).clamp(2, 6);
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

/// 单个筛选胶囊。
class _Pill extends StatelessWidget {
  const _Pill({
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
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
            if (icon != null) ...<Widget>[
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
