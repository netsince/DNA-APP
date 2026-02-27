import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.inputController,
    required this.sending,
    required this.inspirationInProgress,
    required this.rangeSummaryInProgress,
    required this.summaryInProgress,
    required this.searching,
    required this.showTokenCounts,
    required this.onSend,
    required this.onStartInspiration,
    required this.onManageSnapshots,
    required this.onToggleSearch,
    required this.onToggleTokens,
    required this.onForceSummary,
    required this.onRangeSummary,
  });

  final TextEditingController inputController;
  final bool sending;
  final bool inspirationInProgress;
  final bool rangeSummaryInProgress;
  final bool summaryInProgress;
  final bool searching;
  final bool showTokenCounts;
  final VoidCallback onSend;
  final Future<void> Function() onStartInspiration;
  final Future<void> Function() onManageSnapshots;
  final VoidCallback onToggleSearch;
  final VoidCallback onToggleTokens;
  final Future<void> Function() onForceSummary;
  final Future<void> Function() onRangeSummary;

  Future<void> _handleMenu(String value) async {
    if (value == 'archive') {
      await onManageSnapshots();
    } else if (value == 'search') {
      onToggleSearch();
    } else if (value == 'tokens') {
      onToggleTokens();
    } else if (value == 'force_summary') {
      await onForceSummary();
    } else if (value == 'range_summary') {
      await onRangeSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: inputController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '输入消息...'),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '灵感',
              onPressed: inspirationInProgress ? null : () => onStartInspiration(),
              icon: inspirationInProgress
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (String value) {
                _handleMenu(value);
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'range_summary',
                  enabled: !rangeSummaryInProgress,
                  child: ListTile(
                    leading: Icon(Icons.summarize_outlined),
                    title: Text('范围总结'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'force_summary',
                  enabled: !summaryInProgress,
                  child: ListTile(
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
                  value: 'archive',
                  child: ListTile(
                    leading: Icon(Icons.save),
                    title: Text('存档'),
                  ),
                ),
              ],
              child: const Icon(Icons.more_horiz),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: sending ? null : onSend,
              child: Text(sending ? '发送中...' : '发送'),
            ),
          ],
        ),
      ),
    );
  }
}
