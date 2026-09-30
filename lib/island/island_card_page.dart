import 'package:flutter/material.dart';

import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import 'island_api.dart';
import 'island_bridge.dart';
import 'island_card.dart';
import 'island_session.dart';
import 'island_trial_chat_page.dart';
import 'trial_chat.dart';

/// 岛上的角色卡详情页。
///
/// 与主项目的角色展示页长得像（本来就是同一套字段），但动作不同：
/// 这里的重点是**试聊**与**导入到我家** —— 先聊两句再决定要不要收下。
class IslandCardPage extends StatefulWidget {
  const IslandCardPage({
    super.key,
    required this.controller,
    required this.card,
    this.api,
    this.completer,
  });

  final AppController controller;
  final IslandCard card;
  final IslandApi? api;

  /// 透传给试聊页（测试注入模型调用）。
  final Future<String> Function(List<Map<String, String>> messages)? completer;

  @override
  State<IslandCardPage> createState() => _IslandCardPageState();
}

class _IslandCardPageState extends State<IslandCardPage> {
  bool _importing = false;
  String? _error;

  /// 有没有聊到一半的试聊。
  TrialChat? _trial;

  @override
  void initState() {
    super.initState();
    _loadTrial();
  }

  Future<void> _loadTrial() async {
    final TrialChat? trial = await TrialChatStore.load(widget.card.id);
    if (mounted) {
      setState(() => _trial = trial);
    }
  }

  Future<void> _openTrial() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => IslandTrialChatPage(
          controller: widget.controller,
          card: widget.card,
          api: widget.api,
          completer: widget.completer,
        ),
      ),
    );
    // 回来时可能已经导入、也可能只是聊了几句，重新读一次本地记录。
    await _loadTrial();
  }

  /// 「导入到我家」：不试聊，直接把卡片收下。
  Future<void> _import() async {
    if (_importing) {
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    final IslandApi api = widget.api ?? IslandApi();
    try {
      final TA ta = await IslandBridge.importCard(
        controller: widget.controller,
        api: api,
        card: widget.card,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: FitText('已导入「${ta.name}」到我家')));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = '导入失败：$e');
      }
    } finally {
      if (widget.api == null) {
        api.dispose();
      }
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  String? _coverUrl() {
    for (final String slot in <String>[
      'portrait',
      'square',
      'landscape',
    ]) {
      final String? raw = widget.card.images[slot];
      if (raw != null && raw.isNotEmpty) {
        return IslandSession.absoluteUrl(raw);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final IslandCard card = widget.card;
    final String? cover = _coverUrl();
    final bool wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(title: FitText(card.name.trim().isEmpty ? '角色卡' : card.name)),
      body: Column(
        children: <Widget>[
          if (_error != null)
            Container(
              width: double.infinity,
              color: cs.errorContainer,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FitText(_error!, style: TextStyle(color: cs.onErrorContainer)),
            ),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: (MediaQuery.sizeOf(context).width * 0.4).clamp(
                          320.0,
                          520.0,
                        ),
                        child: _buildCover(context, cover),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _buildInfo(context, card),
                        ),
                      ),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        AspectRatio(
                          aspectRatio: 4 / 3,
                          child: _buildCover(context, cover),
                        ),
                        _buildInfo(context, card),
                      ],
                    ),
                  ),
          ),
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context, String? url) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (url == null || url.isEmpty) {
      return ColoredBox(
        color: cs.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.person_outline, size: 48)),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      // 立绘加载失败不该让整页白屏：退回首字占位。
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
          ColoredBox(
            color: cs.surfaceContainerHighest,
            child: const Center(child: Icon(Icons.broken_image_outlined)),
          ),
    );
  }

  Widget _buildInfo(BuildContext context, IslandCard card) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (card.authorName.isNotEmpty || card.authorUsername.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: FitText(
                '作者：${card.authorName.isNotEmpty ? card.authorName : card.authorUsername}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (card.tags.isNotEmpty) ...<Widget>[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final String tag in card.tags)
                  Chip(
                    label: FitText(tag),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (card.gender.trim().isNotEmpty)
            _kv(context, '性别', card.gender),
          _section(context, '简介', card.intro),
          _section(context, '人设', card.persona),
          _section(context, '开场白', card.opening),
          if (card.authorNote != null && card.authorNote!.trim().isNotEmpty)
            _section(context, '作者备注', card.authorNote!),
          if (card.dialogue.isNotEmpty) ...<Widget>[
            FitText(
              '对话风格',
              style: theme.textTheme.titleSmall?.copyWith(color: cs.primary),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final DialogueTurn turn in card.dialogue.take(3))
              _dialogueSample(context, turn),
          ],
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, String body) {
    if (body.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FitText(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FitText(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: AppLineHeight.body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String key, String value) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 56,
            child: FitText(
              key,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(child: FitText(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _dialogueSample(BuildContext context, DialogueTurn turn) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme tt = Theme.of(context).textTheme;
    Widget bubble(String text, bool isUser) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: isUser ? cs.primaryContainer : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: FitText(
            text,
            style: tt.bodySmall?.copyWith(
              color: isUser ? cs.onPrimaryContainer : cs.onSurface,
              height: AppLineHeight.body,
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (turn.user.trim().isNotEmpty) bubble(turn.user, true),
        if (turn.assistant.trim().isNotEmpty) bubble(turn.assistant, false),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    final TrialChat? trial = _trial;
    final bool hasTrial = trial != null && trial.messages.isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: _openTrial,
                icon: const Icon(Icons.chat_bubble_outline),
                label: FitText(
                  hasTrial
                      ? '继续试聊（${trial.messages.length}/${TrialChat.maxMessages}）'
                      : '试聊',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _importing ? null : _import,
                icon: const Icon(Icons.download_outlined),
                label: FitText(_importing ? '正在导入…' : '导入到我家'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
