import 'package:flutter/material.dart';

import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import 'island_api.dart';
import 'island_card.dart';
import 'island_card_page.dart';
import 'island_login_dialog.dart';
import 'island_session.dart';

/// 岛的角色卡信息流：探索（默认）或搜索结果。
///
/// 只读社区内容：拉一页展示一页，滚到底自动加载下一页，下拉刷新。
/// 点卡片进详情页 —— 在那里可以**试聊**或**导入到我家**。
///
/// **本地为主**：没登录也能浏览与导入（卡片详情是公开的）；只有需要账号的
/// 操作才会提示登录。
class IslandFeedBody extends StatefulWidget {
  const IslandFeedBody({
    super.key,
    required this.controller,
    this.api,
    this.query,
    this.completer,
  });

  final AppController controller;

  /// 注入用（测试传 MockClient 包出来的客户端）。
  final IslandApi? api;

  /// 非空 = 搜索模式（走搜索接口）；空 = 探索。
  final String? query;

  /// 透传给卡片页（测试注入模型调用）。
  final Future<String> Function(List<Map<String, String>>)? completer;

  @override
  State<IslandFeedBody> createState() => _IslandFeedBodyState();
}

class _IslandFeedBodyState extends State<IslandFeedBody> {
  final ScrollController _scroll = ScrollController();

  List<IslandCard> _cards = <IslandCard>[];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  late final IslandApi _api = widget.api ?? IslandApi();

  bool get _isSearch =>
      widget.query != null && widget.query!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(IslandFeedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    if (widget.api == null) {
      _api.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || !_hasMore || _loading) {
      return;
    }
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 400) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    } else {
      if (_loadingMore) {
        return;
      }
      setState(() => _loadingMore = true);
    }

    try {
      final int page = reset ? 1 : _page + 1;
      final IslandCardsPage result = _isSearch
          ? await _api.searchCards(widget.query!, page: page)
          : await _api.exploreCards(page: page);
      if (!mounted) {
        return;
      }
      setState(() {
        _cards = reset
            ? <IslandCard>[
                for (final Map<String, dynamic> item in result.items)
                  IslandCard.fromJson(item),
              ]
            : <IslandCard>[
                ..._cards,
                for (final Map<String, dynamic> item in result.items)
                  IslandCard.fromJson(item),
              ];
        _page = page;
        _hasMore = result.hasNext;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = '$e';
      });
    }
  }

  Future<void> _openCard(IslandCard card) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => IslandCardPage(
          controller: widget.controller,
          card: card,
          api: widget.api,
          completer: widget.completer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _cards.isEmpty) {
      return _buildError(context);
    }
    if (_cards.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          children: <Widget>[
            const SizedBox(height: 120),
            Center(
              child: FitText(
                _isSearch ? '没有找到相关角色卡。' : '岛上还没有可浏览的角色卡。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 卡片按 3:4 竖图排；每张至少 ~200 宽，手机 2 列、桌面最多 4 列。
          final int columns = (constraints.maxWidth / 200)
              .floor()
              .clamp(2, 4);
          return CustomScrollView(
            controller: _scroll,
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                sliver: SliverGrid(
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: AppSpacing.lg,
                        crossAxisSpacing: AppSpacing.lg,
                        childAspectRatio: 3 / 4.35,
                      ),
                  delegate: SliverChildBuilderDelegate((
                    BuildContext context,
                    int index,
                  ) {
                    final IslandCard card = _cards[index];
                    return _IslandCardTile(
                      card: card,
                      onTap: () => _openCard(card),
                    );
                  }, childCount: _cards.length),
                ),
              ),
              SliverToBoxAdapter(child: _buildFooter(context)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: <Widget>[
            FitText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => _load(reset: false),
              child: const FitText('重试'),
            ),
          ],
        ),
      );
    }
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: FitText(
            '到底了',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return const SizedBox(height: AppSpacing.xl);
  }

  Widget _buildError(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, size: 48, color: cs.outline),
            const SizedBox(height: AppSpacing.md),
            FitText(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.error),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () => _load(reset: true),
                  child: const FitText('重试'),
                ),
                if (!IslandSession.isLoggedIn) ...<Widget>[
                  const SizedBox(width: AppSpacing.md),
                  FilledButton(
                    onPressed: () async {
                      await showIslandLoginDialog(context, api: widget.api);
                      if (mounted) {
                        await _load(reset: true);
                      }
                    },
                    child: const FitText('登录'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 信息流里的一张卡片：封面（3:4）+ 名字 + 作者。
class _IslandCardTile extends StatelessWidget {
  const _IslandCardTile({required this.card, required this.onTap});

  final IslandCard card;
  final VoidCallback onTap;

  String? _cover() {
    for (final String slot in <String>['portrait', 'square', 'landscape']) {
      final String? raw = card.images[slot];
      if (raw != null && raw.isNotEmpty) {
        return IslandSession.absoluteUrl(raw);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String? cover = _cover();
    final String author = card.authorName.isNotEmpty
        ? card.authorName
        : card.authorUsername;

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: cover == null
                  ? ColoredBox(
                      color: cs.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.person_outline, size: 40),
                      ),
                    )
                  : Image.network(
                      cover,
                      fit: BoxFit.cover,
                      loadingBuilder:
                          (
                            BuildContext context,
                            Widget child,
                            ImageChunkEvent? progress,
                          ) => progress == null
                          ? child
                          : ColoredBox(
                              color: cs.surfaceContainerHighest,
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                      errorBuilder:
                          (
                            BuildContext context,
                            Object error,
                            StackTrace? stack,
                          ) => ColoredBox(
                            color: cs.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText(
                    card.name.trim().isEmpty ? '未命名' : card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (author.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    FitText(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
