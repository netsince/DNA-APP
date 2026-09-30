import 'dart:convert';

import 'package:flutter/material.dart';
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
    } else if (a.startsWith('data:')) {
      final comma = a.indexOf(',');
      final b64 = comma >= 0 ? a.substring(comma + 1) : a;
      try {
        final bytes = base64Decode(b64);
        child = Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      } catch (_) {
        child = Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant);
      }
    } else {
      child = Image.network(
        ServerConfig.resolveUrl(a),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            Icon(Icons.person, size: radius, color: scheme.onSurfaceVariant),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.surfaceContainerHighest,
      child: ClipOval(child: child),
    );
  }
}
