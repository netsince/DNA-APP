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

/// 左括号 -> 右括号 映射，用于自动补全。
const Map<String, String> _openToClose = <String, String>{
  '(': ')',
  '[': ']',
  '{': '}',
  '「': '」',
  '【': '】',
  '『': '』',
  '"': '"',
  "'": "'",
};

/// 右括号 -> 左括号 映射，用于跳过已存在的右括号。
final Map<String, String> _closeToOpen =
    _openToClose.map((String k, String v) => MapEntry<String, String>(v, k));

class _ChatInputBarState extends State<ChatInputBar> {
  bool _hasInput = false;

  /// 上一次文本与光标，用于推断本次插入的字符。
  String _prevText = '';
  TextSelection _prevSelection = const TextSelection.collapsed(offset: 0);

  /// 防止程序化修改文本时递归触发自动补全。
  bool _isAdjusting = false;

  @override
  void initState() {
    super.initState();
    _prevText = widget.inputController.text;
    _prevSelection = widget.inputController.selection;
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

  /// 自动补全括号：输入左括号时补上右括号并把光标置于中间；
  /// 输入右括号且其后已存在相同右括号时，直接跳过而不重复插入。
  void _onChanged(String value) {
    if (_isAdjusting) {
      _prevText = value;
      _prevSelection = widget.inputController.selection;
      return;
    }

    final TextEditingController controller = widget.inputController;
    final TextSelection prevSel = _prevSelection;
    final TextSelection curSel = controller.selection;

    // 仅处理「光标未选中、仅插入 1 个字符」的简单场景。
    if (prevSel.isCollapsed && value.length == _prevText.length + 1) {
      final int insertPos = prevSel.start;
      if (insertPos >= 0 && insertPos < value.length && curSel.isValid) {
        final String inserted = value[insertPos];

        final String? close = _openToClose[inserted];
        if (close != null) {
          _isAdjusting = true;
          final String newText = value.substring(0, curSel.start) +
              close +
              value.substring(curSel.start);
          controller.value = controller.value.copyWith(
            text: newText,
            selection: TextSelection.collapsed(offset: curSel.start),
          );
          _isAdjusting = false;
          _prevText = newText;
          _prevSelection = controller.selection;
          return;
        }

        final String? openFor = _closeToOpen[inserted];
        if (openFor != null &&
            curSel.start < value.length &&
            value[curSel.start] == inserted) {
          _isAdjusting = true;
          controller.value = controller.value.copyWith(
            selection: TextSelection.collapsed(offset: curSel.start + 1),
          );
          _isAdjusting = false;
          _prevText = value;
          _prevSelection = controller.selection;
          return;
        }
      }
    }

    _prevText = value;
    _prevSelection = curSel;
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
                onChanged: _onChanged,
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
