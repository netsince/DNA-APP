import 'package:flutter/material.dart';

/// 文本短于 6 个字时，若因空间不足需要换行，则通过缩小字号保持在单行；
/// 6 字及以上保持原生 [Text] 行为（正常换行）。
///
/// 具备「背景明暗自动感知」能力：
/// 当提供 [contrastBackground]（例如半透明气泡色、强调色、卡片背景）时，
/// 自动合成当前主题底色并计算感知亮度，在浅色背景上自动选用深色文字、在深色背景上选用浅色文字，
/// 彻底杜绝深色模式下浅色气泡配白色文字看不清的问题。
class FitText extends Text {
  const FitText(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
    this.contrastBackground,
  });

  /// 所在容器的背景颜色。若提供，将自动根据其混合亮度计算最佳对比度文本颜色。
  final Color? contrastBackground;

  static const int _shortThreshold = 6;

  /// 计算前景色叠加到底色后的感知混合颜色（支持半透明 Alpha 混合）。
  static Color compositeOver(Color foreground, Color background) {
    final double a = foreground.a;
    if (a >= 1.0) return foreground;
    if (a <= 0.0) return background;
    return Color.from(
      alpha: 1.0,
      red: foreground.r * a + background.r * (1.0 - a),
      green: foreground.g * a + background.g * (1.0 - a),
      blue: foreground.b * a + background.b * (1.0 - a),
    );
  }

  /// 判断给定背景色（经 surface 叠加后）是否属于浅色/亮色背景。
  static bool isLightBackground(Color bgColor, [Color? surfaceColor]) {
    final Color effective = surfaceColor != null
        ? compositeOver(bgColor, surfaceColor)
        : bgColor;
    return effective.computeLuminance() > 0.42;
  }

  /// 依据背景色动态计算高对比度文本颜色。
  static Color contrastColor(
    Color bgColor,
    BuildContext context, {
    Color? darkColor,
    Color? lightColor,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool isLight = isLightBackground(bgColor, cs.surface);
    if (isLight) {
      return darkColor ?? const Color(0xFF1D1B20);
    } else {
      return lightColor ?? cs.onSurface;
    }
  }

  @override
  Widget build(BuildContext context) {
    TextStyle? effectiveStyle = style;
    if (contrastBackground != null) {
      final Color autoColor = contrastColor(contrastBackground!, context);
      effectiveStyle = (effectiveStyle ?? DefaultTextStyle.of(context).style).copyWith(
        color: autoColor,
      );
    }

    final String? text = data;
    final bool isShort = text != null && text.characters.length < _shortThreshold;
    final bool canWrap = softWrap ?? true;

    Widget result = Text(
      data ?? '',
      style: effectiveStyle,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );

    if (isShort && canWrap) {
      // 空间不足时会换行，则缩小字号确保单行显示。
      result = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: _alignmentFor(textAlign),
        child: result,
      );
    }
    return result;
  }

  static Alignment _alignmentFor(TextAlign? align) {
    switch (align) {
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.left:
      case TextAlign.start:
      case TextAlign.justify:
      case null:
        return Alignment.centerLeft;
    }
  }
}
