import 'package:flutter/material.dart';

/// 自适应高度的多行输入框：根据内容行数自动调整行数，避免长文本出现内部滚动条。
class AdaptiveTextField extends StatefulWidget {
  const AdaptiveTextField({super.key, required this.controller, this.decoration});

  final TextEditingController controller;
  final InputDecoration? decoration;

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
    if (text.isEmpty) return 1;
    final int count = text.split('\n').length;
    return count < 1 ? 1 : count;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      minLines: _lineCount,
      maxLines: _lineCount,
      decoration: widget.decoration,
    );
  }
}
