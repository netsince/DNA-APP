import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/community_preload.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/island_app/utils/external_link.dart';
import 'package:dna/island_app/widgets/responsive_card_grid.dart';
import 'package:dna/island_app/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/shimmer.dart';
import 'package:dna/island_app/widgets/state_views.dart';

/// 首页内容（Hero + 随机推荐角色卡）。不含脚手架/侧边栏，由 [RootShell] 承载。
///
/// 采用懒加载的 CustomScrollView：卡片网格按需构建、只保留可视区域附近的
/// 元素，避免滚动加载大量卡片时一次性构建全部 widget 导致卡顿/内存增长。
class HomeBody extends StatefulWidget {
  const HomeBody({super.key, this.onOpenCard, this.refreshCounter});

  /// 打开角色卡详情：优先交给外壳（保留侧边栏）；未提供时回退为 push 内置详情页。
  final ValueChanged<String>? onOpenCard;

  /// 刷新信号：外壳在「推荐」Tab 内再次点击该 Tab 时自增，本页监听到后重新拉取。
  /// 为 null 时（独立使用）不监听外部刷新。
  final ValueListenable<int>? refreshCounter;

  @override
  State<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<HomeBody>
    with SingleTickerProviderStateMixin {
  // 进程内只在启动时强制弹一次公告。
  static bool _announcementShown = false;

  List<Map<String, dynamic>> _cards = const [];
  final Set<String> _seenIds = <String>{};
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  String? _error;

  /// 内容（网格/占位）淡入动画：加载完成后从透明平滑浮现，代替生硬切换。
  late final AnimationController _contentIn;

  @override
  void initState() {
    super.initState();
    // 必须在 initState 中创建：late 惰性初始化若推迟到 dispose（如加载失败、
    // _contentIn 从未被访问），state 已 deactivated，查找 TickerMode 祖先会崩溃。
    _contentIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      value: 1.0,
    );
    // 站点配置是后台异步加载的，可能在首页挂载后才到位；监听其变化，
    // 待公告配置就绪后补弹，避免因非阻塞启动而漏弹。
    SiteConfig.instance.addListener(_onSiteConfigChanged);
    widget.refreshCounter?.addListener(_onRefreshRequested);
    _maybeShowAnnouncement();
    // 主应用首屏时已经预取过一批推荐（见 CommunityPreload）：命中就直接
    // 铺上，用户点进社区立刻有内容，连骨架屏都不出现。
    final List<Map<String, dynamic>>? prefetched =
        CommunityPreload.instance.freshFeaturedCards;
    if (prefetched != null) {
      _cards = prefetched;
      _loading = false;
      _seenIds.addAll(
        prefetched.map((Map<String, dynamic> c) => (c['id'] ?? '').toString()),
      );
    } else {
      _loadFeatured();
    }
  }

  void _onSiteConfigChanged() => _maybeShowAnnouncement();

  /// 外壳在「推荐」Tab 内再次点击该 Tab 时自增计数，触发重新拉取。
  void _onRefreshRequested() {
    if (!mounted) return;
    _loadFeatured();
  }

  @override
  void dispose() {
    widget.refreshCounter?.removeListener(_onRefreshRequested);
    SiteConfig.instance.removeListener(_onSiteConfigChanged);
    _contentIn.dispose();
    super.dispose();
  }

