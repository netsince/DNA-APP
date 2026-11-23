import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/fit_text.dart';
import 'splash_animations.dart';
import '../splash_page.dart';

/// 预览开场动画：在设置里当场把选中的那段动画播一遍。
///
/// 存在的理由：开场动画只在冷启动出现一次，改完设置要卸载重开才能看到效果——
/// 用户没法「试一下再决定」。这里给一个可重播的小舞台，选完立刻看。
Future<void> showSplashPreviewDialog(
  BuildContext context, {
  required String animationId,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) =>
        SplashPreviewDialog(animationId: animationId),
  );
}

class SplashPreviewDialog extends StatefulWidget {
  const SplashPreviewDialog({super.key, required this.animationId});

  final String animationId;

  @override
  State<SplashPreviewDialog> createState() => _SplashPreviewDialogState();
}

class _SplashPreviewDialogState extends State<SplashPreviewDialog> {
  /// 每次「再播一次」自增，让舞台整体重建。
  int _run = 0;

  /// 这一段是否已经播完（播完才允许再播一次，避免重复点击叠动画）。
  bool _done = false;

  SplashAnimationSpec get _animation => splashAnimationById(widget.animationId);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final SplashAnimationSpec animation = _animation;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FitText(
                      '开场动画预览',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: AppWeight.medium,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (animation.enabled)
              SizedBox(
                height: 300,
                child: SplashStage(
                  key: ValueKey<String>('${animation.id}-$_run'),
                  animation: animation,
                  onComplete: () {
                    if (mounted) setState(() => _done = true);
                  },
                ),
              )
            else
              Container(
                height: 120,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FitText(
                  '当前选的是「关闭动画」，启动时不会播放任何动画。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FitText(
                      animation.enabled
                          ? '${animation.label} · ${(animation.durationMs / 1000).toStringAsFixed(1)} 秒'
                          : animation.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (animation.enabled)
                    TextButton.icon(
                      key: const ValueKey<String>('splash-preview-replay'),
                      onPressed: _done
                          ? () => setState(() {
                                _done = false;
                                _run++;
                              })
                          : null,
                      icon: const Icon(Icons.replay, size: 18),
                      label: const FitText('再播一次'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const FitText('完成'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
