import 'package:flutter/material.dart';

import 'package:dna/island_app/auth_session.dart';

/// 统一「登录守卫」：对齐网页版未登录交互（需登录的操作带跳登录引导），
/// 替代各页面散落的 `if (!loggedIn) snack('请先登录…')`。
class AuthGuard {
  AuthGuard._();

  static bool get isLoggedIn => AuthSession.instance.isLoggedIn;

  /// 需要登录的操作守卫。
  ///
  /// 已登录则执行 [action] 并返回 true；未登录则弹出带「去登录」的提示，
  /// 点击后回到外壳并切到「我」页登录，返回 false。
  static Future<bool> run(
    BuildContext context,
    Future<void> Function() action, {
    String message = '请先登录',
  }) async {
    if (isLoggedIn) {
      await action();
      return true;
    }
    _prompt(context, message);
    return false;
  }

  /// 直接弹出登录引导（用于纯展示/无操作可执行的场景）。
  static void require(BuildContext context, {String message = '请先登录'}) {
    if (isLoggedIn) return;
    _prompt(context, message);
  }

  static void _prompt(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '去登录',
            onPressed: () => goToLogin(context),
          ),
        ),
      );
  }

  /// 回到外壳根路由并请求切到「我」页登录。
  static void goToLogin(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    AuthSession.instance.loginRequest.value++;
  }
}
