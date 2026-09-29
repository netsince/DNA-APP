import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

/// 编辑器页面的桌面布局:把表单收进一条**可读宽度的内容列**。
///
/// ## 为什么要收
///
/// 编辑器正文原来是通栏 [ListView](左右各 16):在 1600 宽的桌面上,
/// 每个输入框会被拉到 1500 多像素 —— 标签贴最左、输入内容在中间、
/// 右边一大片空,眼睛要横扫整屏才能读完一行,于是既空又"满"。
/// 这里按窗口宽度自动加左右留白,把内容收进 [AppSize.editorMaxWidth]
/// 的列里;窄窗口算出来不足一个常规边距,就回落成普通边距(手机端
/// 外观不变)。
///
/// ## 为什么用"留白"而不是包一层 Center + ConstrainedBox
///
/// 编辑器正文常常是几百行的 `ListView` 表达式,包一层要动开头与
/// 结尾两处括号,改留白只需动一行;对滚动视图两者视觉等价
/// (内容列宽度 = 窗口宽 - 两侧留白)。
abstract final class AppEditorLayout {
  AppEditorLayout._();

  /// 内容列左右留白(窄窗口回落到 [AppSpacing.lg])。
  static double sideInset(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final double inset = (width - AppSize.editorMaxWidth) / 2;
    return inset > AppSpacing.lg ? inset : AppSpacing.lg;
  }

  /// 正文内边距:左右按内容列留白;上下留出呼吸空间,
  /// 底部额外让位给悬浮保存按钮(否则滚到底时最后一张卡片
  /// 会被按钮压住)。
  static EdgeInsets bodyPadding(
    BuildContext context, {
    double top = AppSpacing.lg,
    double bottom = 88,
  }) {
    final double side = sideInset(context);
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }

  /// 悬浮按钮要让出的右侧留白:让按钮右缘贴内容列右缘,
  /// 而不是飘在离表单几百像素的窗口角落。
  static double fabInset(BuildContext context) =>
      sideInset(context) - AppSpacing.lg;
}

/// 编辑器的保存按钮(悬浮):对齐内容列右缘。
///
/// 参数与 [FloatingActionButton.extended] 一致,便于各编辑器直接
/// 替换构造名;宽度收窄后按钮不会脱离表单。
class AppEditorFab extends StatelessWidget {
  const AppEditorFab({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final Widget label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: AppEditorLayout.fabInset(context)),
      child: FloatingActionButton.extended(
        onPressed: onPressed,
        icon: icon,
        label: label,
      ),
    );
  }
}
