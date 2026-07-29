import 'package:flutter/material.dart';
import 'package:dna/widgets/fit_text.dart';

/// 将 colorScheme.primary 系列替换为指定强调色（用于让弹框跟随角色取色）。
ThemeData _withAccent(ThemeData base, Color? accentColor) {
  if (accentColor == null) {
    return base;
  }
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: accentColor,
      onPrimary: ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
          ? Colors.white
          : Colors.black,
      primaryContainer:
          Color.alphaBlend(accentColor.withValues(alpha: 0.16), base.colorScheme.surface),
      onPrimaryContainer: accentColor,
    ),
  );
}

Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  String cancelText = '取消',
  String confirmText = '确认',
  Color? accentColor,
}) async {
  final ThemeData baseTheme = Theme.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return Theme(
        data: _withAccent(baseTheme, accentColor),
        child: AlertDialog(
          title: FitText(title),
          content: FitText(content),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: FitText(cancelText),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: FitText(confirmText),
            ),
          ],
        ),
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
  Color? accentColor,
}) async {
  final ThemeData baseTheme = Theme.of(context);
  final String? value = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return Theme(
        data: _withAccent(baseTheme, accentColor),
        child: _TextInputDialog(
          title: title,
          hintText: hintText,
          initialValue: initialValue,
          cancelText: cancelText,
          confirmText: confirmText,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: keyboardType,
        ),
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
      title: FitText(widget.title),
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
          child: FitText(widget.cancelText),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: FitText(widget.confirmText),
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
  Color? accentColor,
}) async {
  final ThemeData baseTheme = Theme.of(context);
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return Theme(
        data: _withAccent(baseTheme, accentColor),
        child: AlertDialog(
          title: FitText(title),
          content: content,
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: FitText(closeText),
            ),
          ],
        ),
      );
    },
  );
}
