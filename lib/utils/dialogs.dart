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
  final TextEditingController controller =
      TextEditingController(text: initialValue ?? '');
  final String? value = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: hintText),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (value == null) {
    return null;
  }
  return value.trim();
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
