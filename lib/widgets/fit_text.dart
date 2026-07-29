import 'package:flutter/material.dart';

/// 文本短于 6 个字时，若因空间不足需要换行，则通过缩小字号保持在单行；
/// 6 字及以上保持原生 [Text] 行为（正常换行）。
///
/// 通过继承 [Text] 并仅重写 [build] 实现，对调用处完全透明：
/// 所有 `Text(...)` 替换为 `FitText(...)` 后即可全局生效，长文本行为不变。
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
  });

  static const int _shortThreshold = 6;

  @override
  Widget build(BuildContext context) {
    final String? text = data;
    final bool isShort = text != null && text.characters.length < _shortThreshold;
    final bool canWrap = softWrap ?? true;
    if (isShort && canWrap) {
      // 空间不足时会换行，则缩小字号确保单行显示。
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: _alignmentFor(textAlign),
        child: super.build(context),
      );
    }
    return super.build(context);
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
