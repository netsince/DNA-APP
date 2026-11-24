import 'package:material_ui/material_ui.dart';

import '../../../../models/ta.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/utils/action_table.dart';
import 'package:dna/widgets/fit_text.dart';

typedef SearchChanged = void Function(String value);
typedef NavigateMatch = void Function(int direction);
typedef ToggleSearch = void Function();
typedef ScrollToBottom = void Function();
typedef ToggleBackground = void Function();
typedef ToggleBgm = void Function();
typedef ToggleBgmAnimation = void Function();

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({
    super.key,
    required this.searching,
    required this.searchController,
    required this.searchMatchIndex,
    required this.searchMatchesCount,
    required this.onSearchChanged,
    required this.onNavigateMatch,
    required this.onToggleSearch,
    required this.onScrollToBottom,
    required this.onToggleBackground,
    required this.onToggleBgm,
    this.bgmEnabled = false,
    this.showBgmOption = false,
    required this.onToggleBgmAnimation,
    this.bgmAnimated = false,
    this.showBgmAnimationOption = false,
    required this.rangeSummaryInProgress,
    required this.summaryInProgress,
    required this.showTokenCounts,
    required this.onRangeSummary,
    required this.onForceSummary,
    required this.onToggleTokens,
    required this.onManageSnapshots,
    required this.onExport,
    this.backgroundMode = '',
    this.ta,
    this.titleOverride,
    this.transparentBackground = false,
    this.showAppBarScrim = false,
    this.immersiveHidden = false,
    this.onToggleImmersive,
  });

  final bool searching;
  final TextEditingController searchController;
  final int searchMatchIndex;
  final int searchMatchesCount;
  final SearchChanged onSearchChanged;
  final NavigateMatch onNavigateMatch;
  final ToggleSearch onToggleSearch;
  final ScrollToBottom onScrollToBottom;
  final ToggleBackground onToggleBackground;
  final ToggleBgm onToggleBgm;
  final bool bgmEnabled;
  final bool showBgmOption;
  final ToggleBgmAnimation onToggleBgmAnimation;
  final bool bgmAnimated;
  final bool showBgmAnimationOption;
  final bool rangeSummaryInProgress;
  final bool summaryInProgress;
  final bool showTokenCounts;
  final Future<void> Function() onRangeSummary;
  final Future<void> Function() onForceSummary;
  final VoidCallback onToggleTokens;
  final Future<void> Function() onManageSnapshots;
  final Future<void> Function() onExport;
  final String backgroundMode;
  final TA? ta;
  final String? titleOverride;
  final bool transparentBackground;

  /// 是否在顶栏内画那条「上实下虚」的底色渐变。
  ///
  /// 由**当前是否真的半屏**决定（不是"开了半屏聊天"这个开关）：
  /// 动态半屏滚成全屏之后，栏下面是消息列表而不是立绘，渐变就该消失。
  final bool showAppBarScrim;

  /// 当前是否处于沉浸态（隐藏顶栏与输入岛）。只影响菜单项文案，
  /// 状态本身由聊天页持有。
  final bool immersiveHidden;

  /// 切换沉浸（⋮ 菜单里的「沉浸模式 / 退出沉浸」）。为 null 时不渲染该菜单项。
  final VoidCallback? onToggleImmersive;

  @override
  Widget build(BuildContext context) {
    final Widget bar = AppBar(
      backgroundColor: transparentBackground ? Colors.transparent : null,
      surfaceTintColor: transparentBackground ? Colors.transparent : null,
      elevation: transparentBackground ? 0 : null,
      title: searching
          ? Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '搜索消息',
                      border: InputBorder.none,
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: onSearchChanged,
                  ),
                ),
                FitText(
                  searchMatchesCount > 0 && searchMatchIndex >= 0
                      ? '${searchMatchIndex + 1}/$searchMatchesCount'
                      : '0/0',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            )
          : FitText(
              titleOverride ?? (ta?.name.isNotEmpty == true ? ta!.name : '聊天'),
            ),
      actions: searching
          ? <Widget>[
              IconButton(
                tooltip: '上一条匹配',
                onPressed: searchMatchesCount > 0 ? () => onNavigateMatch(-1) : null,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: '下一条匹配',
                onPressed: searchMatchesCount > 0 ? () => onNavigateMatch(1) : null,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              IconButton(
                tooltip: '关闭搜索',
                onPressed: onToggleSearch,
                icon: const Icon(Icons.close),
              ),
            ]
          : <Widget>[
              // 视图状态（半屏/全屏、沉浸）不再占用顶栏按钮位：
              // 半屏/全屏由滚动自动切换恢复（see docs/REGRESSION_AUDIT.md R2），
              // 沉浸收进右侧 ⋮ 菜单，顶栏回到原来的 3 个动作。
              IconButton(
                tooltip: '回到底部',
                onPressed: onScrollToBottom,
                icon: const Icon(Icons.vertical_align_bottom),
              ),
              IconButton(
                tooltip: backgroundMode == 'image' ? '关闭背景图' : '显示背景图',
                onPressed: onToggleBackground,
                icon: Icon(
                  backgroundMode == 'image' ? Icons.image_not_supported : Icons.image,
                ),
              ),
              rowActionMenu(
                tooltip: '更多',
                child: const Icon(Icons.more_horiz),
                iconSize: 24,
                // 前 6 项原来是 ListTile（非紧凑 + 水平 16 内边距），
                // 后 3 项原来是 Row(Icon, 12, 文案)：用项级样式覆盖回紧凑行。
                itemStyle: RowActionItemStyle.listTilePadded,
                iconGap: 12,
                actions: <RowAction>[
                  RowAction(
                    id: 'bgm',
                    label: '背景音乐',
                    icon: Icons.music_note_outlined,
                    visible: showBgmOption,
                    checked: bgmEnabled,
                    onSelected: onToggleBgm,
                  ),
                  RowAction(
                    id: 'bgm_animation',
                    label: '动态背景',
                    icon: Icons.animation_outlined,
                    visible: showBgmAnimationOption,
                    checked: bgmAnimated,
                    onSelected: onToggleBgmAnimation,
                  ),
                  RowAction(
                    id: 'range_summary',
                    label: '范围总结',
                    icon: Icons.summarize_outlined,
                    enabled: !rangeSummaryInProgress,
                    onSelected: onRangeSummary,
                  ),
                  RowAction(
                    id: 'force_summary',
                    label: '强制摘要',
                    icon: Icons.auto_awesome,
                    enabled: !summaryInProgress,
                    onSelected: onForceSummary,
                  ),
                  RowAction(
                    id: 'search',
                    label: '消息搜索',
                    icon: Icons.search,
                    checked: searching,
                    onSelected: onToggleSearch,
                  ),
                  RowAction(
                    id: 'tokens',
                    label: '显示字数/Token',
                    icon: Icons.numbers,
                    checked: showTokenCounts,
                    onSelected: onToggleTokens,
                  ),
                  RowAction(
                    id: 'immersive',
                    label: immersiveHidden ? '退出沉浸' : '沉浸模式',
                    icon: immersiveHidden
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    itemStyle: RowActionItemStyle.compactRow,
                    visible: onToggleImmersive != null,
                    onSelected: () => onToggleImmersive?.call(),
                  ),
                  RowAction(
                    id: 'export',
                    label: '导出对话',
                    icon: Icons.file_download_outlined,
                    itemStyle: RowActionItemStyle.compactRow,
                    onSelected: onExport,
                  ),
                  RowAction(
                    id: 'archive',
                    label: '存档',
                    icon: Icons.save,
                    itemStyle: RowActionItemStyle.compactRow,
                    onSelected: onManageSnapshots,
                  ),
                ],
              ),
            ],
    );

    if (!transparentBackground) {
      return bar;
    }
    // 半屏 / 图片背景时顶栏是透明的：标题直接压在立绘上会看不清。
    // 这里在栏内加一条「上实下虚」的蒙层（用页面底色，不是黑色遮罩）：
    // 高度**严格等于顶栏**，出了栏就完全透明，所以不会遮挡下面的立绘。
    final Color surface = Theme.of(context).colorScheme.surface;
    // 渐变本身铺满整条栏，但**只在前半段保持较实**，后半段缓降到 0：
    // 直接 0.92→0 的线性收尾会在栏底留一道看得见的分界，很生硬。
    // 显隐走 AnimatedOpacity，半屏 ↔ 全屏切换时是淡出而不是闪没。
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: showAppBarScrim ? 1.0 : 0.0,
              duration: AppMotion.medium,
              curve: Curves.easeInOutCubicEmphasized,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      surface.withValues(alpha: 0.90),
                      surface.withValues(alpha: 0.72),
                      surface.withValues(alpha: 0.30),
                      surface.withValues(alpha: 0.0),
                    ],
                    stops: const <double>[0.0, 0.45, 0.78, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
        bar,
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
