import 'package:flutter/material.dart';

/// 底部提示（SnackBar）的默认显示时长，由设置项统一控制。
Duration _globalSnackDuration = const Duration(milliseconds: 1000);

/// 更新全局底部提示的默认显示时长，供设置项统一控制。
void setSnackDuration(Duration duration) {
  _globalSnackDuration = duration;
}

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
      duration: duration ?? _globalSnackDuration,
      behavior: behavior,
    ),
  );
}
