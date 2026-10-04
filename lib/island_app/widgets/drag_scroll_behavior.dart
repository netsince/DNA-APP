import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 允许**鼠标拖拽**滚动的 [ScrollBehavior]。
///
/// Flutter 在桌面平台默认把鼠标排除在 `dragDevices` 之外（桌面惯例是滚轮滚动、
/// 拖拽选字），于是所有"靠拖"的界面在电脑版上都是死的：社区的「刷一刷」就是
/// 这样 —— 手机上左右滑动翻卡，电脑上按住鼠标拖毫无反应（用户反馈"电脑版
/// 刷一刷坏了"）。
///
/// 只用在**必须靠拖**的界面里（岛的刷一刷、图片预览画廊、横向筛选条），
/// 不去动主项目全局的滚动行为。
class DragScrollBehavior extends MaterialScrollBehavior {
  const DragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      };
}
