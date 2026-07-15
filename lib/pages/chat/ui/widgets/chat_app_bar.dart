import 'package:flutter/material.dart';

import '../../../../models/ta.dart';

typedef SearchChanged = void Function(String value);
typedef NavigateMatch = void Function(int direction);
typedef ToggleSearch = void Function();
typedef ScrollToBottom = void Function();
typedef ToggleBackground = void Function();

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
    required this.rangeSummaryInProgress,
    required this.summaryInProgress,
    required this.showTokenCounts,
    required this.onRangeSummary,
    required this.onForceSummary,
    required this.onToggleTokens,
    required this.onManageSnapshots,
    required this.onExport,
    required this.backgroundMode,
    required this.ta,
    this.titleOverride,
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

  @override
  Widget build(BuildContext context) {
    return AppBar(
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
                Text(
                  searchMatchesCount > 0 && searchMatchIndex >= 0
                      ? '${searchMatchIndex + 1}/$searchMatchesCount'
                      : '0/0',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            )
          : Text(
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
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'range_summary',
                    enabled: !rangeSummaryInProgress,
                    child: const ListTile(
                      leading: Icon(Icons.summarize_outlined),
                      title: Text('范围总结'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'force_summary',
                    enabled: !summaryInProgress,
                    child: const ListTile(
                      leading: Icon(Icons.auto_awesome),
                      title: Text('强制摘要'),
                    ),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'search',
                    checked: searching,
                    child: const ListTile(
                      leading: Icon(Icons.search),
                      title: Text('消息搜索'),
                    ),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'tokens',
                    checked: showTokenCounts,
                    child: const ListTile(
                      leading: Icon(Icons.numbers),
                      title: Text('显示字数/Token'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'export',
                    child: ListTile(
                      leading: Icon(Icons.file_download_outlined),
                      title: Text('导出对话'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'archive',
                    child: ListTile(
                      leading: Icon(Icons.save),
                      title: Text('存档'),
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
