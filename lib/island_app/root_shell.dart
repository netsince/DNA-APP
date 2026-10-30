import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:dna/island_app/app_drawer.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/articles_page.dart';
import 'package:dna/island_app/card_detail_page.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/card_publish_source.dart';
import 'package:dna/island_app/ta_import_sink.dart';
import 'package:dna/island_app/card_publish_start_page.dart';
import 'package:dna/island_app/explore_body.dart';
import 'package:dna/island_app/home_body.dart';
import 'package:dna/island_app/image_gen_body.dart';
import 'package:dna/island_app/swipe_body.dart';
import 'package:dna/island_app/me_page.dart';
import 'package:dna/island_app/my_cards_page.dart';
import 'package:dna/island_app/my_collections_page.dart';
import 'package:dna/island_app/notifications_page.dart';
import 'package:dna/island_app/proxy_config_page.dart';
import 'package:dna/island_app/recommend_page.dart';
import 'package:dna/island_app/search_page.dart';
import 'package:dna/island_app/site_config.dart';
import 'package:dna/island_app/sponsor_body.dart';
import 'package:dna/island_app/teahouse_body.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/island_app/world_publish_page.dart';
import 'package:dna/island_app/worlds_body.dart';
import 'package:dna/island_app/widgets/plus_hub.dart';
import 'package:dna/island_app/widgets/drag_scroll_behavior.dart';
import '../theme/tokens.dart';

/// 顶部内容 tab：推荐 / 刷一刷 / 探索。
enum _TopTab { recommend, swipe, explore }

/// 底栏的 Key。
///
/// 侧边栏（抽屉）与底栏会出现同名图标，测试要单独点底栏时得能区分开。
const Key kCommunityBottomBarKey = Key('communityBottomBar');

