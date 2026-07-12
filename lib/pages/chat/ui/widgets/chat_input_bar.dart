import 'package:flutter/material.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.inputController,
    required this.inputFocusNode,
    required this.sending,
    required this.inspirationInProgress,
    required this.onSend,
    required this.onStartInspiration,
    this.onTap,
  });

  final TextEditingController inputController;
  final FocusNode inputFocusNode;
  final bool sending;
  final bool inspirationInProgress;
  final VoidCallback onSend;
  final Future<void> Function() onStartInspiration;
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
                focusNode: widget.inputFocusNode,
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
