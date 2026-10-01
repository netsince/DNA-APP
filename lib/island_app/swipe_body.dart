import 'package:flutter/material.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/widgets/fade_in_image.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 「刷一刷」横向翻页式角色卡浏览。
///
/// - 全屏左右滑动（PageView 横向），每页一张卡；
/// - 背景用卡片**对应比例**的封面（portrait=9:16 / landscape=16:9 / square=1:1，
///   按此比例用 `BoxFit.cover` 铺满并裁剪），不拉伸变形；
/// - 底部黑色→透明渐变内展示名称/性别/作者/简介/观看·复制数；
/// - 点按整页经 [onOpenCard] 打开详情页；
/// - 只展示**有封面**的卡；滑到底自动用 `excludeIds` 拉下一批，去重追加。
class SwipeBody extends StatefulWidget {
  const SwipeBody({super.key, this.onOpenCard, this.cardsLoader});

  /// 打开角色卡详情：优先交给外壳（保留侧边栏）；未提供时回退为 push 内置详情页。
  final ValueChanged<String>? onOpenCard;

  /// 拉取「刷一刷」卡的分页加载器；默认走 [ApiClient.getSwipeCards]。可注入以便测试。
  final Future<List<Map<String, dynamic>>> Function({List<String> excludeIds})?
  cardsLoader;

  @override
  State<SwipeBody> createState() => _SwipeBodyState();
}

class _SwipeBodyState extends State<SwipeBody> {
  final PageController _pageController = PageController();

  List<Map<String, dynamic>> _cards = <Map<String, dynamic>>[];
  final Set<String> _seenIds = <String>{};
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 分页加载器：优先注入的 loader，否则回退到 [ApiClient.getSwipeCards]（专用「刷一刷」接口）。
  Future<List<Map<String, dynamic>>> _loader({
    List<String> excludeIds = const [],
  }) {
    final custom = widget.cardsLoader;
    if (custom != null) return custom(excludeIds: excludeIds);
    return ApiClient.instance.getSwipeCards(excludeIds: excludeIds);
  }

  /// 拉取首批推荐卡并过滤出有封面的。
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _noMore = false;
    });
    try {
      final cards = await _loader();
      final withCover = cards.where(_hasCover).toList();
      if (!mounted) return;
      setState(() {
        _cards = withCover;
        _loading = false;
        _seenIds
          ..clear()
          ..addAll(withCover.map((c) => (c['id'] ?? '').toString()));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 换一批：重新拉取（保留已见去重，仍可补到新卡）。
  Future<void> _refresh() async {
    try {
      final cards = await _loader();
      final withCover = cards.where(_hasCover).toList();
      if (!mounted) return;
      setState(() {
        _cards = withCover;
        _error = null;
        _loading = false;
        _noMore = false;
        _seenIds
          ..clear()
          ..addAll(withCover.map((c) => (c['id'] ?? '').toString()));
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('刷新失败，请稍后再试')));
    }
  }

  /// 滑到接近末尾时追加下一批（排除已展示的卡，仍只留有封面的）。
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _noMore) return;
    setState(() => _loadingMore = true);
    try {
      final cards = await _loader(excludeIds: _seenIds.toList());
      if (!mounted) return;
      final withCover = cards.where(_hasCover).toList();
      setState(() {
        _cards = <Map<String, dynamic>>[..._cards, ...withCover];
        for (final c in withCover) {
          _seenIds.add((c['id'] ?? '').toString());
        }
        _loadingMore = false;
        if (cards.isEmpty) _noMore = true;
      });
    } catch (_) {
      // 加载更多失败：静默，允许下次滚动再试。
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// 是否带封面（有任意槽位封面才算「有图片」，符合「只匹配有图的卡」）。
  bool _hasCover(Map<String, dynamic> card) {
    final covers = card['covers'];
    if (covers is! Map || covers.isEmpty) return false;
    return covers.values.any((v) => v is String && v.isNotEmpty);
  }

  /// 取对应比例的封面 URL：优先 portrait(9:16)，其次 landscape(16:9)，再 square(1:1)。
  String? _coverUrl(Map<String, dynamic> card) {
    final covers = card['covers'];
    if (covers is! Map) return null;
    for (final slot in <String>['portrait', 'landscape', 'square']) {
      final v = covers[slot];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  void _onPageChanged(int index) {
    // 滑到接近末尾（距末尾 2 页）时预加载下一批。
    if (index >= _cards.length - 2) _loadMore();
  }

  void _openCard(Map<String, dynamic> card) {
    final id = (card['id'] ?? '').toString();
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
    if (_loading) {
      return const LoadingState();
    }
    if (_error != null && _cards.isEmpty) {
      return ErrorState(onRetry: _load);
    }
    if (_cards.isEmpty) {
      return EmptyState(
        icon: Icons.image_not_supported_outlined,
        title: '暂无有封面的推荐卡',
        actionLabel: '换一批',
        onAction: _refresh,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        AppRefreshIndicator(
          onRefresh: _refresh,
          child: PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.horizontal,
            itemCount: _cards.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) => _SwipeCard(
              card: _cards[index],
              coverUrl: _coverUrl(_cards[index]),
              onTap: () => _openCard(_cards[index]),
            ),
          ),
        ),
        // 顶部小标题浮层。
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '刷一刷',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        // 换一批按钮（右上角）。
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: IconButton.filled(
            tooltip: '换一批',
            onPressed: _refresh,
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.35),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh),
          ),
        ),
      ],
    );
  }
}

/// 单张刷一刷卡片：全屏封面 + 底部渐变信息层。
class _SwipeCard extends StatelessWidget {
  const _SwipeCard({
    required this.card,
    required this.coverUrl,
    required this.onTap,
  });

  final Map<String, dynamic> card;
  final String? coverUrl;
  final VoidCallback onTap;

  String _str(String key) => (card[key] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final name = _str('name');
    final gender = _str('gender');
    final intro = _str('intro');
    final author = _authorName();
    final cover = coverUrl;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 全屏背景：黑色 + 对应比例封面（BoxFit.cover 保持比例并裁剪铺满）。
          ColoredBox(color: Colors.black),
          if (cover != null)
            FadeInNetworkImage(
              url: ServerConfig.resolveUrl(cover),
              fit: BoxFit.cover,
              cacheWidth: 720,
              placeholder: const ColoredBox(color: Colors.black),
            ),
          // 底部黑色→透明渐变遮罩，内写信息。
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.5, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                        if (gender.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              gender,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '@$author',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                    if (intro.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        intro,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.visibility_outlined,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _fmtCount(card['view_count']),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.content_copy,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _fmtCount(card['copy_count']),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.touch_app_outlined,
                          size: 16,
                          color: Colors.white54,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '点按查看详情',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _authorName() {
    final author = card['author'];
    if (author is Map) {
      final nickname = (author['nickname'] ?? '').toString();
      final username = (author['username'] ?? '').toString();
      return nickname.isNotEmpty ? nickname : username;
    }
    return '';
  }

  String _fmtCount(dynamic v) {
    final n = v is num ? v.toDouble() : 0;
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toStringAsFixed(0);
  }
}
