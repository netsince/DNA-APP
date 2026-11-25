import 'package:material_ui/material_ui.dart';

import 'package:dna/models/conversation.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

/// 「建议生成摘要」卡片：出现在 AI 回复足够长、提示可以压缩上下文时。
///
/// 从 `ChatMessageList` 的 itemBuilder 里抽出来的两个 kind 分支之一。抽出的意义：
/// itemBuilder 原本是个三百多行的闭包，三种 kind 的 UI 挤在一起；抽成 widget 后
/// 每种气泡可以单独看、单独改，itemBuilder 只剩派发。
class SummaryPromptBubble extends StatelessWidget {
  const SummaryPromptBubble({
    super.key,
    required this.message,
    required this.index,
    required this.summaryInProgress,
    required this.onStartSummary,
    required this.onDismissSummary,
    required this.onShowMessageMenu,
  });

  final ConversationMessage message;
  final int index;
  final bool summaryInProgress;
  final Future<void> Function(ConversationMessage message) onStartSummary;
  final Future<void> Function(String messageId) onDismissSummary;

  /// 长按 / 右键打开消息菜单（由列表统一提供，位置用全局坐标）。
  final void Function({
    required Offset position,
    required ConversationMessage message,
    required int index,
  }) onShowMessageMenu;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onLongPressStart: (LongPressStartDetails details) => onShowMessageMenu(
          position: details.globalPosition,
          message: message,
          index: index,
        ),
        onSecondaryTapDown: (TapDownDetails details) => onShowMessageMenu(
          position: details.globalPosition,
          message: message,
          index: index,
        ),
        child: SystemNoticeCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.auto_awesome, size: 18),
                  SizedBox(width: 4),
                  FitText('建议生成摘要'),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: summaryInProgress
                        ? null
                        : () => onStartSummary(message),
                    child: const FitText('生成摘要'),
                  ),
                  OutlinedButton(
                    onPressed: () => onDismissSummary(message.id),
                    child: const FitText('忽略'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「摘要已生成」卡片：点击/长按可以查看、编辑、删除。
class SummaryBubble extends StatelessWidget {
  const SummaryBubble({
    super.key,
    required this.message,
    required this.index,
    required this.summaryById,
    required this.onShowMessageMenu,
  });

  final ConversationMessage message;
  final int index;
  final ConversationSummary? Function(String? id) summaryById;
  final void Function({
    required Offset position,
    required ConversationMessage message,
    required int index,
  }) onShowMessageMenu;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final ConversationSummary? summary = summaryById(message.summaryId);
    final String raw = summary?.text.trim() ?? '';
    final String preview = raw.isEmpty
        ? '摘要为空'
        : (raw.length > 80 ? '${raw.substring(0, 80)}...' : raw);

    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onLongPressStart: (LongPressStartDetails details) => onShowMessageMenu(
          position: details.globalPosition,
          message: message,
          index: index,
        ),
        onSecondaryTapDown: (TapDownDetails details) => onShowMessageMenu(
          position: details.globalPosition,
          message: message,
          index: index,
        ),
        child: SystemNoticeCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.article_outlined, size: 18),
                  SizedBox(width: 4),
                  FitText('摘要已生成'),
                ],
              ),
              const SizedBox(height: 4),
              FitText(preview, style: textTheme.bodySmall),
              const SizedBox(height: 4),
              FitText(
                '长按/右键查看/删除',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(
                    alpha: AppAlpha.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 系统提示卡外壳（摘要提示 / 摘要正文共用）。
///
/// 两份卡片原本各写一遍同样的 padding / 圆角 / 描边 / 底色，改观感要改两处；
/// 内容（图标 + 文案 + 按钮）仍由调用方给。
class SystemNoticeCard extends StatelessWidget {
  const SystemNoticeCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      constraints: const BoxConstraints(maxWidth: AppSize.contentMaxWidth),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: AppAlpha.a85),
        borderRadius: AppRadius.smAll,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}
