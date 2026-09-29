import 'package:flutter/material.dart';

import 'package:dna/models/ta.dart';
import 'package:dna/services/image_storage.dart';
import 'package:dna/widgets/fit_text.dart';

/// 角色 1:1 头像:**有立绘用立绘,没有就用名字首字**。
///
/// 此前「有图用图、无图用首字」这段逻辑散落在各页手写(会话列表、
/// 我家…),首字取法还不一致(`name[0]` 会把代理对拆坏)。这里收成
/// 一处,侧栏、列表都可以直接用。
class TaAvatar extends StatelessWidget {
  const TaAvatar({
    super.key,
    required this.ta,
    this.size = 44,
    this.borderRadius = 8,
  });

  /// 角色;传 null(角色已被删除)时走首字兜底并显示 `?`。
  final TA? ta;

  /// 边长(正方形)。
  final double size;

  /// 圆角。
  final double borderRadius;

  /// 名字首字;名字为空时给 `?`。
  ///
  /// 用 `characters` 取首字:直接 `name[0]` 遇到 emoji / 罕用汉字
  /// (代理对)会截出半个字符变成乱码。
  static String initialOf(String? name) {
    final String trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed.characters.first;
  }

  @override
  Widget build(BuildContext context) {
    final TA? ta = this.ta;
    final ImageProvider? provider = ta == null
        ? null
        : ImageStorage.instance.providerFor(ta, 'square');

    if (provider != null) {
      final int pixels = (size * 2).round();
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image(
          image: ResizeImage.resizeIfNeeded(pixels, pixels, provider),
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: FitText(
        initialOf(ta?.name),
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w500,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
