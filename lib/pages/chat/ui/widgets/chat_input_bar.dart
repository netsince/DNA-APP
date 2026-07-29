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

  /// 是否处于「语音输入模式」（隐藏普通输入栏，显示语音条）。
  bool _voiceMode = false;

  /// 是否正在聆听。
  bool _voiceListening = false;

  /// 点击停止后进入「待确认」状态：长条裂变为 修改 / 发送 / 取消。
  bool _voiceReview = false;

  /// 本次聆听是否由「长按」触发：
  /// 长按松开 = 直接发送；点击 = 再点一次停止并进入待确认。
  bool _enteredByLongPress = false;

  /// start() 正在进行中（防止重复触发导致并发 start）。
  bool _starting = false;

  /// 长按松开发生在 start() 完成之前时标记：start 完成后立即停止并发送。
  bool _pendingSend = false;

  /// 长按被系统中断且 start() 未完成时标记：start 完成后立即取消。
  bool _pendingCancel = false;

  /// 按下计时器：用于区分长按（>=180ms）与点击。
  Timer? _longPressTimer;

  /// 当前是否有指针按下未抬起。
  bool _pressActive = false;

  /// 本次按下是否已触发长按（计时器到点）。
  bool _longPressFired = false;

  /// 语音模式下的实时识别文本。
  String _transcript = '';

  /// 进入语音模式前输入框里已有的文字，发送时拼接到识别结果前。
  String _preRecordText = '';

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
    _longPressTimer?.cancel();
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

  /// 语音识别实时结果：聆听中同步到语音条的识别文本。
  void _onPartial(String text) {
    if (!_voiceListening) {
      return;
    }
    if (mounted) {
      setState(() => _transcript = text);
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

  /// 点击麦克风：进入语音输入模式（隐藏普通输入框，显示语音条）。
  void _enterVoiceMode() {
    if (!_voiceReady) {
      showSnack(context, '请先在「设置 → 语音输入」中下载模型');
      return;
    }
    if (mounted) {
      setState(() {
        _voiceMode = true;
        _voiceListening = false;
        _voiceReview = false;
        _enteredByLongPress = false;
        _transcript = '';
        _preRecordText = widget.inputController.text;
      });
    }
    // 预热识别器：进入语音模式时即开始构建，按下长按/点击时 start() 几乎无延迟。
    // 失败忽略：真正按下时 _startListening 会再次初始化并提示错误。
    final String p = widget.controller.settings.sherpaModelPath!;
    SpeechToTextService.instance.ensureInitialized(p).catchError((Object _) {});
  }

  /// 退出语音模式，回到普通文本输入。
  void _exitVoiceMode() {
    if (_voiceListening) {
      SpeechToTextService.instance.cancel();
    }
    if (mounted) {
      setState(() {
        _voiceMode = false;
        _voiceListening = false;
        _voiceReview = false;
        _enteredByLongPress = false;
        _transcript = '';
      });
    }
  }

  Future<void> _startListening() async {
    if (_voiceListening || _starting) {
      return;
    }
    _starting = true;
    try {
      final String? p = widget.controller.settings.sherpaModelPath;
      await SpeechToTextService.instance.ensureInitialized(p!);
      final bool ok = await SpeechToTextService.instance.start();
      if (!ok) {
        if (mounted) {
          showSnack(context, '无法使用麦克风，请检查系统麦克风权限');
        }
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceListening = true;
        _transcript = '';
      });
      // 松手/中断发生在 start() 完成之前：现在按当时的意图处理。
      if (_pendingSend) {
        _pendingSend = false;
        _stopAndSend();
      } else if (_pendingCancel) {
        _pendingCancel = false;
        _cancelToListenIdle();
      }
    } catch (e) {
      // 任何初始化/启动异常都复位状态，避免卡在「聆听中」。
      _pendingSend = false;
      _pendingCancel = false;
      _enteredByLongPress = false;
      if (mounted) {
        showSnack(context, '语音启动失败：$e');
      }
    } finally {
      _starting = false;
    }
  }

  /// 长按松开：停止并直接发送；若没识别到内容则回到未聆听语音模式以便重试。
  /// 任何异常都会复位状态，避免卡在「聆听中」。
  Future<void> _stopAndSend() async {
    if (!_voiceListening) {
      return;
    }
    String text;
    try {
      text = await SpeechToTextService.instance.stop();
    } catch (e) {
      if (mounted) {
        showSnack(context, '停止录音失败：$e');
        setState(() {
          _voiceListening = false;
          _enteredByLongPress = false;
          _transcript = '';
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final String t = text.trim();
    if (t.isEmpty) {
      // 没识别到内容：不发送，回到未聆听的语音模式。
      setState(() {
        _voiceListening = false;
        _enteredByLongPress = false;
        _transcript = '';
      });
      return;
    }
    setState(() {
      _voiceListening = false;
      _transcript = text;
    });
    _commitAndExit(text);
  }

  /// 点击停止：进入待确认状态（长条裂变为 修改 / 发送 / 取消）。
  Future<void> _stopAndReview() async {
    if (!_voiceListening) {
      return;
    }
    String text;
    try {
      text = await SpeechToTextService.instance.stop();
    } catch (e) {
      if (mounted) {
        showSnack(context, '停止录音失败：$e');
        setState(() {
          _voiceListening = false;
          _enteredByLongPress = false;
          _transcript = '';
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceListening = false;
      _voiceReview = true;
      _transcript = text;
    });
  }

  /// 长按被系统中断：取消聆听，回到未聆听的语音模式。
  Future<void> _cancelToListenIdle() async {
    try {
      await SpeechToTextService.instance.cancel();
    } catch (e) {
      if (mounted) {
        showSnack(context, '停止录音失败：$e');
      }
    }
    if (mounted) {
      setState(() {
        _voiceListening = false;
        _transcript = '';
      });
    }
  }

  /// 待确认 → 修改：回到文本模式，输入框带上识别结果。
  void _editTranscript() {
    final String t = _transcript.trim();
    final String base = _preRecordText;
    final String msg = base.isEmpty
        ? t
        : (base.endsWith(' ') || t.isEmpty ? '$base$t' : '$base $t');
    widget.inputController.text = msg;
    widget.inputController.selection =
        TextSelection.collapsed(offset: msg.length);
    _exitVoiceMode();
  }

  /// 待确认 → 发送。
  void _sendFromReview() {
    _commitAndExit(_transcript);
  }

  /// 待确认 → 取消：回到未聆听的语音模式（丢弃本次识别）。
  void _discardReview() {
    if (mounted) {
      setState(() {
        _voiceReview = false;
        _transcript = '';
      });
    }
  }

  /// 把识别文字拼上进入前已有文字，写入输入框并发送，退出语音模式。
  void _commitAndExit(String transcript) {
    final String t = transcript.trim();
    if (t.isEmpty) {
      _exitVoiceMode();
      return;
    }
    final String base = _preRecordText;
    final String msg = base.isEmpty
        ? t
        : (base.endsWith(' ') ? '$base$t' : '$base $t');
    widget.inputController.text = msg;
    _exitVoiceMode();
    widget.onSend();
  }

  /// 普通文本模式下的麦克风按钮：点击进入语音输入模式。
  Widget _buildMic() {
    return IconButton(
      tooltip: _voiceReady ? '语音输入' : '语音输入（需先下载模型）',
      onPressed: _voiceReady
          ? _enterVoiceMode
          : () =>
              showSnack(context, '请先在「设置 → 语音输入」中下载语音模型'),
      icon: Icon(_voiceReady ? Icons.mic : Icons.mic_none_outlined),
    );
  }

  /// 语音输入模式面板：根据 聆听 / 待确认 / 未聆听 三态切换布局。
  Widget _buildVoicePanel() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool hasText = _transcript.trim().isNotEmpty;

    // 待确认：长条裂变为 修改 / 取消 / 发送
    if (_voiceReview) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildBackRow(cs),
              const SizedBox(height: 8),
              _buildTranscriptArea(theme, cs, hasText, '识别完成'),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _editTranscript,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('修改'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _discardReview,
                      icon: const Icon(Icons.close),
                      label: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sendFromReview,
                      icon: const Icon(Icons.send),
                      label: const Text('发送'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // 聆听中：返回按钮隐藏，大长条占满底部
    if (_voiceListening) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildTranscriptArea(theme, cs, hasText, '聆听中…'),
              const SizedBox(height: 10),
              SizedBox(
                height: 120,
                child: _buildBigVoiceButton(cs, listening: true),
              ),
            ],
          ),
        ),
      );
    }

    // 未聆听：返回按钮 + 小区域 + 大长条
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildBackRow(cs),
            const SizedBox(height: 8),
            _buildTranscriptArea(theme, cs, hasText, '长按或点击下方按钮说话'),
            const SizedBox(height: 10),
            _buildBigVoiceButton(cs, listening: false),
          ],
        ),
      ),
    );
  }

  /// 语音模式顶部返回按钮：退出语音模式，回到文本输入。
  Widget _buildBackRow(ColorScheme cs) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        tooltip: '返回',
        onPressed: _exitVoiceMode,
        icon: const Icon(Icons.arrow_back),
      ),
    );
  }

  /// 上方小区域：显示实时识别文本或占位提示。
  Widget _buildTranscriptArea(
      ThemeData theme, ColorScheme cs, bool hasText, String placeholder) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
        color: _voiceListening
            ? cs.errorContainer.withValues(alpha: 0.12)
            : cs.surfaceContainerHighest,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          hasText ? _transcript : placeholder,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: hasText ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 大长条语音按钮：用 Listener + Timer 自己判定长按/点击，避免手势识别器竞态。
  /// - 按住 >=180ms = 长按：聆听，松开直接发送；
  /// - 快速点击：开始聆听，再点一次停止并进入待确认。
  Widget _buildBigVoiceButton(ColorScheme cs, {required bool listening}) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: listening ? cs.error : cs.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              listening ? Icons.mic : Icons.mic_none,
              color: listening ? cs.onError : cs.onPrimary,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              listening
                  ? (_enteredByLongPress ? '松开发送' : '再点一次停止')
                  : '按住或点击说话',
              style: TextStyle(
                color: listening ? cs.onError : cs.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _pressActive = true;
    _longPressFired = false;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(milliseconds: 180), () {
      _longPressFired = true;
      _enteredByLongPress = true;
      _startListening(); // 长按到点：开始聆听
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_pressActive) {
      return;
    }
    _pressActive = false;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    if (_longPressFired) {
      // 长按下抬起：直接发送（长按语义）
      if (_voiceListening) {
        _stopAndSend();
      } else {
        _pendingSend = true; // start 未完成，待其完成后发送
      }
    } else {
      // 快速点击抬起：点击语义
      _enteredByLongPress = false;
      if (!_voiceListening) {
        _startListening();
      } else if (!_enteredByLongPress) {
        _stopAndReview();
      } else {
        _stopAndSend(); // 兜底
      }
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (!_pressActive) {
      return;
    }
    _pressActive = false;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    if (_longPressFired) {
      // 长按被系统中断
      if (_voiceListening) {
        _cancelToListenIdle();
      } else {
        _pendingCancel = true; // start 未完成，待其完成后取消
      }
    } else {
      _enteredByLongPress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_voiceMode) {
      return _buildVoicePanel();
    }
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
                decoration: const InputDecoration(
                  hintText: '输入消息...',
                ),
                onSubmitted: (_) => widget.onSend(),
                onTap: widget.onTap,
              ),
            ),
            const SizedBox(width: 8),
            // 语音输入按钮（点击进入语音模式）
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
