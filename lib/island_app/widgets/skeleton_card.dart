import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

/// 骨架卡片：3:4 封面块 + 两行文字条，用于加载中的占位。
///
/// 原本 `explore_body` 与 `home_body` 各写一份（逐行相同，连注释都一样）。
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final Color block = Theme.of(context).colorScheme.surfaceContainerHighest;
    final BorderRadius radius = BorderRadius.circular(AppRadius.sm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            decoration: BoxDecoration(color: block, borderRadius: radius),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 96,
          height: 14,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: 12,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
      ],
    );
  }
}
