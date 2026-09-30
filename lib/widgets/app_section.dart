import 'package:flutter/material.dart';

import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/app_bottom_nav.dart';
import 'package:dna/widgets/app_drawer.dart';
import 'package:dna/widgets/section_assembly.dart';

/// 主导航的栏目:抽屉与底部导航栏共用这一份定义。
///
/// 枚举顺序即**抽屉自上而下**的顺序,也是纵向滑动的"胶片"顺序:
/// 从首页滑到世界,会依次经过群聊、我家、岛、身份。
enum AppSection { home, groupChats, myHome, island, identity, world, settings }

/// 底栏(横向)的滑动顺序:前五项与底栏一致;身份/设置不在底栏中,
/// 追加在末尾——仅当从它们出发横向切换时才会作为端点或途经页。
const List<AppSection> kHorizontalSectionOrder = <AppSection>[
  AppSection.home,
  AppSection.groupChats,
  AppSection.myHome,
  AppSection.island,
  AppSection.world,
  AppSection.identity,
  AppSection.settings,
];

/// 滑行时长随距离递增:首步 [AppMotion.sectionTravel],
/// 每多经过一个栏目加 [AppMotion.sectionTravelStep],
/// 封顶 [AppMotion.sectionTravelCap]。
Duration sectionTravelDuration(int distance) {
  if (distance <= 1) {
    return AppMotion.sectionTravel;
  }
  final int ms =
      AppMotion.sectionTravel.inMilliseconds +
      (distance - 1) * AppMotion.sectionTravelStep.inMilliseconds;
  if (ms > AppMotion.sectionTravelCap.inMilliseconds) {
    return AppMotion.sectionTravelCap;
  }
  return Duration(milliseconds: ms);
}

/// 对应轴的滑动顺序表。
List<AppSection> sectionOrder(Axis axis) =>
    axis == Axis.vertical ? AppSection.values : kHorizontalSectionOrder;

/// 一个栏目的"壳内零件":标题栏、内容区、悬浮按钮。
///
/// 都由 [AppSectionShell] 持有的装配表(sectionAssembly)提供;
/// 内容区是胶片的滑动物,标题栏与悬浮按钮只**换内容**、不动位置。
class SectionPageData {
  const SectionPageData({
    required this.section,
    required this.appBar,
    required this.body,
    this.fab,
    this.showArchived,
    this.contentMaxWidth = AppSize.listMaxWidth,
  });

  final AppSection section;

  /// 标题栏(位置固定,随栏目淡换)。内部需要跟归档开关联动的,
  /// 自己包 ValueListenableBuilder(见各栏目装配)。
  /// 不要求 PreferredSizeWidget——壳负责统一包一层定高。
  final Widget Function(BuildContext) appBar;

  /// 内容区:胶片滑动的单元。惰性挂载(±1 步窗口),
  /// 构造很轻,真正的 build 只发生在覆盖视口时。
  final WidgetBuilder body;

  /// 悬浮按钮(可选)。同样只换不滑;归档视图下返回收缩占位。
  final WidgetBuilder? fab;

  /// 归档视图开关:标题栏动作与内容区共用一份状态。
  /// 无归档概念的栏目(身份/设置)为 null。
  final ValueNotifier<bool>? showArchived;

  /// 内容列最大宽度。窗口比它宽时**居中收窄成一列**,窄窗口自动铺满。
  ///
  /// 标题栏、内容区、悬浮按钮共用这一份宽度 ⇒ 三者对齐同一条
  /// 内容列边缘,不会出现"标题贴最左、内容在中间"的错位。
  final double contentMaxWidth;
}

/// 进行中的一次栏目飞行:起点、终点、轴与顺序表。
class AppSectionFlight {
  const AppSectionFlight({
    required this.from,
    required this.to,
    required this.axis,
    required this.order,
    required this.fromIndex,
    required this.toIndex,
  });

  final AppSection from;
  final AppSection to;
  final Axis axis;
  final List<AppSection> order;
  final int fromIndex;
  final int toIndex;
}

