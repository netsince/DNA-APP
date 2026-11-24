import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/utils/ui_feedback.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/community_preload.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/theme/app_dimensions.dart';
import 'package:dna/island_app/utils/external_link.dart';
import 'package:dna/island_app/widgets/skeleton_card.dart';
import 'package:dna/island_app/widgets/announcement_sheet.dart';
import 'package:dna/island_app/widgets/responsive_card_grid.dart';
import 'package:dna/widgets/refreshable.dart';
import 'package:dna/island_app/widgets/shimmer.dart';
import 'package:dna/island_app/widgets/state_views.dart';
import 'package:dna/widgets/paged_controller.dart';
import '../theme/tokens.dart';

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

  /// 分页状态（首屏 / 加载更多 / 没有更多 / 错误）统一由 [PagedController] 管，
  /// 页面只提供「怎么取一批卡」。
  ///
  /// 推荐接口是**随机**的、没有真正的页码：翻页靠 `exclude` 已经展示过的 id
  /// 往前推，所以这里用 `page` 区分首屏（1 = 不带 exclude）与翻页。
  late final PagedController<Map<String, dynamic>> _paged =
      PagedController<Map<String, dynamic>>(
        fetch: (int page) async {
          try {
            if (page <= 1) {
              // 启动时预取的那批只消费一次（之后含下拉刷新都走网络）。
              final List<Map<String, dynamic>>? seed = _pendingSeed;
              if (seed != null) {
                _pendingSeed = null;
                return PagedResult<Map<String, dynamic>>(
                  items: seed,
                  hasMore: seed.isNotEmpty,
                );
              }
            }
            final List<Map<String, dynamic>> cards = await ApiClient.instance
                .getFeaturedCards(
                  excludeIds: page <= 1
                      ? const <String>[]
                      : _paged.items
                            .map(
                              (Map<String, dynamic> c) =>
                                  (c['id'] ?? '').toString(),
                            )
                            .toList(),
                );
            // 内容就绪：整体淡入浮现（骨架屏 → 真实卡片），代替生硬切换。
            if (mounted) _contentIn.forward(from: 0);
            // 随机推荐没有「下一页」：返回空批 = 换不出新卡了。
            return PagedResult<Map<String, dynamic>>(
              items: cards,
              hasMore: cards.isNotEmpty,
            );
          } catch (_) {
            // 首屏/刷新失败：错误态交给控制器，下拉刷新的 snackbar 见 [_refresh]。
            if (page <= 1) _refreshFailed = true;
            rethrow;
          }
        },
        onChanged: () {
          if (mounted) setState(() {});
        },
        firstLoadError: '推荐内容加载失败，请稍后重试',
      );

  /// 启动时预取的那批推荐（见 [CommunityPreload]），被第一页消费后置空。
  List<Map<String, dynamic>>? _pendingSeed;

  /// 上一次首屏/刷新请求是否失败（控制器不区分「刷新失败」，见 [_refresh]）。
  bool _refreshFailed = false;

  /// 内容（网格/占位）淡入动画：加载完成后从透明平滑浮现，代替生硬切换。
  late final AnimationController _contentIn;

  @override
  void initState() {
    super.initState();
    // 必须在 initState 中创建：late 惰性初始化若推迟到 dispose（如加载失败、
    // _contentIn 从未被访问），state 已 deactivated，查找 TickerMode 祖先会崩溃。
    _contentIn = AnimationController(
      vsync: this,
      duration: AppMotion.transform,
      value: 1.0,
    );
    // 站点配置是后台异步加载的，可能在首页挂载后才到位；监听其变化，
    // 待公告配置就绪后补弹，避免因非阻塞启动而漏弹。
    SiteConfig.instance.addListener(_onSiteConfigChanged);
    widget.refreshCounter?.addListener(_onRefreshRequested);
    _maybeShowAnnouncement();
    // 主应用首屏时已经预取过一批推荐（见 CommunityPreload）：命中就直接
    // 铺上，用户点进社区立刻有内容，连骨架屏都不出现。
    _pendingSeed = CommunityPreload.instance.freshFeaturedCards;
    _paged.refresh();
  }

  void _onSiteConfigChanged() => _maybeShowAnnouncement();

  /// 外壳在「推荐」Tab 内再次点击该 Tab 时自增计数，触发重新拉取。
  void _onRefreshRequested() {
    if (!mounted) return;
    _paged.refresh();
  }

  @override
  void dispose() {
    widget.refreshCounter?.removeListener(_onRefreshRequested);
    SiteConfig.instance.removeListener(_onSiteConfigChanged);
    _paged.dispose();
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
        builder: (_) =>
            AnnouncementSheet(
              content: cfg.announcementContent,
              onOpen: _open,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              maxHeightFraction: 0.7,
            ),
      );
    });
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => CardDetailPage(cardId: id)));
  }

  void _onScrollNotification(ScrollNotification notification) {
    // 接近底部时触发追加加载（阈值统一用 [kLoadMoreThreshold]）。
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - kLoadMoreThreshold) {
      _paged.loadMore();
    }
  }

  /// 下拉刷新：静默重新拉取随机推荐（保留现有内容，避免骨架屏闪烁）。
  ///
  /// 刷新失败时控制器**不动**已有列表（也就不会进错误态），所以这里补一条
  /// snackbar —— 下拉刷新的失败必须让用户看见。
  Future<void> _refresh() async {
    _refreshFailed = false;
    await _paged.refresh();
    if (!mounted || !_refreshFailed) return;
    showSnack(context, '刷新失败，请稍后再试');
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
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
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
            duration: AppMotion.medium,
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

    if (_paged.isLoading) {
      // 加载微动画：闪烁骨架屏，贴合卡片布局，替代生硬转圈。
      slivers.add(titleSliver);
      slivers.add(_skeletonSliver(context));
    } else if (_paged.error != null) {
      slivers.add(titleSliver);
      slivers.add(
        SliverToBoxAdapter(child: ErrorState(onRetry: () => _paged.refresh())),
      );
    } else if (_paged.items.isEmpty) {
      slivers.add(titleSliver);
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('暂无推荐内容')),
          ),
        ),
      );
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
                cards: _paged.items,
                onCardTap: _openCard,
              ),
            ),
          ),
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
        child: Shimmer(
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
                    child: const SkeletonCard(),
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
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: AppLineHeight.body,
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

