import 'package:flutter/material.dart';

void showSnack(
  BuildContext context,
  String message, {
  Duration? duration,
  SnackBarBehavior? behavior,
}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration ?? const Duration(seconds: 4),
      behavior: behavior,
    ),
  );
}
