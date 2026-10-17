import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/models/world_card.dart';
import 'package:dna/island_app/utils/time_format.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/shimmer.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/island_app/world_detail_page.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/theme/tokens.dart';

/// 世界卡列表的筛选条件：搜索词 / 标签 / 排序。
///
/// 收成一个值对象而不是三个独立参数：加载器要一次拿到全部条件，测试也好
/// 断言「切标签后到底传了什么」。
class WorldsQuery {
  const WorldsQuery({this.sort = 'new', this.keyword = '', this.tag = ''});

  final String sort;
  final String keyword;
  final String tag;

  WorldsQuery copyWith({String? sort, String? keyword, String? tag}) =>
      WorldsQuery(
        sort: sort ?? this.sort,
        keyword: keyword ?? this.keyword,
        tag: tag ?? this.tag,
      );

  bool get hasFilter => keyword.trim().isNotEmpty || tag.trim().isNotEmpty;
}

/// 世界卡列表加载器（测试可注入）。返回分页对象（items / has_next）。
typedef WorldsLoader = Future<Map<String, dynamic>> Function(
  int page,
  WorldsQuery query,
);

/// 社区「世界」栏目：世界卡列表。
///
/// 列表项只有元信息（名称/简介/词条数/体积/复制量/标签），**不含正文** ——
/// 正文在详情页点「导入」时才单独取（见 [WorldDetailPage]）。
///
/// 世界书动辄几百 KB，列表接口要是带上正文，翻一页就是几十 MB。
///
/// 与角色卡/茶馆对齐的部分：搜索框、标签筛选、骨架屏。这三样之前都没有，
/// 于是「找一本世界书」只能靠翻页 —— 后端其实一直支持 q/tag 参数，只是
/// 客户端从来没传过。
class WorldsBody extends StatefulWidget {
  const WorldsBody({super.key, this.importSink, this.loader, this.tagsLoader});

  /// 导入落地用的窄接口（见 [WorldImportSink]）。为空时详情页不给导入按钮
  /// —— 岛独立运行时没有主应用可写。
  final WorldImportSink? importSink;

  /// 列表加载器。为空时走 [ApiClient.getWorlds]；测试注入假数据。
  final WorldsLoader? loader;

  /// 标签筛选条的标签来源。为空时走 [ApiClient.getWorldTags]。
  final Future<List<({String tag, int count})>> Function()? tagsLoader;

  @override
  State<WorldsBody> createState() => _WorldsBodyState();
}

class _WorldsBodyState extends State<WorldsBody> {
  final List<WorldCardSummary> _items = <WorldCardSummary>[];
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<({String tag, int count})> _tags = const <({String tag, int count})>[];

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  bool _hasNext = false;

  WorldsQuery _query = const WorldsQuery();

  @override
  void initState() {
    super.initState();
    _load();
    _loadTags();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
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
      query: _query.keyword,
      tag: _query.tag,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> data = await _fetch(1);
      final List<WorldCardSummary> items = _parse(data);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _page = 1;
        _hasNext = data['has_next'] == true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '世界列表加载失败，下拉重试';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext) return;
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

  List<WorldCardSummary> _parse(Map<String, dynamic> data) {
    final Object? raw = data['items'];
    if (raw is! List) return <WorldCardSummary>[];
    return raw
        .whereType<Map>()
        .map((Map e) => WorldCardSummary.fromJson(e.cast<String, dynamic>()))
        .where((WorldCardSummary w) => w.id.isNotEmpty)
        .toList();
  }

