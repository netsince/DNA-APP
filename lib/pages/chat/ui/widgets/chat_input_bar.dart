import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../services/speech_to_text_service.dart';
import '../../../../state/app_controller.dart';
import '../../../../utils/ui_feedback.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.inputController,
    required this.inputFocusNode,
    required this.sending,
    required this.inspirationInProgress,
    required this.onSend,
    required this.onStartInspiration,
    this.onTap,
  });

  final AppController controller;
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

  /// 是否正在语音录音。
  bool _recording = false;

  StreamSubscription<String>? _partialSub;

  @override
  void initState() {
    super.initState();
    _prevText = widget.inputController.text;
    _prevSelection = widget.inputController.selection;
    widget.inputController.addListener(_onInputChanged);
    _partialSub = SpeechToTextService.instance.partial.listen(_onPartial);
  }

  @override
  void dispose() {
    widget.inputController.removeListener(_onInputChanged);
    _partialSub?.cancel();
    super.dispose();
  }

  /// 当前选中的模型是否已下载就绪。
  bool get _voiceReady {
    final String? p = widget.controller.settings.sherpaModelPath;
    return widget.controller.settings.sherpaModelReady &&
        p != null &&
        p.endsWith(widget.controller.settings.selectedVoiceModelId);
  }

  void _onInputChanged() {
    final bool hasText = widget.inputController.text.trim().isNotEmpty;
    if (hasText != _hasInput) {
      setState(() {
        _hasInput = hasText;
      });
    }
  }

  /// 语音识别实时结果：录音中同步到输入框。
  void _onPartial(String text) {
    if (!_recording) {
      return;
    }
    widget.inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
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

  Future<void> _startVoice() async {
    final String? path = widget.controller.settings.sherpaModelPath;
    if (path == null || !widget.controller.settings.sherpaModelReady) {
      if (mounted) {
        showSnack(context, '请先在「设置 → 语音输入」中下载模型');
      }
      return;
    }
    try {
      await SpeechToTextService.instance.ensureInitialized(path);
    } catch (e) {
      if (mounted) {
        showSnack(context, '模型初始化失败：$e');
      }
      return;
    }

    final bool ok = await SpeechToTextService.instance.start();
    if (!ok) {
      if (mounted) {
        showSnack(context, '无法使用麦克风，请检查系统麦克风权限');
      }
      return;
    }
    widget.inputController.clear();
    if (mounted) {
      setState(() => _recording = true);
    }
  }

  Future<void> _stopVoice() async {
    if (!_recording) {
      return;
    }
    final String text = await SpeechToTextService.instance.stop();
    if (mounted) {
      setState(() => _recording = false);
    }
    if (text.isNotEmpty) {
      final String existing = widget.inputController.text;
      final String combined = existing.isEmpty ? text : '$existing $text';
      widget.inputController.value = TextEditingValue(
        text: combined,
        selection: TextSelection.collapsed(offset: combined.length),
      );
      widget.onSend();
    }
  }

  Future<void> _cancelVoice() async {
    await SpeechToTextService.instance.cancel();
    if (mounted) {
      setState(() => _recording = false);
    }
  }

  Widget _buildMic() {
    if (!_voiceReady) {
      return IconButton(
        tooltip: '语音输入（需先下载模型）',
        onPressed: () =>
            showSnack(context, '请先在「设置 → 语音输入」中下载语音模型'),
        icon: const Icon(Icons.mic_none_outlined),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _startVoice(),
      onLongPressEnd: (_) => _stopVoice(),
      onLongPressCancel: () => _cancelVoice(),
      onTap: () => showSnack(context, '长按麦克风按钮说话，松手自动发送'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          Icons.mic,
          color: _recording ? Colors.red : null,
        ),
      ),
    );
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
                decoration: InputDecoration(
                  hintText: _recording ? '聆听中…松手发送' : '输入消息...',
                ),
                onSubmitted: (_) => widget.onSend(),
                onTap: widget.onTap,
              ),
            ),
            const SizedBox(width: 8),
            // 语音输入按钮（长按说话）
            _buildMic(),
            const SizedBox(width: 8),
            // 当输入框没有内容时显示灵感按钮
            if (!_hasInput)
              IconButton(
                tooltip: '灵感',
                onPressed: widget.inspirationInProgress
                    ? null
                    : () => widget.onStartInspiration(),
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
