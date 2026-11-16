import 'package:flutter/material.dart';

import '../../../../models/ta.dart';
import 'package:dna/theme/tokens.dart';
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

  /// 当前是否处于沉浸态（隐藏顶栏与输入岛）。只影响菜单项文案，
  /// 状态本身由聊天页持有。
  final bool immersiveHidden;

  /// 切换沉浸（⋮ 菜单里的「沉浸模式 / 退出沉浸」）。为 null 时不渲染该菜单项。
  final VoidCallback? onToggleImmersive;

  @override
  Widget build(BuildContext context) {
    return AppBar(
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
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (String value) {
                  if (value == 'archive') {
                    onManageSnapshots();
                  } else if (value == 'export') {
                    onExport();
                  } else if (value == 'search') {
                    onToggleSearch();
                  } else if (value == 'tokens') {
                    onToggleTokens();
                  } else if (value == 'force_summary') {
                    onForceSummary();
                  } else if (value == 'range_summary') {
                    onRangeSummary();
                  } else if (value == 'bgm') {
                    onToggleBgm();
                  } else if (value == 'bgm_animation') {
                    onToggleBgmAnimation();
                  } else if (value == 'immersive') {
                    onToggleImmersive?.call();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  if (showBgmOption)
                    CheckedPopupMenuItem<String>(
                      value: 'bgm',
                      checked: bgmEnabled,
                      child: const ListTile(
                        leading: Icon(Icons.music_note_outlined),
                        title: FitText('背景音乐'),
                      ),
                    ),
                  if (showBgmAnimationOption)
                    CheckedPopupMenuItem<String>(
                      value: 'bgm_animation',
                      checked: bgmAnimated,
                      child: const ListTile(
                        leading: Icon(Icons.animation_outlined),
                        title: FitText('动态背景'),
                      ),
                    ),
                  PopupMenuItem<String>(
                    value: 'range_summary',
                    enabled: !rangeSummaryInProgress,
                    child: const ListTile(
                      leading: Icon(Icons.summarize_outlined),
                      title: FitText('范围总结'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'force_summary',
                    enabled: !summaryInProgress,
                    child: const ListTile(
                      leading: Icon(Icons.auto_awesome),
                      title: FitText('强制摘要'),
                    ),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'search',
                    checked: searching,
                    child: const ListTile(
                      leading: Icon(Icons.search),
                      title: FitText('消息搜索'),
                    ),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'tokens',
                    checked: showTokenCounts,
                    child: const ListTile(
                      leading: Icon(Icons.numbers),
                      title: FitText('显示字数/Token'),
                    ),
                  ),
                  if (onToggleImmersive != null)
                    PopupMenuItem<String>(
                      value: 'immersive',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            immersiveHidden
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                          ),
                          AppSpacing.wMd,
                          FitText(immersiveHidden ? '退出沉浸' : '沉浸模式'),
                        ],
                      ),
                    ),
                  const PopupMenuItem<String>(
                    value: 'export',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[Icon(Icons.file_download_outlined), AppSpacing.wMd, FitText('导出对话')],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'archive',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[Icon(Icons.save), AppSpacing.wMd, FitText('存档')],
                    ),
                  ),
                ],
                child: const Icon(Icons.more_horiz),
              ),
            ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
