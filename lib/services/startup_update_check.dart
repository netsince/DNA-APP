import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/settings/update_dialog.dart';
import '../state/app_controller.dart';
import '../utils/ui_feedback.dart';
import 'update_service.dart';

/// 启动时的更新检查。
///
/// ## 行为
///
/// * **有更新** → 弹更新窗口(版本号 / 发布时间 / 更新日志 + 前往更新、忽略);
/// * **已是最新** → 什么都不做(不打扰);
/// * **检查失败** → 底部一条轻提示:「获取更新失败,可能不是最新版。」
///
/// 失败提示是用户明确要求的 —— 静默失败会让用户以为"没更新",
/// 而实际上可能只是网络不通,属于误导。
///
/// 检查在**首帧渲染之后**才发起,不阻塞启动;且整体不抛异常
/// (任何意外都吞掉,绝不能因为更新检查拖垮启动)。
class StartupUpdateCheck {
  const StartupUpdateCheck._();

  /// 在启动流程里调用。不 await 网络,立即返回。
  static void schedule(
    BuildContext context,
    AppController controller,
  ) {
    if (!controller.settings.updateCheckEnabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 不 await:让调用方立刻继续。
      scheduleMicrotask(() => _run(context, controller));
    });
  }

  static Future<void> _run(
    BuildContext context,
    AppController controller,
  ) async {
    try {
      final UpdateCheckResult result = await UpdateService().check();
      if (!context.mounted) return;

      switch (result) {
        case UpdateAvailable(:final UpdateInfo info):
          await showUpdateDialog(context, info);
        case UpdateUpToDate():
          break; // 已是最新 —— 不打扰
        case UpdateCheckFailed(:final UpdateCheckError error):
          // 读不到本地版本是应用自身的问题,用户无法解决 —— 静默,
          // 否则每次启动都弹一条无意义的错误。
          if (error == UpdateCheckError.localVersionUnavailable) break;
          showSnack(context, '获取更新失败，可能不是最新版。');
      }
    } catch (_) {
      // 启动路径上的任何异常都不允许冒泡。
    }
  }
}
