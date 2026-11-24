import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'package:dna/theme/tokens.dart';
import 'package:flutter/services.dart';

import '../../../../models/attachment_draft.dart';
import '../../../../models/message_attachment.dart';
import '../../../../models/quick_reply.dart';
import '../../../../services/attachment_intake.dart';
import '../../../../utils/error_display.dart';
import '../../../../utils/platform_capabilities.dart';
import '../../../../utils/ui_feedback.dart';
import '../../../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.inputController,
    required this.inputFocusNode,
    required this.sending,
    required this.inspirationInProgress,
    required this.onSend,
    required this.attachments,
    required this.visionEnabled,
    required this.onStartInspiration,
    this.quickReplies = const <QuickReply>[],
    this.onQuickReply,
    this.onTap,
    this.onStopGeneration,
    this.halfScreen = false,
  });

  final AppController controller;
  final TextEditingController inputController;
  final FocusNode inputFocusNode;
  final bool sending;
  final bool inspirationInProgress;
  final VoidCallback onSend;

  /// 「停止生成」回调。非空且 [sending] 为 true 时,发送按钮变为可点的停止按钮;
  /// 为 null 时保持旧行为(生成中仅显示转圈、不可点)。
  final VoidCallback? onStopGeneration;
  /// 待发送附件草稿（与 ChatSurface 共享，回溯回填也写它）。
  final AttachmentDraft attachments;

  /// 当前模型是否支持图片输入（决定抽屉里要不要给「相册 / 照相」）。
  final bool visionEnabled;

  final Future<void> Function() onStartInspiration;

  /// 快速回复按钮列表（显示在输入栏上方）。
  final List<QuickReply> quickReplies;

  /// 点击某个快速回复按钮（尚未做宏替换，由上层处理并发送）。
  final ValueChanged<QuickReply>? onQuickReply;
  final VoidCallback? onTap;
  final bool halfScreen;

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

  /// 最近一次点击「停止生成」的时刻,用于吞掉停止后同一手势跨重建
  /// 误触到发送键的竞态(见 [_sendSafe] 与 [_buildSendOrStopButton])。
  DateTime? _lastStopAt;

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
    widget.attachments.addListener(_onAttachmentsChanged);
  }

  @override
  void dispose() {
    widget.inputController.removeListener(_onInputChanged);
    widget.attachments.removeListener(_onAttachmentsChanged);
    super.dispose();
  }

  void _onAttachmentsChanged() {
    if (mounted) setState(() {});
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

  /// 回车键行为。true = 回车发送、Shift+回车换行；false = 回车换行、Shift+回车发送。
  bool get _enterToSend => widget.controller.settings.enterToSend;

  /// 处理回车键：根据 [enterToSend] 决定发送还是换行。
  ///
  /// `enter` 表示是否按下了 Shift（即 Enter 是否带 Shift 修饰）。
  void _handleEnter({required bool shift}) {
    final bool send = _enterToSend ? !shift : shift;
    if (send) {
      widget.onSend();
    } else {
      _insertNewline();
    }
  }

  /// 在光标处插入换行（回车换行模式用）。
  void _insertNewline() {
    final TextEditingController controller = widget.inputController;
    final TextSelection sel = controller.selection;
    if (!sel.isValid) return;
    final String text = controller.text;
    final int start = sel.start;
    final int end = sel.end;
    final String newText = text.replaceRange(start, end, '\n');
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
    // 同步自动补全追踪，避免后续输入被误判。
    _prevText = newText;
    _prevSelection = controller.selection;
  }

  /// 文本输入框：通过 Shortcuts/Actions 处理回车与换行的键盘策略。
  ///
  /// [capsule] 为真：去掉描边与自定内边距，外观交给外层胶囊容器（输入岛）；
  /// 为假：什么都不指定，走当时的「默认输入框」样式（下划线、无填充），
  /// 即 0.2.0 的旧样式（由 [_buildClassicBar] 摘掉全局输入框样式后生效）。
  Widget _buildTextField({required bool capsule}) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // 回车 / 小键盘回车（区分是否带 Shift）
        const SingleActivator(LogicalKeyboardKey.enter):
            const _EnterIntent(shift: false),
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const _EnterIntent(shift: false),
        const SingleActivator(LogicalKeyboardKey.enter, shift: true):
            const _EnterIntent(shift: true),
        const SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true):
            const _EnterIntent(shift: true),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _EnterIntent: CallbackAction<_EnterIntent>(
            onInvoke: (Intent intent) {
              final _EnterIntent e = intent as _EnterIntent;
              _handleEnter(shift: e.shift);
              // 返回非 null 表示已消费该事件，避免 TextField 再默认处理回车。
              return true;
            },
          ),
        },
        child: TextField(
          controller: widget.inputController,
          focusNode: widget.inputFocusNode,
          minLines: 1,
          maxLines: 4,
          onChanged: _onChanged,
          decoration: capsule
              ? const InputDecoration(
                  hintText: '输入消息...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                )
              : const InputDecoration(hintText: '输入消息...'),
          onTap: widget.onTap,
          textInputAction:
              _enterToSend ? TextInputAction.send : TextInputAction.newline,
        ),
      ),
    );
  }

  /// 在输入框末尾追加一对全角括号（），并把光标置于括号中间。
  void _insertParens() {
    final TextEditingController controller = widget.inputController;
    final String text = controller.text;
    final String newText = '$text（）';
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: text.length + 1),
    );
    // 同步自动补全的追踪状态，避免后续手动输入被误判为「插入左括号」而再次补全。
    _prevText = newText;
    _prevSelection = controller.selection;
    widget.inputFocusNode.requestFocus();
  }

  /// 添加括号按钮：始终显示（不受输入内容影响），由设置控制是否展示。
  Widget _buildParenButton(ColorScheme cs) {
    return IconButton(
      tooltip: '添加括号',
      color: cs.onSurfaceVariant,
      onPressed: _insertParens,
      icon: const Text(
        '（）',
        style: TextStyle(fontSize: AppFontSize.subtitle, fontWeight: AppWeight.medium),
      ),
    );
  }








  /// 快速回复按钮行：横向滚动的精致卡片胶囊，点击立即发送对应内容。
  Widget _buildQuickReplies() {
    if (widget.quickReplies.isEmpty) {
      return const SizedBox.shrink();
    }
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: widget.quickReplies.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final QuickReply qr = widget.quickReplies[index];
          return Material(
            color: cs.surfaceContainerHighest.withValues(
              alpha: widget.halfScreen ? 0.65 : 0.85,
            ),
            borderRadius: AppRadius.lgAll,
            child: InkWell(
              borderRadius: AppRadius.lgAll,
              onTap: widget.onQuickReply == null
                  ? null
                  : () => widget.onQuickReply!(qr),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(
                    color: cs.outlineVariant.withValues(
                      alpha: widget.halfScreen ? 0.4 : 0.55,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 13,
                      color: cs.primary.withValues(alpha: AppAlpha.a85),
                    ),
                    const SizedBox(width: 4),
                    FitText(
                      qr.label.isEmpty ? '回复' : qr.label,
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: AppWeight.medium,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    // 输入栏样式：'capsule'（默认，胶囊输入岛）/ 'classic'（0.2.0 旧样式）。
    // 两种都在「设置 → 界面与显示 → 聊天输入栏」里可选，功能完全一致。
    final bool capsule =
        widget.controller.settings.chatInputStyle != 'classic';
    return SafeArea(
      top: false,
      child: Padding(
        padding: capsule
            ? const EdgeInsets.fromLTRB(12, 4, 12, 10)
            : const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildQuickReplies(),
            SizedBox(height: capsule ? 4 : 6),
            if (widget.attachments.isNotEmpty) ...<Widget>[
              _buildAttachmentStrip(cs),
              SizedBox(height: capsule ? 6 : 8),
            ],
            if (capsule) _buildCapsuleBar(cs) else _buildClassicBar(cs),
          ],
        ),
      ),
    );
  }

  /// 胶囊样式（默认）：输入框与所有按钮装在同一个圆角容器里（悬浮输入岛）。
  Widget _buildCapsuleBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 3, 6, 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(
          alpha: widget.halfScreen ? 0.72 : 0.95,
        ),
        // 圆角与阴影都用令牌（审计 4.4）：以前是手写 999 与一条自造阴影。
        // 半透明输入岛的层次由 AppShadows.soft 统一表达。
        borderRadius: AppRadius.pillAll,
        border: Border.all(
          color: cs.outlineVariant.withValues(
            alpha: widget.halfScreen ? 0.35 : 0.5,
          ),
        ),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(child: _buildTextField(capsule: true)),
          _buildTrailingActions(cs, capsule: true),
        ],
      ),
    );
  }

  /// 旧样式（0.2.0）：**下划线输入框 + 框外各自独立的图标按钮**。
  ///
  /// 0.2.0 的输入框用的就是 Flutter 的默认输入框（下划线、无填充），因为
  /// 那时主项目还没有全局的 `inputDecorationTheme`。后来全局配上了「描边
  /// 圆角 + 填充」的输入框样式，所以这里要把全局样式**临时摘掉**，否则
  /// 这一栏会长成一个描边方框 —— 那就不是 0.2.0 的样子了。
  ///
  /// 与胶囊样式的区别只有「外观」：回车/换行策略、语音、灵感、发送与停止
  /// 的行为完全一致（旧版本没有「停止生成」，这里保留）。
  Widget _buildClassicBar(ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: const InputDecorationThemeData(
                filled: false,
              ),
            ),
            child: _buildTextField(capsule: false),
          ),
        ),
        _buildTrailingActions(cs, capsule: false),
      ],
    );
  }

  /// 上传文件按钮：满了就禁用（tooltip 说明原因，不做无声失败）。
  Widget _buildUploadButton(ColorScheme cs) {
    final bool full = widget.attachments.remainingSlots == 0;
    return IconButton(
      tooltip: full ? '最多只能带 3 个附件' : '上传文件',
      color: cs.onSurfaceVariant,
      onPressed: full ? null : _openUploadSheet,
      icon: const Icon(Icons.attach_file_rounded),
    );
  }

  /// 从底部滑出的上传抽屉：文件 / 相册 / 照相。
  ///
  /// 相册与照相只在「当前模型支持视觉」时出现 —— 模型吃不下的东西不给入口，
  /// 比让用户传完再看到失败要体面。照相在 PC（含 Web）上不出现。
  Future<void> _openUploadSheet() async {
    final bool canImage = widget.visionEnabled;
    final bool canCamera = canImage &&
        !PlatformCapabilities.isDesktop &&
        !kIsWeb;
    final _UploadChoice? choice = await showModalBottomSheet<_UploadChoice>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ColorScheme cs = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          // 矮屏 / 横屏 / 键盘顶起时，固定高度会溢出：让抽屉自己可滚。
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const FitText('文件'),
                subtitle: const FitText('文本文档、代码、表格等'),
                onTap: () => Navigator.of(sheetContext).pop(_UploadChoice.file),
              ),
              if (canImage)
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const FitText('相册'),
                  subtitle: const FitText('选一张图给模型看'),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_UploadChoice.gallery),
                ),
              if (canCamera)
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const FitText('照相'),
                  subtitle: const FitText('拍一张马上用'),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_UploadChoice.camera),
                ),
              if (!canImage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.info_outline, size: 16, color: cs.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FitText(
                          '当前模型未开启图片支持，只能发文件（可在模型设置里打开）。',
                          style: TextStyle(fontSize: AppFontSize.caption, color: cs.outline),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _UploadChoice.file:
        await _runIntake(() => AttachmentIntake.instance.pickFiles(
              maxCount: widget.attachments.remainingSlots,
            ));
      case _UploadChoice.gallery:
        await _runIntake(() => AttachmentIntake.instance.pickGallery(
              maxCount: widget.attachments.remainingSlots,
            ));
      case _UploadChoice.camera:
        await _runIntakeCamera();
    }
  }

  Future<void> _runIntake(
    Future<List<AttachmentIntakeResult>> Function() task,
  ) async {
    try {
      final List<AttachmentIntakeResult> results = await task();
      _applyIntake(results);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, '选择文件失败：${describeError(e)}');
    }
  }

  Future<void> _runIntakeCamera() async {
    try {
      final AttachmentIntakeResult? one =
          await AttachmentIntake.instance.pickCamera();
      if (one == null) return;
      _applyIntake(<AttachmentIntakeResult>[one]);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, '拍照失败：${describeError(e)}');
    }
  }

  void _applyIntake(List<AttachmentIntakeResult> results) {
    if (!mounted) return;
    final List<String> errors = <String>[];
    int added = 0;
    for (final AttachmentIntakeResult r in results) {
      if (r.ok) {
        if (widget.attachments.add(r.attachment!)) {
          added++;
        }
      } else if (r.error != null) {
        errors.add(r.error!);
      }
    }
    if (errors.isNotEmpty) {
      showSnack(context, errors.first);
    } else if (added == 0 && results.isNotEmpty) {
      showSnack(context, '这些附件已经在列表里了');
    }
  }

  /// 输入区上方的附件条：每个附件一个胶囊，右侧 X 可移除。
  Widget _buildAttachmentStrip(ColorScheme cs) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: widget.attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final MessageAttachment a = widget.attachments.items[index];
          return Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.only(left: 10, right: 2),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  a.isImage
                      ? Icons.image_outlined
                      : (a.isText ? Icons.description_outlined : Icons.attach_file),
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: FitText(
                    a.name,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '移除附件',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  color: cs.onSurfaceVariant,
                  onPressed: () => widget.attachments.removeAt(index),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  /// 输入框右侧的动作区：括号 / 语音 / 灵感 / 发送（或停止）。
  ///
  /// [capsule] 只影响间距与发送键的形态：胶囊里发送键是实心圆钮，
  /// 旧样式里是与其它按钮同款的普通图标按钮（含发送图标）。
  Widget _buildTrailingActions(ColorScheme cs, {required bool capsule}) {
    final Widget gap = SizedBox(width: capsule ? 2 : 8);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 上传文件（设置里可关；发送中隐藏，避免和发送按钮抢位）
        if (widget.controller.settings.showUploadButton && !widget.sending) ...<Widget>[
          _buildUploadButton(cs),
          gap,
        ],
        // 添加括号按钮
        if (widget.controller.settings.showParenButton) ...<Widget>[
          _buildParenButton(cs),
          gap,
        ],
        // 生成中:整区恒定显示「停止生成」(不依赖 _hasInput——
        // 发送即清空输入,若按文字条件渲染会让停止按钮直接消失)。
        if (widget.sending) ...<Widget>[
          if (capsule)
            _buildSendOrStopButton(cs)
          else
            _buildClassicSendOrStopButton(cs),
          gap,
        ] else if (!_hasInput) ...<Widget>[
          // 语音输入按钮
          // 灵感按钮
          IconButton(
            tooltip: '灵感',
            color: cs.onSurfaceVariant,
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
        ] else ...<Widget>[
          // 发送按钮(动态高亮悬浮胶囊状态)
          if (capsule)
            _buildSendOrStopButton(cs)
          else
            _buildClassicSendOrStopButton(cs),
          gap,
        ],
      ],
    );
  }

  /// 旧样式的发送/停止键：与其它按钮同款的普通图标按钮。
  ///
  /// 生成中且可以停止时显示停止方块；生成中但上层没给停止回调时，
  /// 退回旧版本的「转圈且不可点」。
  Widget _buildClassicSendOrStopButton(ColorScheme cs) {
    final bool canStop = widget.sending && widget.onStopGeneration != null;
    if (widget.sending && !canStop) {
      return const IconButton(
        tooltip: '发送中...',
        onPressed: null,
        icon: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      tooltip: canStop ? '停止生成' : '发送',
      color: cs.onSurfaceVariant,
      onPressed: canStop
          ? () {
              _lastStopAt = DateTime.now();
              widget.onStopGeneration!();
            }
          : _sendSafe,
      icon: Icon(canStop ? Icons.stop_rounded : Icons.send),
    );
  }

  /// 发送/停止按钮:空闲=发送箭头;生成中=停止方块。
  ///
  /// 停止按钮在 [widget.sending] 为真时恒定显示(独立于输入是否有字);
  /// [ChatInputBar.onStopGeneration] 为空时退回旧行为(仅转圈、不可点)。
  ///
  /// 竞态说明:点停止后 `_sending` 会异步翻为 false,按钮随即重建为发送键;
  /// 若用户此刻仍在抬手,同一个手势的 up 事件会落在新的发送键上,把残留
  /// 文字误发出去。这里给停止后的发送加冷却,吞掉该同一手势的误触。
  Widget _buildSendOrStopButton(ColorScheme cs) {
    final bool canStop = widget.sending && widget.onStopGeneration != null;
    // 命中区按 [AppSize.touchTarget]（48dp）给：以前是 38×38 的自绘
    // Material+InkWell 圆钮，视觉尺寸当成了命中尺寸（审计 4.3）。
    // IconButton.filled 自带填充底、onPrimary 前景、水波纹、禁用态与焦点；
    // tooltip 兼作读屏标签（「发送」/「停止生成」）。
    return IconButton.filled(
      onPressed: canStop
          ? () {
              _lastStopAt = DateTime.now();
              widget.onStopGeneration!();
            }
          : (widget.sending ? null : _sendSafe),
      tooltip: canStop ? '停止生成' : '发送',
      style: IconButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        disabledBackgroundColor: cs.surfaceContainerHighest,
        disabledForegroundColor: cs.onSurfaceVariant,
        minimumSize: const Size(AppSize.touchTarget, AppSize.touchTarget),
        shape: const CircleBorder(),
      ),
      icon: widget.sending
          ? (canStop
              ? const Icon(Icons.stop_rounded, size: 22)
              : SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onSurfaceVariant,
                  ),
                ))
          : const Icon(Icons.arrow_upward_rounded, size: 20),
    );
  }

  /// 发送入口:若刚点过停止(同一手势内按钮被重建为发送键)则忽略本次,
  /// 避免误发残留文字;350ms 后正常发送。
  void _sendSafe() {
    final DateTime? t = _lastStopAt;
    if (t != null &&
        DateTime.now().difference(t) < const Duration(milliseconds: 350)) {
      return;
    }
    widget.onSend();
  }
}

/// 上传抽屉的三个选项。
enum _UploadChoice { file, gallery, camera }

/// 回车键（可选带 Shift）意图：用于在输入框里区分「发送」与「换行」。
class _EnterIntent extends Intent {
  const _EnterIntent({required this.shift});

  /// 是否按下了 Shift。
  final bool shift;
}
