import 'package:flutter/material.dart';

/// 按钮的基础样式形态。
enum AsyncButtonVariant { filled, tonal, outlined, text }

/// 异步操作按钮：点击后立即禁用并显示加载圆圈，等待 [onPressed] 完成后恢复。
///
/// 用于所有「点击后发起网络/异步请求」的按钮，避免用户在等待响应期间重复
/// 点击导致重复提交。组件内部自动管理 busy 状态（内置重入保护），无需外部
/// 维护 loading 布尔值。
class AsyncActionButton extends StatefulWidget {
  const AsyncActionButton({
    super.key,
    required this.onPressed,
    this.child,
    this.icon,
    this.variant = AsyncButtonVariant.tonal,
    this.style,
    this.loadingSize = 18,
    this.loadingStrokeWidth = 2,
    this.enabled = true,
    this.tooltip,
  }) : assert(child != null || icon != null,
            'child 与 icon 至少提供一个');

  /// 点击后执行的异步操作。await 期间按钮禁用并显示加载圆圈。
  final Future<void> Function() onPressed;

  /// 按钮文字/自定义内容。
  final Widget? child;

  /// 图标（与 [child] 并用时以 icon+label 形式展示）。
  final Widget? icon;

  /// 按钮样式：决定基础材质（filled/tonal/outlined/text）。
  final AsyncButtonVariant variant;

  /// 额外样式，会叠加到基础样式之上。
  final ButtonStyle? style;

  /// 加载圆圈直径。
  final double loadingSize;

  /// 加载圆圈描边粗细。
  final double loadingStrokeWidth;

  /// 是否可点击（额外的禁用条件，如未登录时）。
  final bool enabled;

  /// 语义提示。
  final String? tooltip;

  @override
  State<AsyncActionButton> createState() => _AsyncActionButtonState();
}

class _AsyncActionButtonState extends State<AsyncActionButton> {
  bool _busy = false;

  bool get _canPress => widget.enabled && !_busy;

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } catch (_) {
      // onPressed 内部通常自带异常处理；这里兜底吞掉，确保 busy 恢复、
      // 不产生未处理异常导致崩溃。
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _loading() {
    return SizedBox(
      width: widget.loadingSize,
      height: widget.loadingSize,
      child: CircularProgressIndicator(strokeWidth: widget.loadingStrokeWidth),
    );
  }

  ButtonStyle _baseStyle() {
    switch (widget.variant) {
      case AsyncButtonVariant.filled:
        return FilledButton.styleFrom();
      case AsyncButtonVariant.tonal:
        return FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
        );
      case AsyncButtonVariant.outlined:
        return OutlinedButton.styleFrom();
      case AsyncButtonVariant.text:
        return TextButton.styleFrom();
    }
  }

  /// busy 期间显示加载圆圈替代按钮内容。
  Widget _buildChild() {
    if (_busy) return _loading();
    final Widget? icon = widget.icon;
    final Widget? child = widget.child;
    final Widget? content;
    if (icon != null && child != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[icon, const SizedBox(width: 8), child],
      );
    } else {
      content = icon ?? child;
    }
    if (content == null) return const SizedBox.shrink();
    // 用 FittedBox 兜底：按钮内容在极窄空间（如宽屏左栏 288px 内 4 个按钮）
    // 也能等比缩放容纳，避免 RenderFlex 溢出。
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onPressed = _canPress ? _handleTap : null;
    final ButtonStyle style =
        widget.style == null ? _baseStyle() : _baseStyle().merge(widget.style!);

    final Widget button;
    switch (widget.variant) {
      case AsyncButtonVariant.filled:
      case AsyncButtonVariant.tonal:
        button = FilledButton(
          onPressed: onPressed,
          style: style,
          child: _buildChild(),
        );
      case AsyncButtonVariant.outlined:
        button = OutlinedButton(
          onPressed: onPressed,
          style: style,
          child: _buildChild(),
        );
      case AsyncButtonVariant.text:
        button = TextButton(
          onPressed: onPressed,
          style: style,
          child: _buildChild(),
        );
    }
    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}
