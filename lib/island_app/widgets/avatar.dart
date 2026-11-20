
import 'package:flutter/material.dart';

import '../../widgets/memo_image.dart';
import 'package:dna/island_app/server_config.dart';

/// 头像渲染：空 -> 人形图标；data URL -> Image.memory；其余按网络图（经 resolveUrl）。
///
/// 与 `me_page` 中原有的 `_Avatar` 行为一致，抽为共享组件供评论区等复用。
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.avatar, this.radius = 20});

  final String avatar;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget child;
    final a = avatar;
    if (a.isEmpty) {
      child = Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant);
    } else {
      // 按显示尺寸解码：头像最大也就 40~80px，没必要把 1080p 的图解进来。
      final int target = (radius * 2 * MediaQuery.devicePixelRatioOf(context))
          .clamp(32, 256)
          .round();
      final ImageProvider? provider = a.startsWith('data:')
          ? MemoImage.dataUrl(a, cacheWidth: target)
          : MemoImage.network(ServerConfig.resolveUrl(a), cacheWidth: target);
      if (provider == null) {
        child = Icon(
          Icons.person,
          size: radius,
          color: scheme.onSurfaceVariant,
        );
      } else {
        child = Image(
          image: provider,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) =>
              Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant),
        );
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.surfaceContainerHighest,
      child: ClipOval(child: child),
    );
  }
}
