import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:dna/island_app/app_drawer.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/articles_page.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/card_publish_start_page.dart';
import 'package:dna/island_app/explore_body.dart';
import 'package:dna/island_app/home_body.dart';
import 'package:dna/island_app/image_gen_body.dart';
import 'package:dna/island_app/swipe_body.dart';
import 'package:dna/island_app/me_page.dart';
import 'package:dna/island_app/notifications_page.dart';
import 'package:dna/island_app/proxy_config_page.dart';
import 'package:dna/island_app/recommend_page.dart';
import 'package:dna/island_app/search_page.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/island_app/sponsor_body.dart';
import 'package:dna/island_app/teahouse_body.dart';

/// 顶部内容 tab：推荐 / 刷一刷 / 探索。
enum _TopTab { recommend, swipe, explore }

/// 应用外壳：顶栏 + 常驻侧边栏/底栏。
///
/// 导航目标（推荐/茶馆/上传/生图/我/设置）通过侧边栏与底栏切换；
/// 「推荐」页内顶栏提供 推荐/刷一刷/探索 三个内容子页。
class RootShell extends StatefulWidget {
  const RootShell({super.key, this.onExitToMainApp});

  /// 「返回主应用」回调。
  ///
  /// 岛被嵌进主项目的「社区」栏目时由外层传入：顶栏抽屉与底栏都会出现
  /// 返回入口。岛单独运行（原来的 main.dart）时不传，两个入口都不出现，
  /// 行为与合并前完全一致。
  final VoidCallback? onExitToMainApp;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  _TopTab _tab = _TopTab.recommend;
  AppNavTarget _page = AppNavTarget.recommend;

  /// 「推荐」Tab 刷新信号：在「推荐」内再次点击该 Tab 时自增，首页监听到后重拉。
  final ValueNotifier<int> _recommendRefresh = ValueNotifier<int>(0);

