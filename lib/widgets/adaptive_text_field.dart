import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 自适应高度的多行输入框：根据内容行数自动调整行数，避免长文本出现内部滚动条。
class AdaptiveTextField extends StatefulWidget {
  const AdaptiveTextField({
    super.key,
    required this.controller,
    this.decoration,
    this.minLines,
    this.maxLines,
    this.onChanged,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final int? minLines;
  final int? maxLines;
  final ValueChanged<String>? onChanged;

  @override
  State<AdaptiveTextField> createState() => _AdaptiveTextFieldState();
}

class _AdaptiveTextFieldState extends State<AdaptiveTextField> {
  late int _lineCount;

  @override
  void initState() {
    super.initState();
    _lineCount = _calculateLineCount(widget.controller.text);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final int newLineCount = _calculateLineCount(widget.controller.text);
    if (newLineCount != _lineCount) {
      setState(() => _lineCount = newLineCount);
    }
  }

  int _calculateLineCount(String text) {
    final int baseMin = widget.minLines ?? 1;
    if (text.isEmpty) return baseMin;
    final int count = text.split('\n').length;
    int resolved = math.max(baseMin, count);
    if (widget.maxLines != null) {
      resolved = math.min(widget.maxLines!, resolved);
    }
    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    final int baseMin = widget.minLines ?? 1;
    return TextField(
      controller: widget.controller,
      minLines: baseMin,
      maxLines: widget.maxLines ?? math.max(baseMin, _lineCount),
      decoration: widget.decoration,
      onChanged: widget.onChanged,
    );
  }
}