  void _openDetail(WorldCardSummary item) {
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

  /// 输入停顿 350ms 再查：每敲一个字都打一次接口，服务端会被搜索框打爆。
  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final String keyword = text.trim();
      if (keyword == _query.keyword) return;
      setState(() => _query = _query.copyWith(keyword: keyword));
      _load();
    });
  }

  void _selectTag(String tag) {
    if (_query.tag == tag) return;
    setState(() => _query = _query.copyWith(tag: tag));
    _load();
  }

  void _selectSort(String sort) {
    if (_query.sort == sort) return;
    setState(() => _query = _query.copyWith(sort: sort));
    _load();
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _query = const WorldsQuery());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(child: _header(context)),
          ..._content(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '世界卡',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: AppWeight.medium,
                  ),
                ),
              ),
              // 排序：最新 / 最多复制。
              //
              // 复制量是这个栏目最有价值的信号 —— 一个人愿意把世界导入自己的
              // 应用，说明它真的有用，比点赞可信。
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'new', label: Text('最新')),
                  ButtonSegment<String>(value: 'copies', label: Text('最多复制')),
                ],
                selected: <String>{_query.sort},
                showSelectedIcon: false,
                onSelectionChanged: (Set<String> next) =>
                    _selectSort(next.first),
              ),
            ],
          ),
          AppSpacing.hSm,
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (String value) {
              _searchDebounce?.cancel();
              setState(
                () => _query = _query.copyWith(keyword: value.trim()),
              );
              _load();
            },
            decoration: InputDecoration(
              hintText: '搜索世界名称 / 简介',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.hasFilter
                  ? IconButton(
                      tooltip: '清除筛选',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _clearFilters,
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: AppRadius.smAll),
            ),
          ),
          if (_tags.isNotEmpty) ...<Widget>[
            AppSpacing.hSm,
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  _tagChip(context, '', '全部'),
                  for (final ({String tag, int count}) t in _tags)
                    _tagChip(context, t.tag, t.tag),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tagChip(BuildContext context, String tag, String label) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool selected = _query.tag == tag;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        visualDensity: VisualDensity.compact,
        labelStyle: TextStyle(
          fontSize: AppFontSize.caption,
          color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
        ),
        onSelected: (_) => _selectTag(tag),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return <Widget>[SliverToBoxAdapter(child: _skeleton(context))];
    }
    if (_items.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: _query.hasFilter
              ? EmptyState(
                  icon: Icons.search_off,
                  title: '没有匹配的世界卡',
                  message: '换个词，或者清除筛选看看全部',
                  actionLabel: '清除筛选',
                  onAction: _clearFilters,
                )
              : EmptyState(
                  icon: Icons.public_outlined,
                  title: _error ?? '还没有人发布世界卡',
                  message: _error == null ? '发布一个世界书，让别人也能用上你的设定' : null,
                  actionLabel: _error == null ? null : '重试',
                  onAction: _error == null ? null : _load,
                ),
        ),
      ];
    }
    return <Widget>[
      SliverList.separated(
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) => _tile(
          context,
          _items[index],
        ),
      ),
      SliverToBoxAdapter(child: _footer()),
    ];
  }

  /// 首屏骨架：和真实行同构（标题 / 两行简介 / 元信息），比转圈更能预告布局。
  Widget _skeleton(BuildContext context) {
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: AppRadius.xsAll,
            ),
          ),
        );
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          children: <Widget>[
            for (int i = 0; i < 6; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    bar(0.45, 14),
                    AppSpacing.hXs,
                    bar(0.9, 10),
                    AppSpacing.hXxs,
                    bar(0.6, 10),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!_hasNext) return AppSpacing.hXl;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: TextButton(onPressed: _loadMore, child: const Text('加载更多')),
      ),
    );
  }

  Widget _tile(BuildContext context, WorldCardSummary item) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<String> meta = <String>[
      if (item.entryCount > 0) '${item.entryCount} 词条',
      if (item.sizeLabel.isNotEmpty) item.sizeLabel,
      if (item.copyCount > 0) '复制 ${item.copyCount}',
    ];
    final DateTime? when = item.updatedAt ?? item.createdAt;
    final String whenLabel =
        when == null ? '' : formatRelativeTime(when.toIso8601String());
    return InkWell(
      onTap: () => _openDetail(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: AppWeight.medium,
              ),
            ),
            if (item.summary.isNotEmpty) ...<Widget>[
              AppSpacing.hXxs,
              Text(
                item.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            if (meta.isNotEmpty) ...<Widget>[
              AppSpacing.hXs,
              Text(
                meta.join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            if (item.tags.isNotEmpty) ...<Widget>[
              AppSpacing.hXs,
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  for (final String tag in item.tags.take(4)) _chip(context, tag),
                ],
              ),
            ],
            if (item.authorName.isNotEmpty) ...<Widget>[
              AppSpacing.hXs,
              Row(
                children: <Widget>[
                  Avatar(avatar: item.authorAvatar, radius: 9),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      item.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (whenLabel.isNotEmpty) ...<Widget>[
                    Text(
                      ' · $whenLabel',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String tag) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppRadius.xsAll,
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: AppFontSize.caption,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
