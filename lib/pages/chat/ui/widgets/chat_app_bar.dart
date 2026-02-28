import 'package:flutter/material.dart';

import '../../../../models/role.dart';

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
    required this.backgroundMode,
    required this.role,
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
  final String backgroundMode;
  final Role? role;
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
              titleOverride ??
                  (role?.name.isNotEmpty == true ? role!.name : '聊天'),
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
            ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