/// 胶片飞行:逐帧计算各栏目的偏移并按可见窗口挂载。
///
/// 把栏目想成一条首尾相接的胶片:切换 = 胶片从当前栏目滑到目标栏目,
/// **中间栏目真的从视口里掠过**(不是凭空淡换)。纵向按抽屉顺序滑,
/// 横向按 [kHorizontalSectionOrder] 滑。
///
/// 每个栏目的偏移 = `(k - from) - t × (to - from)` 个视口
/// (t 为缓动后的进度)。途经页**接近视口(±1 步)才挂载**、
/// 离开即卸载——任意时刻最多两三页在场;各页 widget 实例全程不变,
/// 只重算位置。t=1 时仅剩目标页。
///
/// 视口取**本组件被放进去的实际区域**(LayoutBuilder 约束),
/// 而不是窗口尺寸——壳内的胶片只滑内容区,标题栏/底栏不参与。
Widget sectionFlight({
  required Animation<double> animation,
  required Axis axis,
  required int fromIndex,
  required int toIndex,
  required List<AppSection> sections,
  required List<Widget> pages,
}) {
  final Animation<double> eased = CurvedAnimation(
    parent: animation,
    curve: AppMotion.travel,
  );
  assert(pages.length == sections.length, 'pages 与 sections 一一对应');
  return AnimatedBuilder(
    animation: animation,
    builder: (BuildContext context, Widget? _) {
      final double t = eased.value;
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size vp = constraints.biggest;
          final List<Widget> layers = <Widget>[];
          for (int k = 0; k < pages.length; k++) {
            // 页面左/上边缘的位置(单位:视口)。t=1 时目标页归 0。
            final double step = (k - fromIndex) - t * (toIndex - fromIndex);
            // 可见窗口(-1, 1):仅覆盖或即将覆盖视口的页面在场,
            // 途经页惰性挂载、离开即卸。
            if (step <= -1 || step >= 1) {
              continue;
            }
            layers.add(
              Positioned(
                key: ValueKey<AppSection>(sections[k]),
                left: axis == Axis.horizontal ? step * vp.width : 0,
                top: axis == Axis.vertical ? step * vp.height : 0,
                width: vp.width,
                height: vp.height,
                child: pages[k],
              ),
            );
          }
          return Stack(clipBehavior: Clip.hardEdge, children: layers);
        },
      );
    },
  );
}

/// 主栏目壳:一个常驻的"骨架 + 内容"宿主。
///
/// **侧边栏、底部导航栏、标题栏、悬浮按钮的位置都固定在壳上**,
/// 切换栏目时只有内容区在滑胶片;标题栏与悬浮按钮随栏目
/// 淡换内容(位置不动)——这正是"框架不动、内容滑动"的布局。
///
/// 横屏:左侧常驻侧边栏 + 右侧(标题栏 + 内容)列;
/// 竖屏:抽屉导航 + 标题栏 + 内容 + 底部导航栏。
class AppSectionShell extends StatefulWidget {
  const AppSectionShell({
    super.key,
    required this.controller,
    this.initial = AppSection.home,
    this.drawerWidth = 260,
  });

  final AppController controller;
  final AppSection initial;

  /// 横屏常驻侧边栏宽度。
  final double drawerWidth;

  static AppSectionShellState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<AppSectionShellState>();

  @override
  State<AppSectionShell> createState() => AppSectionShellState();
}