  /// 启动时强制弹公告：用模态底部弹层（非小弹窗、非横幅），适合长内容。
  void _maybeShowAnnouncement() {
    if (_announcementShown) return;
    final cfg = SiteConfig.instance;
    if (!cfg.announcementEnabled || cfg.announcementContent.isEmpty) return;
    _announcementShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _AnnouncementSheet(
          content: cfg.announcementContent,
          onOpen: _open,
        ),
      );
    });
  }

  /// 拉取首页随机推荐角色卡（首批）。
  Future<void> _loadFeatured() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cards = await ApiClient.instance.getFeaturedCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
        _seenIds
          ..clear()
          ..addAll(cards.map((c) => (c['id'] ?? '').toString()));
      });
      // 内容就绪，淡入浮现（骨架屏/占位平滑过渡到真实内容）。
      _contentIn.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 无限滚动：滚动接近底部时追加一批新随机卡（排除已展示的）。
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _noMore) return;
    setState(() => _loadingMore = true);
    try {
      final cards = await ApiClient.instance
          .getFeaturedCards(excludeIds: _seenIds.toList());
      if (!mounted) return;
      setState(() {
        _cards = <Map<String, dynamic>>[..._cards, ...cards];
        for (final c in cards) {
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

  Future<void> _open(String url) async {
    await confirmOpenBrowser(context, url);
  }

  /// 点击角色卡：打开内置详情页（而非外部网页）。
  void _openCard(String id) {
    final cb = widget.onOpenCard;
    if (cb != null) {
      cb(id); // 交由外壳承载，横屏保留常驻侧边栏。
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardDetailPage(cardId: id),
      ),
    );
  }

  void _onScrollNotification(ScrollNotification notification) {
    // 接近底部时触发追加加载。
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  /// 下拉刷新：静默重新拉取随机推荐（保留现有内容，避免骨架屏闪烁）。
  Future<void> _refresh() async {
    try {
      final cards = await ApiClient.instance.getFeaturedCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _error = null;
        _loading = false;
        _noMore = false;
        _seenIds
          ..clear()
          ..addAll(cards.map((c) => (c['id'] ?? '').toString()));
      });
      _contentIn.forward(from: 0);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('刷新失败，请稍后再试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = SiteConfig.instance;
    return AppRefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _onScrollNotification(notification);
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: _buildSlivers(context, cfg),
        ),
      ),
    );
  }

  /// 按当前状态构建首页 sliver 列表：Hero + 标题 + 网格（或加载/错误/空占位）。
  List<Widget> _buildSlivers(BuildContext context, SiteConfig cfg) {
    final Widget titleSliver = SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      sliver: SliverToBoxAdapter(
        child: Text(
          '为你推荐',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
    );

    final List<Widget> slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        sliver: SliverToBoxAdapter(
          // Hero 首次出现时的淡入 + 轻微上浮，柔和衔接。
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - v)),
                child: child,
              ),
            ),
            child: _HeroBanner(
              title: cfg.heroTitle,
              subtitle: cfg.heroSubtitle,
              buttons: cfg.heroButtons,
              onOpen: _open,
            ),
          ),
        ),
      ),
    ];

    if (_loading) {
      // 加载微动画：闪烁骨架屏，贴合卡片布局，替代生硬转圈。
      slivers.add(titleSliver);
      slivers.add(_skeletonSliver(context));
    } else if (_error != null) {
      slivers.add(titleSliver);
      slivers.add(SliverToBoxAdapter(
        child: ErrorState(onRetry: _loadFeatured),
      ));
    } else if (_cards.isEmpty) {
      slivers.add(titleSliver);
      slivers.add(const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: Text('暂无推荐内容')),
        ),
      ));
    } else {
      slivers.add(titleSliver);
      // 内容整体淡入（骨架屏 → 真实网格）。
      slivers.add(
        AnimatedBuilder(
          animation: _contentIn,
          builder: (context, _) => SliverOpacity(
            opacity: _contentIn.value,
            sliver: SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: ResponsiveCardGrid(
                cards: _cards,
                onCardTap: _openCard,
              ),
            ),
          ),
        ),
      );
      if (_loadingMore) {
        slivers.add(const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ));
      }
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return slivers;
  }

  /// 加载中的骨架屏网格：与真实卡片同列宽、同间隙，带 shimmer 微光。
  Widget _skeletonSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Shimmer(
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

/// 首页 Hero：简洁的全宽左对齐 banner。无装饰渐变、无边框，内容贴左，
/// 左右拉伸到接近边缘（保留少量 padding）。符合 MD 的横幅/排版规范。
class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.title,
    required this.subtitle,
    required this.buttons,
    required this.onOpen,
  });

  final String title;
  final String subtitle;
  final List<Map<String, String>> buttons;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title.isNotEmpty)
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .displaySmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
        ],
        if (buttons.isNotEmpty) ...[
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: buttons.asMap().entries.map((entry) {
              final i = entry.key;
              final b = entry.value;
              final label = b['label'] ?? '';
              final url = b['url'] ?? '';
              final onPressed = url.isEmpty ? null : () => onOpen(url);
              // 首个用主按钮，其余用描边按钮，对齐 web 版主/次按钮。
              return i == 0
                  ? FilledButton(onPressed: onPressed, child: Text(label))
                  : OutlinedButton(onPressed: onPressed, child: Text(label));
            }).toList(),
          ),
        ],
      ],
    );
  }
}

/// 公告底部弹层：模态底部弹窗，可滚动长内容，底部「知道了」关闭。
class _AnnouncementSheet extends StatelessWidget {
  const _AnnouncementSheet({required this.content, required this.onOpen});

  final String content;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.campaign_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '站点公告',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Html(
                    data: content,
                    onLinkTap: (href, _, _) {
                      if (href != null) onOpen(href);
                    },
                    extensions: <HtmlExtension>[TableHtmlExtension()],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
