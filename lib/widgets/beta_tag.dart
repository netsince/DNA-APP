import 'package:flutter/material.dart';

import 'fit_text.dart';

/// 「测试版」标签，标记尚处于测试阶段的功能入口标题。
class BetaTag extends StatelessWidget {
  const BetaTag({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: FitText(
        '测试版',
        style: theme.textTheme.labelSmall?.copyWith(
          color: cs.onTertiaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