  /// 「生图」激活信号：切到「生图」tab 时自增，触发生图工作台加载。
  /// 生图页常驻 IndexedStack，应用启动即构建，故需等真正切到该页才请求，
  /// 避免登录态未就绪时 401。
  final ValueNotifier<int> _imageGenActivate = ValueNotifier<int>(0);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // 监听「去登录」请求：切换到「我」页登录表单。
    AuthSession.instance.loginRequest.addListener(_onLoginRequest);
  }

  void _onLoginRequest() {
    _onSelectNav(AppNavTarget.me);
  }

  @override
  void dispose() {
    AuthSession.instance.loginRequest.removeListener(_onLoginRequest);
    _recommendRefresh.dispose();
    _imageGenActivate.dispose();
    super.dispose();
  }

  /// 打开角色卡内置详情页（原生路由 push）。
  void _openCardDetail(String id) {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardDetailPage(
          cardId: id,
          cardExporter: ApiClient.instance.exportCard,
          cardHider: ApiClient.instance.toggleCardHidden,
        ),
      ),
    );
  }

  /// 再次查看站点公告：底部弹层展示公告内容（与首页首启公告同款）。
  void _showAnnouncement() {
    _scaffoldKey.currentState?.closeDrawer();
    final cfg = SiteConfig.instance;
    if (!cfg.announcementEnabled || cfg.announcementContent.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无公告')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AnnouncementSheet(content: cfg.announcementContent),
    );
  }

  /// 打开官方文章（文章列表）。
  void _openArticles() {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ArticlesPage()),
    );
  }

  /// 打开站长推荐。
  void _openRecommend() {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RecommendPage()),
    );
  }

  /// 打开代理中转（BYOK 代理配置）。
  void _openProxy() {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProxyConfigPage()),
    );
  }

  /// 选中顶栏 tab：回到「推荐」页。
  ///
  /// 已在「推荐」Tab 时再次点击该 Tab，触发一次刷新。
  void _selectTab(_TopTab t) {
    _scaffoldKey.currentState?.closeDrawer();
    final reRefresh = _tab == t && t == _TopTab.recommend;
    setState(() {
      _tab = t;
      _page = AppNavTarget.recommend;
    });
    if (reRefresh) _recommendRefresh.value++;
  }

  /// 打开赞助页（原生路由 push；岛设置并入主项目设置后，赞助从抽屉直达）。
  void _openSponsor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('赞助')),
          body: const SponsorBody(),
        ),
      ),
    );
  }

  /// 通过侧边栏/底栏选中导航目标。
  void _onSelectNav(AppNavTarget target) {
    _scaffoldKey.currentState?.closeDrawer();
    final firstShow = _page != target;
    setState(() {
      _page = target;
    });
    // 首次切到「生图」：触发生图工作台加载（登录态已就绪，避免 401）。
    if (target == AppNavTarget.imagegen && firstShow) {
      _imageGenActivate.value++;
    }
  }

  /// 主体内容层（始终保持 IndexedStack 不销毁）。
  Widget _body() {
    return _buildContentStack();
  }

  /// 主页面常驻栈：索引 = 导航目标；推荐页内部按顶栏 tab 切换。
  Widget _buildContentStack() {
    return IndexedStack(
      index: _page == AppNavTarget.recommend ? 0 : _page.index,
      children: <Widget>[
        // 推荐页：内部用 IndexedStack 保活 推荐/刷一刷/探索 三个子页。
        IndexedStack(
          index: _tab.index,
          children: <Widget>[
            HomeBody(
              onOpenCard: _openCardDetail,
              refreshCounter: _recommendRefresh,
            ),
            SwipeBody(onOpenCard: _openCardDetail),
            ExploreBody(
              onOpenCard: _openCardDetail,
              cardsLoader: ApiClient.instance.getExploreCards,
              metaLoader: ApiClient.instance.getExploreMeta,
            ),
          ],
        ),
        const TeahouseBody(),
        const CardPublishStartBody(),
        ImageGenBody(
          onRequireLogin: () => _onSelectNav(AppNavTarget.me),
          loadSignal: _imageGenActivate,
        ),
        const MePage(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final drawerContent = AppDrawerContent(
      selected: _page,
      onSelect: _onSelectNav,
      onShowAnnouncement: _showAnnouncement,
      onOpenArticles: _openArticles,
      onOpenRecommend: _openRecommend,
      onOpenProxy: _openProxy,
      onOpenSponsor: _openSponsor,
      // 嵌进主项目时才有:抽屉末尾的「返回主应用」。
      onExitToMainApp: widget.onExitToMainApp,
    );

    final bool isAtRootPage =
        _page == AppNavTarget.recommend && _tab == _TopTab.recommend;

    return PopScope(
      canPop: isAtRootPage,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_page != AppNavTarget.recommend) {
          setState(() => _page = AppNavTarget.recommend);
        } else if (_tab != _TopTab.recommend) {
          setState(() => _tab = _TopTab.recommend);
        }
      },
      child: OrientationBuilder(
        builder: (context, orientation) {
          final landscape = orientation == Orientation.landscape;
          final Widget? bottomBar = landscape ? null : _bottomBar();
          final PreferredSizeWidget topBar = _topBar(landscape);

          return Scaffold(
            key: _scaffoldKey,
            appBar: landscape ? null : topBar,
            drawer: landscape ? null : Drawer(child: drawerContent),
            bottomNavigationBar: bottomBar,
            body: landscape
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: 260,
                        child: SafeArea(bottom: false, child: drawerContent),
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            topBar,
                            Expanded(child: _body()),
                          ],
                        ),
                      ),
                    ],
                  )
                : _body(),
          );
        },
      ),
    );
  }

  /// 构建顶栏（汉堡 + 标题/tab + 搜索）。
  AppBar _topBar(bool landscape) {
    return AppBar(
      leading: landscape ? null : _hamburger(),
      title: _title(),
      centerTitle: true,
      actions: [_notificationButton(), _searchButton()],
    );
  }

  Widget _title() {
    if (_page == AppNavTarget.recommend) return _topTabs();
    return Text(_pageTitle(_page));
  }

  String _pageTitle(AppNavTarget p) => switch (p) {
        AppNavTarget.recommend => '推荐',
        AppNavTarget.teahouse => '茶馆',
        AppNavTarget.upload => '上传',
        AppNavTarget.imagegen => '生图',
        AppNavTarget.me => '我',
        AppNavTarget.settings => '设置',
      };

  /// 常驻底栏：推荐/茶馆/上传/生图/我。
  ///
  /// 未激活只显示图标；激活项同时显示小字号文字（MDUI 简洁风格）。
  Widget _bottomBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              ..._bottomTargets.map((target) {
                final selected = _page == target;
                return Expanded(
                  child: InkWell(
                    onTap: () => _onSelectNav(target),
                    child: _bottomItem(target, selected),
                  ),
                );
              }),
              // 「我」右边的「返回主应用」：仅在嵌入主项目时出现。
              if (widget.onExitToMainApp != null)
                Expanded(
                  child: InkWell(
                    onTap: widget.onExitToMainApp,
                    child: _bottomExitItem(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底栏末尾的「返回主应用」项：**只显示图标**（与底栏未激活项一致），
  /// 图标用「出门」的隐喻（箭头出门）。
  Widget _bottomExitItem() {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Icon(Icons.logout, size: 22, color: scheme.onSurfaceVariant),
    );
  }

  /// 单个底栏项：激活显示图标 + 文字，未激活仅图标。
  ///
  /// 「我」特殊：登录时图标位置换成**当前用户头像**（圆形裁剪），
  /// 文字规则不变。
  Widget _bottomItem(AppNavTarget target, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) = _navMeta(target);
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final bool meWithAvatar =
        target == AppNavTarget.me && AuthSession.instance.isLoggedIn;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (meWithAvatar)
            Avatar(avatar: AuthSession.instance.avatar, radius: 11)
          else
            Icon(icon, size: 22, color: color),
          if (selected) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  (IconData, String) _navMeta(AppNavTarget t) => switch (t) {
        AppNavTarget.recommend => (Icons.home_outlined, '推荐'),
        AppNavTarget.teahouse => (Icons.local_cafe_outlined, '茶馆'),
        AppNavTarget.upload => (Icons.upload_outlined, '上传'),
        AppNavTarget.imagegen => (Icons.auto_awesome_outlined, '生图'),
        AppNavTarget.me => (Icons.person_outline, '我'),
        AppNavTarget.settings => (Icons.settings_outlined, '设置'),
      };

  static const List<AppNavTarget> _bottomTargets = <AppNavTarget>[
    AppNavTarget.recommend,
    AppNavTarget.teahouse,
    AppNavTarget.upload,
    AppNavTarget.imagegen,
    AppNavTarget.me,
  ];

  Widget _hamburger() => Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      );

  /// 居中顶栏 tab：推荐 / 刷一刷 / 探索。
  Widget _topTabs() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _TopTab.values.map((t) {
          final label = switch (t) {
            _TopTab.recommend => '推荐',
            _TopTab.swipe => '刷一刷',
            _TopTab.explore => '探索',
          };
          return _topTabButton(label, t);
        }).toList(),
      ),
    );
  }

  Widget _topTabButton(String label, _TopTab t) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _tab == t;
    return InkWell(
      onTap: () => _selectTab(t),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
            ),
            const SizedBox(height: 3),
            Container(
              height: 2,
              width: 20,
              decoration: BoxDecoration(
                color: selected ? scheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右侧搜索入口：打开全站搜索页。
  Widget _searchButton() => IconButton(
        icon: const Icon(Icons.search),
        tooltip: '搜索',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SearchPage()),
          );
        },
      );

  /// 右侧通知入口：带未读数角标。未登录时不显示。
  ///
  /// 未读数在构建顶栏时拉一次(登录才有意义),失败按 0 处理 ——
  /// 一个角标不该在顶栏里报错。
  Widget _notificationButton() {
    if (!AuthSession.instance.isLoggedIn) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<int>(
      future: ApiClient.instance.getUnreadNotificationCount(),
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        final int unread = snapshot.data ?? 0;
        return IconButton(
          tooltip: '消息通知',
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications_outlined),
          ),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => NotificationsPage()),
            );
          },
        );
      },
    );
  }
}

/// 站点公告弹层（可复用）：侧边栏「公告」与首页首启公告共用。
class AnnouncementSheet extends StatelessWidget {
  const AnnouncementSheet({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.campaign_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '站点公告',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Html(
                  data: content,
                  extensions: <HtmlExtension>[TableHtmlExtension()],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
  }
}
