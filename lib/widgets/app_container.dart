import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

/// 容器变换跳转:点击处的小容器平滑放大为整页,返回时缩回原位。
///
/// ## 用在哪
///
/// **「卡片/按钮 → 它的详情或编辑页」**这种存在明确"源容器"的跳转:
/// 角色卡 → 角色编辑、服务商卡 → 服务商编辑、聊天入口卡 → 聊天页。
///
/// **不要用在没有源容器的层级浏览**(如设置 → 子设置页):
/// 那种场景应继续使用 [MaterialPageRoute] 走平台原生转场。
///
/// ## 为什么统一走这个封装
///
/// * 时长 / 曲线 / 颜色从 [AppMotion] 与当前主题取,全应用一致;
/// * 默认 `closedColor = openColor = surface`,飞行中不闪色;
/// * 泛型默认 `bool`,约定回传「页面内是否发生了修改」,
///   列表页据此决定是否刷新(与既有 `push().then()` 习惯对齐)。
///
/// ## 性能说明
///
/// 飞行动画期间 `openBuilder` 只构建一个色块过渡态,
/// 目标页在动画完成后才真正 build —— 目标页再重也不会拖慢动画
/// (源码 `animations-2.2.0` 行 810-823)。
class AppContainer<T extends Object?> extends StatelessWidget {
  const AppContainer({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.closedShape,
    this.duration,
    this.tappable = true,
    this.onClosed,
  });

  /// 关闭态:列表里的卡片 / 按钮(原样搬入,不再包 InkWell)。
  ///
  /// 注意:点击行为由容器接管,**不要**在这里再套一层
  /// InkWell/GestureDetector,否则水波纹与飞行动画会打架。
  final Widget Function(BuildContext context, VoidCallback open) closedBuilder;

  /// 打开态:全屏目标页。`action` 即"关闭并缩回原位"。
  ///
  /// 签名沿用 [OpenContainer] 的 `CloseContainerActionCallback<T>`:
  /// `action({T? returnValue})`——可无参关闭,也可回传结果
  /// (由 [onClosed] 接收)。调用方把参数标注为 `VoidCallback` 也兼容
  /// (函数子类型),只在需要回传时标注完整类型。
  final Widget Function(
    BuildContext context,
    CloseContainerActionCallback<T> close,
  ) openBuilder;

  /// 关闭态形状(与卡片圆角一致,飞行中圆角从它插值到 0)。
  final ShapeBorder? closedShape;

  /// 覆盖默认时长(一般不用传)。
  final Duration? duration;

  /// false = 容器不自动接管点击,由 closedBuilder 里的控件自行调 `open`。
  ///
  /// 用于点击前需要校验(目标可能已被删除等)的场景:
  /// 传入 `tappable: false`,在 closedBuilder 拿到 `open` 回调,
  /// 校验通过后再调它起飞。
  final bool tappable;

  /// 容器关闭(缩回原位)时回传的结果,透传给 [OpenContainer.onClosed]。
  final void Function(T? result)? onClosed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    // OpenContainer 不读全局 cardTheme:封闭态的形状/底色手动对齐,
    // 保证它替换 Card 后,静止外观与改造前逐像素一致。
    final CardThemeData card = theme.cardTheme;
    return OpenContainer<T>(
      transitionDuration: duration ?? AppMotion.transform,
      transitionType: ContainerTransitionType.fade,
      // 封闭态底色对齐 Card 默认(M3 = surfaceContainerLow),
      // 飞行中途过渡到页面背景 surface,不闪白。
      closedColor: card.color ?? cs.surfaceContainerLow,
      middleColor: cs.surface,
      openColor: cs.surface,
      closedElevation: card.elevation ?? 0,
      openElevation: 0,
      closedShape:
          closedShape ??
          card.shape ??
          RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      closedBuilder: closedBuilder,
      openBuilder: openBuilder,
      tappable: tappable,
      onClosed: onClosed,
    );
  }
}
