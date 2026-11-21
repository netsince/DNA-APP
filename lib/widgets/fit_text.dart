import 'package:flutter/material.dart';

import '../theme/tokens.dart';

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
    this.minShrink = 0,
    this.wrapWhenTooNarrow = true,
  });

  /// 空间不足时是否允许「不缩字、改为换行」。
  ///
  /// 默认 true（大字号下优先保真）。**但在按固有宽度排版的容器里必须设为 false**
  /// （如 `SegmentedButton` 的段）：那种布局会在测量阶段向子节点要 intrinsic
  /// 宽度，而换行分支内部是 `LayoutBuilder` —— 一查 intrinsic 就抛断言。
  /// 这也是「换行不是万能解」的边界：定宽控件里只能缩字。
  final bool wrapWhenTooNarrow;

  /// 短文本「缩小保单行」的推荐下限（0.85 = 最多压到 85%，再窄改为换行）。
  ///
  /// **只是推荐值，不是默认值。** 默认保持 0（无条件缩到装下为止）——
  /// 这是 2026-10-29 `cb3a0da` 定下的口径：短标签缩字是「字号全局生效」
  /// 之外被明确保留的例外，要换行的位置逐个调用点自己传。
  /// 详见 docs/REGRESSION_AUDIT.md §4。
  static const double recommendedMinShrink = 0.85;

  /// 所在容器的背景颜色。若提供，将自动根据其混合亮度计算最佳对比度文本颜色。
  final Color? contrastBackground;

  /// 短文本「缩小保单行」的下限（0 = 不设下限，永远缩到装下为止）。
  ///
  /// `FitText` 对 6 字以内的文本会套 FittedBox 强制单行；空间不足时会**缩小**，
  /// 于是字号调大后，窄容器里的短标签「长到装不下就不再长」——用户会把系统
  /// 字号调到最大，界面却纹丝不动。
  ///
  /// 默认 [defaultMinShrink]（0.85）：缩放比低于该值就不再压字，改为正常换行。
  /// 显式传 `0` 恢复旧行为（无条件缩到装下为止）。
  final double minShrink;

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
    if (inkFor(bgColor, cs.surface) == AppColors.inkOnLight) {
      // 浅色/高亮背景上必须用深色墨字(即使当前是深色主题),
      // 否则会出现「白字配白底」看不清的问题。
      return darkColor ?? AppColors.inkOnLight;
    }
    // 深色背景上必须用浅色墨字(即使当前是浅色主题):
    // 取色可能给出很深的颜色,浅色主题的 onSurface 是深色字,
    // 落在深色气泡上同样看不清。
    return lightColor ?? AppColors.inkOnDark;
  }

  /// 背景上的前景墨色:在深浅两种墨里挑**对比度更高**的那个。
  ///
  /// 刻意不用固定的明暗阈值。气泡是半透明的:50% 白叠在深色页面上
  /// 得到的是中灰(亮度约 0.25),按"亮度 > 0.42 才算亮底"会判成深色
  /// 底、给出浅色字,对比度只有 2.7;按对比度取优会选深色字(4.8)。
  ///
  /// [background] 允许半透明(气泡会透出后面的背景),此时先与
  /// [surfaceColor] 合成再比较。供 `RichText` 这类不能用 [FitText]
  /// 包裹的场景复用。
  static Color inkFor(Color background, [Color? surfaceColor]) {
    final Color effective = surfaceColor != null
        ? compositeOver(background, surfaceColor)
        : background;
    final Color picked = _betterInk(effective);
    // 阈值取 7:1（WCAG AAA）而不是 4.5：
    // 近黑气泡 @50% 叠浅色页面会合成中灰，深墨在中灰上正好 4.6 —— 刚过 AA，
    // 于是还会选深墨，观感就是"黑气泡上仍然是黑字"。只有对比足够高才信任
    // 合成色，否则按气泡本身判断。
    if (_contrastRatio(picked, effective) >= 7.0) {
      return picked;
    }
    // 半透明气泡叠在页面底色上可能刚好落在"两头都不够"的中灰区间
    // （例：莫奈取色给出近黑的气泡 @50% 叠在浅色页面上），此时按合成色
    // 选墨只会得到勉强合格、观感却像"黑底黑字"的结果。
    // 这时退化为按**气泡本身的颜色**判断：黑气泡就给浅色字。
    return _betterInk(background);
  }

  /// 在两种墨色里挑对比度更高的那个。
  static Color _betterInk(Color background) {
    final double withLightInk = _contrastRatio(AppColors.inkOnLight, background);
    final double withDarkInk = _contrastRatio(AppColors.inkOnDark, background);
    return withLightInk >= withDarkInk
        ? AppColors.inkOnLight
        : AppColors.inkOnDark;
  }

  /// WCAG 相对对比度(仅用于挑选前景墨色)。
  static double _contrastRatio(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    final double hi = la > lb ? la : lb;
    final double lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  @override
  Widget build(BuildContext context) {
    TextStyle? effectiveStyle = style;
    if (contrastBackground != null) {
      final Color autoColor = contrastColor(contrastBackground!, context);
      effectiveStyle = (effectiveStyle ?? DefaultTextStyle.of(context).style)
          .copyWith(color: autoColor);
    }

    final String? text = data;
    final bool isShort =
        text != null && text.characters.length < _shortThreshold;
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

    // 缩放下限**只由调用点显式决定**，不跟字号倍率联动。
    //
    // 这里曾经被改成「字号倍率 > 1 时自动启用下限」，那是一处越界改动：
    // 作者在 2026-10-29（提交 cb3a0da「字号真正全局生效」）已经处理过
    // 「字号没生效」这个真问题（封掉 RichText/TextPainter 的逃逸口、改成
    // 系统×应用组合），并把短标签缩字作为**明确保留的例外**——
    // minShrink 默认 0，注释原话是「需要的地方再逐个开」。
    //
    // 所以：默认 0 = 缩到装下为止（既有行为）；要换行就在那一处显式传
    // minShrink（推荐 FitText.recommendedMinShrink）。
    // wrapWhenTooNarrow 只服务于「显式传了 minShrink、但容器按固有宽度排版」
    // 的场景（例如 SegmentedButton 的段：那里查 intrinsic，不能用 LayoutBuilder）。
    final double cap = wrapWhenTooNarrow ? minShrink : 0;

    if (isShort && canWrap) {
      if (cap <= 0) {
        //默认路径：与历史行为完全一致（无条件缩到装下为止）。
        result = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: _alignmentFor(textAlign),
          child: result,
        );
      } else {
        final Widget plain = result;
        result = LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double available = constraints.maxWidth;
            final double intrinsic = _intrinsicWidth(context, effectiveStyle);
            if (available.isFinite && intrinsic > 0) {
              final double ratio = available / intrinsic;
              if (ratio < cap) {
                //缩得太狠：保持原字号、允许换行。
                return plain;
              }
            }
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: _alignmentFor(textAlign),
              child: plain,
            );
          },
        );
      }
    }
    return result;
  }

  ///量出这段文字在当前样式 /当前字号倍率下的**单行**宽度。
  ///
  ///只用于测量，不参与绘制（绘制仍旧走 Text）——这是本文件被允许使用
  /// TextPainter的唯一理由，见 test/text_scaling_guard_test.dart。
  double _intrinsicWidth(BuildContext context, TextStyle? effectiveStyle) {
    final TextStyle baseStyle =
        (effectiveStyle ?? DefaultTextStyle.of(context).style).copyWith();
    final TextPainter painter = TextPainter(
      text: TextSpan(text: data ?? '', style: baseStyle),
      textDirection:
          textDirection ?? Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler:
          textScaler ??
          MediaQuery.maybeTextScalerOf(context) ??
          TextScaler.noScaling,
      maxLines: 1,
      locale: locale,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
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