class AppSectionShellState extends State<AppSectionShell>
    with SingleTickerProviderStateMixin {
  late List<SectionPageData> _sections = sectionAssembly(widget.controller);
  late AppSection _current = widget.initial;
  AppSectionFlight? _flight;

  /// 当前栏目(测试可见)。
  @visibleForTesting
  AppSection get currentSection => _current;

  late final AnimationController _drive = AnimationController(
    vsync: this,
    duration: AppMotion.sectionTravel,
  )..addListener(_onTick);

  /// 飞行到位后收起飞行描述:胶片只剩目标页,等价于静止内容。
  /// 用 value 而不是 status 监听,兼容"中途中断硬切到位"的路径。
  void _onTick() {
    if (!_drive.isAnimating && _drive.value >= 1.0 && _flight != null) {
      setState(() => _flight = null);
    }
  }

  SectionPageData? _data(AppSection s) {
    for (final SectionPageData d in _sections) {
      if (d.section == s) {
        return d;
      }
    }
    return null;
  }

  @override
  void didUpdateWidget(AppSectionShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _sections = sectionAssembly(widget.controller);
    }
  }

  /// 切换到目标栏目。抽屉纵向滑(按抽屉顺序,途经栏目逐个掠过),
  /// 底栏横向滑(按底栏顺序)。
  ///
  /// 标题栏/底栏/侧边栏高亮/悬浮按钮立即切到目标栏目;
  /// 内容区从当前位置滑向目标,途经栏目真实掠过。
  /// 飞行中再次点击:上一次飞行硬切到位,再起飞新的(不排队)。
  void navigateTo(AppSection target, {Axis axis = Axis.vertical}) {
    if (target == _current && _flight == null) {
      return;
    }
    if (target == _flight?.to) {
      return; // 已在飞往该栏目
    }
    final List<AppSection> order = sectionOrder(axis);
    final int from = order.indexOf(_current);
    final int to = order.indexOf(target);
    if (from < 0 || to < 0) {
      return;
    }
    if (_flight != null) {
      _drive.value = 1.0; // 硬切落位,监听器清掉旧飞行
    }
    _flight = AppSectionFlight(
      from: _current,
      to: target,
      axis: axis,
      order: order,
      fromIndex: from,
      toIndex: to,
    );
    _current = target; // 框架(标题栏/底栏/高亮/FAB)立即切到目标
    _drive
      ..duration = sectionTravelDuration((to - from).abs())
      ..value = 0.0;
    setState(() {});
    _drive.forward();
  }

  @override
  void dispose() {
    _drive.dispose();
    super.dispose();
  }

  Widget _film(BuildContext context) {
    final AppSectionFlight? f = _flight;
    if (f == null) {
      return _data(_current)!.body(context);
    }
    return sectionFlight(
      animation: _drive,
      axis: f.axis,
      fromIndex: f.fromIndex,
      toIndex: f.toIndex,
      sections: f.order,
      pages: <Widget>[
        for (final AppSection s in f.order) _data(s)!.body(context),
      ],
    );
  }

  /// 标题栏槽位:位置固定,内容随当前栏目淡换。
  Widget _appBarSlot() {
    final Widget bar = PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: KeyedSubtree(
        key: ValueKey<AppSection>(_current),
        child: _data(_current)!.appBar(context),
      ),
    );
    if (_flight == null) {
      return bar;
    }
    return AnimatedSwitcher(duration: AppMotion.fast, child: bar);
  }

  /// 悬浮按钮:只换不滑;飞行中随进度淡入。
  ///
  /// 按内容列留白内缩右缘 ⇒ 宽窗口下按钮不会孤零零贴在窗口最右边,
  /// 而是贴在内容列右下角(与列表右缘对齐)。
  Widget? _buildFab(BuildContext context, double inset) {
    final WidgetBuilder? fab = _data(_current)!.fab;
    if (fab == null) {
      return null;
    }
    final Widget child = fab(context);
    final Widget placed = inset > 0
        ? Padding(
            padding: EdgeInsets.only(right: inset),
            child: child,
          )
        : child;
    if (_flight == null) {
      return placed;
    }
    return AnimatedBuilder(
      animation: _drive,
      builder: (BuildContext context, Widget? _) => Opacity(
        opacity: AppMotion.travel.transform(_drive.value),
        child: placed,
      ),
    );
  }

  /// 内容列左右留白:窗口(减去常驻侧边栏)比内容列宽时居中收窄。
  ///
  /// 标题栏、内容区、悬浮按钮都用这一份留白 ⇒ 三者对齐到同一条
  /// 内容列边缘。窄窗口算出来为负,取 0(铺满,与手机端一致)。
  double _contentInset(BuildContext context, bool landscape) {
    final double area =
        MediaQuery.sizeOf(context).width -
        (landscape ? widget.drawerWidth + 1 : 0);
    final double inset = (area - _data(_current)!.contentMaxWidth) / 2;
    return inset > 0 ? inset : 0;
  }

  @override
  Widget build(BuildContext context) {
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double inset = _contentInset(context, landscape);
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 标题栏:背景与页面同色,按内容列内缩 ⇒ 标题与右侧动作
        // 都对齐到内容列边缘(视觉上仍是通栏的栏,只是内容对齐了)。
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: _appBarSlot(),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: _film(context),
          ),
        ),
      ],
    );

    if (landscape) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: widget.drawerWidth,
              child: AppDrawer(
                controller: widget.controller,
                current: _current,
                persistent: true,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
        floatingActionButton: _buildFab(context, inset),
      );
    }

    return Scaffold(
      drawer: AppDrawer(
        controller: widget.controller,
        current: _current,
        persistent: false,
      ),
      body: content,
      bottomNavigationBar: widget.controller.settings.showBottomNav
          ? AppBottomNav(controller: widget.controller, current: _current)
          : null,
      floatingActionButton: _buildFab(context, inset),
    );
  }
}