/// 应用外壳：顶栏 + 常驻侧边栏/底栏。
///
/// 导航目标（推荐/茶馆/上传/生图/我/设置）通过侧边栏与底栏切换；
/// 「推荐」页内顶栏提供 推荐/刷一刷/探索 三个内容子页。
class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    this.onExitToMainApp,
    this.worldImportSink,
    this.worldPublishSource,
    this.cardPublishSource,
    this.taImportSink,
  });

  /// 「返回主应用」回调。
  ///
  /// 岛被嵌进主项目的「社区」栏目时由外层传入：顶栏抽屉与底栏都会出现
  /// 返回入口。岛单独运行（原来的 main.dart）时不传，两个入口都不出现，
  /// 行为与合并前完全一致。
  final VoidCallback? onExitToMainApp;

  /// 导入落地用的窄接口（见 [WorldImportSink]）。
  ///
  /// 社区对主应用是零状态依赖，所以这里不传 AppController，只注入这一个方法。
  /// 为空时世界卡详情页不给「导入」按钮（岛独立运行时没有可写入的本地世界）。
  final WorldImportSink? worldImportSink;

  /// 取本地世界列表的窄接口（发布世界卡用）。为空时发布页只给提示。
  final WorldPublishSource? worldPublishSource;

  /// 取本地角色卡（发布角色卡用）。为空时发布页只给「新建 / 导入」两条路。
  final CardPublishSource? cardPublishSource;

  /// 「导入社区角色卡到本地」的落地。为空时详情页不显示导入入口。
  final TaImportSink? taImportSink;

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

  /// 「＋」枢纽是否开着（开着时图标转成 ×）。
  bool _plusOpen = false;

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
          cardImporter: widget.taImportSink?.importTa,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无公告')));
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ArticlesPage()));
  }

  /// 打开站长推荐。
  void _openRecommend() {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RecommendPage()));
  }

  /// 打开代理中转（BYOK 代理配置）。
  void _openProxy() {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ProxyConfigPage()));
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
      _plusOpen = false;
    });
    if (reRefresh) _recommendRefresh.value++;
  }

  /// 打开通知页（侧栏「我的」组，带未读角标）。
  void _openNotifications() {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => NotificationsPage()));
  }

  /// 打开「我的发布」。
  void _openMyCards() {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MyCardsPage()));
  }

  /// 打开「我的收藏」。
  void _openMyFavorites() {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyCollectionsPage(
          title: '我的收藏',
          loader: ApiClient.instance.getMyFavorites,
        ),
      ),
    );
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
      // 底栏是从 ＋ 浮层「挖空」的那块里露出来的（见 PlusHubOverlay），
      // 点它不经过蒙层、不会触发 onClose，所以必须在这里顺手收掉 ——
      // 否则会切到茶馆、浮层却还盖在上面。
      _plusOpen = false;
    });
    // 首次切到「生图」：触发生图工作台加载（登录态已就绪，避免 401）。
    if (target == AppNavTarget.imagegen && firstShow) {
      _imageGenActivate.value++;
    }
  }

  /// 主体内容层（始终保持 IndexedStack 不销毁）。
  ///
  /// 外面套一层 [DragScrollBehavior]：电脑版上「刷一刷」、横向筛选条这类
  /// **靠拖**的界面才能用鼠标拖动（Flutter 桌面默认把鼠标排除在 dragDevices
  /// 之外，按住鼠标拖毫无反应 —— 用户反馈"电脑版刷一刷坏了"）。
  /// 只作用于社区内部，不动主项目全局的滚动行为。
  Widget _body() {
    return ScrollConfiguration(
      behavior: const DragScrollBehavior(),
      child: _buildContentStack(),
    );
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
        WorldsBody(importSink: widget.worldImportSink),
        const TeahouseBody(),
        CardPublishStartBody(source: widget.cardPublishSource),
        ImageGenBody(
          onRequireLogin: () => _onSelectNav(AppNavTarget.me),
          loadSignal: _imageGenActivate,
        ),
        MePage(importSink: widget.worldImportSink),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final drawerContent = AppDrawerContent(
      selected: _page,
      onSelect: _onSelectNav,
      // 侧栏「发布」与底栏「＋」同源：都打开三选一枢纽。
      // 注意：抽屉不是路由，收它必须走 closeDrawer；在这里 pop 会把整个社区弹回去。
      onPlusHubTap: _togglePlusHub,
      onShowAnnouncement: _showAnnouncement,
      onOpenArticles: _openArticles,
      onOpenRecommend: _openRecommend,
      onOpenProxy: _openProxy,
      onOpenSponsor: _openSponsor,
      onOpenNotifications: _openNotifications,
      onOpenMyCards: _openMyCards,
      onOpenMyFavorites: _openMyFavorites,
      // 未登录时侧栏那行「登录」必须接上回调：不传的话 ListTile.onTap 是
      // null，那一行**看起来正常但完全点不动**（岛独立运行时就一直是这样）。
      // 「登录表单」在「我」页里，所以这里直接切过去。
      onLogin: () => _onSelectNav(AppNavTarget.me),
      // 嵌进主项目时才有:抽屉末尾的「返回主应用」。
      onExitToMainApp: widget.onExitToMainApp,
    );

    final bool isAtRootPage =
        _page == AppNavTarget.recommend && _tab == _TopTab.recommend;

    return PopScope(
      // 社区自己接管返回，顺序是：浮层 → 子页 → 顶栏 tab → 交回主应用。
      //
      // 嵌进主应用时 canPop 必须**恒为 false**：社区是主应用里的一个「栏目」而不是
      // 一条路由，canPop=true 会把整个应用 pop 掉 —— Android 上就是按一下返回直接
      // 退出应用，而用户只是想退一层。独立运行（onExitToMainApp 为空）时才交给系统。
      canPop: widget.onExitToMainApp == null && isAtRootPage && !_plusOpen,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_plusOpen) {
          _closePlusHub();
          return;
        }
        if (_page != AppNavTarget.recommend) {
          setState(() => _page = AppNavTarget.recommend);
          return;
        }
        if (_tab != _TopTab.recommend) {
          setState(() => _tab = _TopTab.recommend);
          return;
        }
        // 社区内部已经退无可退 → 交回主应用。
        widget.onExitToMainApp?.call();
      },
      child: OrientationBuilder(
        builder: (context, orientation) {
          final landscape = orientation == Orientation.landscape;
          final Widget? bottomBar = landscape ? null : _bottomBar();
          final PreferredSizeWidget topBar = _topBar(landscape);

          final Widget content = landscape
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
              : _body();

          // ＋ 枢纽浮在**整个 Scaffold 之上**，连底栏一起糊；底部原来 ＋ 的位置
          // 换成一个关闭按钮。
          //
          // 不用 push 路由：路由的 ModalBarrier 会吸收整屏点击，浮层里的按钮
          // 也跟着点不动。
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Scaffold(
                key: _scaffoldKey,
                appBar: landscape ? null : topBar,
                drawer: landscape ? null : Drawer(child: drawerContent),
                bottomNavigationBar: bottomBar,
                body: content,
              ),
              PlusHubOverlay(
                open: _plusOpen,
                bottomBarHeight: _kBottomBarHeight,
                onClose: _closePlusHub,
                onSelect: _onPlusChoice,
              ),
            ],
          );
        },
      ),
    );
  }

  /// 构建顶栏（汉堡 + 标题/tab + 搜索 + 返回主应用）。
  /// 顶栏布局：**左边是「退」**（侧边栏、返回主应用），**右边是「找」**（通知、搜索）。
  ///
  /// 两个动作簇分开：左半区管「往回走」，右半区管「往外看」，比混在一排好扫。
  AppBar _topBar(bool landscape) {
    final bool canExit = widget.onExitToMainApp != null;
    return AppBar(
      // 两个图标占两格，默认 56 宽放不下。
      leadingWidth: landscape ? null : (canExit ? 96 : null),
      leading: landscape
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _hamburger(),
                if (canExit)
                  IconButton(
                    tooltip: '返回主应用',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _exitToMainApp,
                  ),
              ],
            ),
      title: _title(),
      actions: <Widget>[_notificationButton(), _searchButton()],
    );
  }

  Widget _title() {
    if (_page == AppNavTarget.recommend) return _topTabs();
    return Text(_pageTitle(_page));
  }

  String _pageTitle(AppNavTarget p) => switch (p) {
    AppNavTarget.recommend => '推荐',
    AppNavTarget.worlds => '世界',
    AppNavTarget.teahouse => '茶馆',
    AppNavTarget.upload => '发布',
    AppNavTarget.imagegen => '生图',
    AppNavTarget.me => '我',
    AppNavTarget.settings => '设置',
  };

  /// 底栏内容高度（不含系统底部安全区）。
  ///
  /// ＋ 浮层要按这个高度从底部挖空，所以两边必须共用同一个常量。
  static const double _kBottomBarHeight = 56;

  /// 常驻底栏：推荐 / 茶馆 / ＋ / 我（嵌入主项目时末尾再加「返回主应用」）。
  ///
  /// 未激活只显示图标；激活项同时显示小字号文字（MDUI 简洁风格）。
  ///
  /// 中间那格是 **＋ 动作枢纽**而不是栏目（对齐网页版的移动底栏）：点开是
  /// 「发布角色卡」与「AI生图」。这样发布与生图不占底栏格子 —— 之前它俩各占
  /// 一格，加上「返回主应用」一共 6 格，很挤；腾出来的位置留给真正的栏目。
  ///
  /// ＋ 放在第三格：嵌入主项目时底栏是 5 格（推荐/茶馆/＋/我/返回），
  /// ＋ 正好落在正中，与网页版一致。
  Widget _bottomBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: kCommunityBottomBarKey,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _kBottomBarHeight,
          child: Row(
            children: <Widget>[
              // 顺序：推荐 / 茶馆 / ＋ / 世界 / 我
              _bottomNavItem(AppNavTarget.recommend),
              _bottomNavItem(AppNavTarget.teahouse),
              _plusItem(),
              _bottomNavItem(AppNavTarget.worlds),
              _bottomNavItem(AppNavTarget.me),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomNavItem(AppNavTarget target) {
    final bool selected = _page == target;
    return Expanded(
      child: InkWell(
        onTap: () => _onSelectNav(target),
        child: _bottomItem(target, selected),
      ),
    );
  }

  /// 底栏中间的 ＋：动作枢纽。
  ///
  /// 高亮跟「发布」「生图」两页联动 —— 停在那两页时 ＋ 亮起，否则底栏会出现
  /// 「一格都没选中」的空档（网页版也是这么做的：publish.* 时 ＋ 激活）。
  ///
  /// **刻意不显示文字标签**：别的格子是栏目、标签常驻；＋ 是动作，标签只在枢纽
  /// 展开时出现。那一出现/一消失会把图标在 56px 的格子里顶上顶下 8px 多，而且是
  /// 瞬时的 —— 看着像按钮在打嗝。转成 × 的图标已经足够说明状态。
  Widget _plusItem() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool active =
        _plusOpen ||
        _page == AppNavTarget.upload ||
        _page == AppNavTarget.imagegen;
    final Color color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: _togglePlusHub,
        child: Center(
          child: AnimatedRotation(
            // 45° 就够把 ＋ 转成 × —— 用最短的必要位移，别让它多绕一圈。
            turns: _plusOpen ? 0.125 : 0,
            // 与浮层同一组 MD3 令牌，图标和面板同步动，不会一个先到、一个后到。
            duration: Durations.medium1,
            curve: Easing.emphasizedDecelerate,
            child: Icon(Icons.add, size: 22, color: color),
          ),
        ),
      ),
    );
  }

  /// 点 ＋：展开 / 收起枢纽。
  ///
  /// 做成开关而不是「只能开」—— 浮层不盖底栏（见 PlusHubOverlay 的注释），
  /// 所以 ＋ 一直在，再点一次就收起来（图标同时从 ＋ 转成 ×）。
  void _togglePlusHub() {
    _scaffoldKey.currentState?.closeDrawer();
    setState(() => _plusOpen = !_plusOpen);
  }

  void _closePlusHub() {
    if (!_plusOpen) return;
    setState(() => _plusOpen = false);
  }

  /// 「返回主应用」：先收掉 ＋ 浮层。
  ///
  /// 社区这一栏是 IndexedStack 常驻的，不收的话下次从主应用回到社区，
  /// 浮层还盖在那儿。
  void _exitToMainApp() {
    _closePlusHub();
    widget.onExitToMainApp?.call();
  }

  void _onPlusChoice(PlusHubChoice choice) {
    _closePlusHub();
    switch (choice) {
      case PlusHubChoice.publishCard:
        _onSelectNav(AppNavTarget.upload);
      case PlusHubChoice.publishWorld:
        _openWorldPublish();
      case PlusHubChoice.imageGen:
        _onSelectNav(AppNavTarget.imagegen);
    }
  }

  /// 发布世界卡：从本地世界里挑一个发到社区。
  void _openWorldPublish() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorldPublishPage(source: widget.worldPublishSource),
      ),
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
      duration: AppMotion.fast,
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
                fontSize: AppFontSize.tiny,
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
    AppNavTarget.worlds => (Icons.public_outlined, '世界'),
    AppNavTarget.teahouse => (Icons.local_cafe_outlined, '茶馆'),
    AppNavTarget.upload => (Icons.upload_outlined, '上传'),
    AppNavTarget.imagegen => (Icons.auto_awesome_outlined, '生图'),
    AppNavTarget.me => (Icons.person_outline, '我'),
    AppNavTarget.settings => (Icons.settings_outlined, '设置'),
  };

  Widget _hamburger() => Builder(
    builder: (context) => IconButton(
      icon: const Icon(Icons.menu),
      onPressed: () => Scaffold.of(context).openDrawer(),
    ),
  );

  /// 居中顶栏 tab：推荐 / 刷一刷 / 探索。
  ///
  /// 外面套 FittedBox：顶栏右侧有三个动作（搜索 / 通知 / 返回）时，窄屏上
  /// 中间的可用宽度只剩 168px，而三个 tab 要 171px —— 差一点点就溢出。
  /// 这里让它按需整体缩小（最多缩几个百分点，肉眼无感），而不是硬溢出。
  Widget _topTabs() {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
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
      ),
    );
  }

  Widget _topTabButton(String label, _TopTab t) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _tab == t;
    return InkWell(
      onTap: () => _selectTab(t),
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              height: 2,
              width: 20,
              decoration: BoxDecoration(
                color: selected ? scheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.xs),
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
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SearchPage()));
    },
  );

  /// 右侧通知入口：带未读数角标。未登录时不显示。
  Widget _notificationButton() {
    if (!AuthSession.instance.isLoggedIn) {
      return const SizedBox.shrink();
    }
    return const _NotificationButton();
  }
}

/// 顶栏右侧的通知入口：带未读数角标。
///
/// **未读数只在 initState 拉一次，绝不能写在 build 里。**
///
/// 这里原先是个 FutureBuilder，future 直接写成
/// getUnreadNotificationCount() —— 而 _topBar() 是在 build() 里调的，于是
/// RootShell 每 rebuild 一次就发一次请求。配合「每次尝试 15 秒超时」和
/// maxConnectionsPerHost = 4，几次交互就能把连接池占满，之后所有请求排队等死
/// —— 表现就是「疯狂地无法连接」。而且它只在登录后渲染，未登录时完全看不出来。
class _NotificationButton extends StatefulWidget {
  const _NotificationButton();

  @override
  State<_NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<_NotificationButton> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final int unread = await ApiClient.instance.getUnreadNotificationCount();
      if (mounted) setState(() => _unread = unread);
    } catch (_) {
      // 一个角标不该在顶栏里报错；失败就当 0。
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '消息通知',
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text('$_unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () async {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => NotificationsPage()));
        // 从通知页回来，未读数可能已经清掉，刷新一次。
        if (mounted) _load();
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
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
