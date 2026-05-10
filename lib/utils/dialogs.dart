import 'package:flutter/material.dart';

Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  String cancelText = '取消',
  String confirmText = '确认',
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

Future<String?> showTextInputDialog({
  required BuildContext context,
  required String title,
  required String hintText,
  String? initialValue,
  String cancelText = '取消',
  String confirmText = '保存',
  int minLines = 1,
  int maxLines = 1,
  TextInputType? keyboardType,
}) async {
  final String? value = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return _TextInputDialog(
        title: title,
        hintText: hintText,
        initialValue: initialValue,
        cancelText: cancelText,
        confirmText: confirmText,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
      );
    },
  );
  return value;
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.hintText,
    this.initialValue,
    required this.cancelText,
    required this.confirmText,
    required this.minLines,
    required this.maxLines,
    this.keyboardType,
  });

  final String title;
  final String hintText;
  final String? initialValue;
  final String cancelText;
  final String confirmText;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(hintText: widget.hintText),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelText),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

Future<void> showInfoDialog({
  required BuildContext context,
  required String title,
  required Widget content,
  String closeText = '关闭',
}) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: content,
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(closeText),
          ),
        ],
      );
    },
  );
}
