import 'package:flutter/material.dart';

class ChatInputBar extends StatefulWidget {
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
    this.onTap,
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
  final VoidCallback? onTap;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  bool _hasInput = false;

  @override
  void initState() {
    super.initState();
    widget.inputController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    widget.inputController.removeListener(_onInputChanged);
    super.dispose();
  }

  void _onInputChanged() {
    final bool hasText = widget.inputController.text.trim().isNotEmpty;
    if (hasText != _hasInput) {
      setState(() {
        _hasInput = hasText;
      });
    }
  }

  Future<void> _handleMenu(String value) async {
    if (value == 'archive') {
      await widget.onManageSnapshots();
    } else if (value == 'search') {
      widget.onToggleSearch();
    } else if (value == 'tokens') {
      widget.onToggleTokens();
    } else if (value == 'force_summary') {
      await widget.onForceSummary();
    } else if (value == 'range_summary') {
      await widget.onRangeSummary();
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
                controller: widget.inputController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '输入消息...'),
                onSubmitted: (_) => widget.onSend(),
                onTap: widget.onTap,
              ),
            ),
            const SizedBox(width: 8),
            // 当输入框没有内容时显示灵感按钮
            if (!_hasInput)
              IconButton(
                tooltip: '灵感',
                onPressed: widget.inspirationInProgress ? null : () => widget.onStartInspiration(),
                icon: widget.inspirationInProgress
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
                  enabled: !widget.rangeSummaryInProgress,
                  child: ListTile(
                    leading: Icon(Icons.summarize_outlined),
                    title: Text('范围总结'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'force_summary',
                  enabled: !widget.summaryInProgress,
                  child: ListTile(
                    leading: Icon(Icons.auto_awesome),
                    title: Text('强制摘要'),
                  ),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'search',
                  checked: widget.searching,
                  child: const ListTile(
                    leading: Icon(Icons.search),
                    title: Text('消息搜索'),
                  ),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'tokens',
                  checked: widget.showTokenCounts,
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
            // 发送按钮改成图标
            IconButton(
              tooltip: widget.sending ? '发送中...' : '发送',
              onPressed: widget.sending ? null : widget.onSend,
              icon: widget.sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
