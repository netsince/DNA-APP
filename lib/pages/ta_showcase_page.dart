import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/dialogue_style.dart';
import '../models/ta.dart';
import '../services/image_storage.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/conversation_labels.dart';
import '../utils/id_utils.dart';
import '../widgets/fit_text.dart';
import '../widgets/ta_avatar.dart';
import '../widgets/ta_cover.dart';
import 'chat_page.dart';
import 'delete_confirm_page.dart';
import 'delete_preview_builders.dart';
import 'ta_editor_page.dart';

/// 角色展示页:**先看人,再决定要不要聊或改**。
///
/// 从「我家」点卡片进来 —— 点卡片的默认意图通常是"看看这是谁",而不是
/// "改它",所以编辑收成右上角一个小图标、归档收进「⋮」,主按钮留给
/// 「开始新聊天」。
///
/// 布局:hero 大图 → 长条 tab(介绍 | 已有聊天) → 内容;
/// 底部一个「开始新聊天」主按钮。
///
/// 「已有聊天」与聊天页侧栏**共用同一套排序与文案**
/// (见 utils/conversation_labels.dart):同一条聊天在两处长得一样。
class TaShowcasePage extends StatefulWidget {
  const TaShowcasePage({
    super.key,
    required this.controller,
    required this.taId,
  });

  final AppController controller;

  /// 用 id 而不是 TA 对象:编辑之后这一页要能显示最新数据。
  final String taId;

  @override
  State<TaShowcasePage> createState() => _TaShowcasePageState();
}

class _TaShowcasePageState extends State<TaShowcasePage> {
  /// 0 = 介绍,1 = 已有聊天。
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final TA? ta = widget.controller.getTaById(widget.taId);
        if (ta == null) {
          // 角色在别处被删掉了:别停在一个空壳上。
          return const Scaffold(body: SizedBox.shrink());
        }
        final List<Conversation> chats = conversationsOfTa(
          widget.controller,
          ta.id,
        );
        return Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              _buildHero(context, ta),
              SliverToBoxAdapter(child: _buildTabBar(context)),
              ...(_tab == 0
                  ? _buildIntroSlivers(context, ta)
                  : _buildChatSlivers(context, chats)),
            ],
          ),
          bottomNavigationBar: _buildStartChatBar(context, ta),
        );
      },
    );
  }

  // ---------- hero ----------

  Widget _buildHero(BuildContext context, TA ta) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String? slot = TaCover.slotOf(ta, priority: TaCover.heroPriority);
    final ImageProvider? image = slot == null
        ? null
        : ImageStorage.instance.providerFor(ta, slot);

    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      // 编辑:小图标;归档/删除收进「⋮」—— 点开才出现。
      actions: <Widget>[
        IconButton(
          tooltip: '编辑',
          onPressed: () => _openEditor(context, ta),
          icon: const Icon(Icons.edit_outlined),
        ),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (String value) => _onMenu(context, ta, value),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: ta.archived ? 'unarchive' : 'archive',
              child: ListTile(
                leading: Icon(
                  ta.archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: FitText(ta.archived ? '取消归档' : '归档'),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: FitText('删除'),
              ),
            ),
          ],
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        title: FitText(
          ta.name.trim().isEmpty ? '未命名TA' : ta.name,
          style: theme.textTheme.titleMedium,
        ),
        background: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (image != null)
              Image(image: image, fit: BoxFit.cover)
            else
              ColoredBox(
                color: cs.surfaceContainerHighest,
                child: Center(
                  child: TaAvatar(ta: ta, size: 96, borderRadius: 24),
                ),
              ),
            // 底部压一层渐变,保证标题与图标在任何立绘上都读得清。
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    cs.surface.withValues(alpha: 0.35),
                    cs.surface.withValues(alpha: 0.0),
                    cs.surface.withValues(alpha: 0.85),
                  ],
                  stops: const <double>[0.0, 0.45, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 长条 tab ----------

  Widget _buildTabBar(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: <Widget>[
            _tabButton(context, 0, '介绍'),
            _tabButton(context, 1, '已有聊天'),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(BuildContext context, int index, String label) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.all(4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: FitText(
            label,
            style: TextStyle(
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: selected ? AppWeight.medium : AppWeight.regular,
            ),
          ),
        ),
      ),
    );
  }

  // ---------- 介绍 ----------

  List<Widget> _buildIntroSlivers(BuildContext context, TA ta) {
    final ThemeData theme = Theme.of(context);
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        sliver: SliverList(
          delegate: SliverChildListDelegate(<Widget>[
            if (ta.tags.isNotEmpty) ...<Widget>[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final String tag in ta.tags)
                    Chip(label: FitText(tag), visualDensity: VisualDensity.compact),
                ],
              ),
              const SizedBox(height: 18),
            ],
            if (ta.gender.trim().isNotEmpty)
              _kv(context, '性别', ta.gender),
            _section(context, '简介', ta.intro),
            _section(context, '人设', ta.persona),
            _section(context, '开场白', ta.opening),
            _section(context, '作者备注', ta.authorNote ?? ''),
            if (ta.dialogueStyle.isNotEmpty) ...<Widget>[
              FitText(
                '对话风格',
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 8),
              for (final DialogueTurn turn in ta.dialogueStyle.take(3))
                _dialogueSample(context, turn),
            ],
          ]),
        ),
      ),
    ];
  }

  Widget _section(BuildContext context, String title, String body) {
    if (body.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FitText(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
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
      padding: const EdgeInsets.only(bottom: 12),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: isUser ? cs.primaryContainer : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
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
        const SizedBox(height: 6),
      ],
    );
  }

  // ---------- 已有聊天 ----------

  List<Widget> _buildChatSlivers(
    BuildContext context,
    List<Conversation> chats,
  ) {
    if (chats.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FitText(
                '还没有聊天记录，点下面的按钮开始吧。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ),
        ),
      ];
    }
    final ColorScheme cs = Theme.of(context).colorScheme;
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        sliver: SliverList.builder(
          itemCount: chats.length,
          itemBuilder: (BuildContext context, int index) {
            final Conversation chat = chats[index];
            final int count = chat.messages.length;
            return ListTile(
              leading: Icon(
                chat.pinned ? Icons.push_pin : Icons.chat_bubble_outline,
                color: chat.pinned ? cs.primary : cs.onSurfaceVariant,
              ),
              title: FitText(conversationLabel(chat)),
              subtitle: FitText(count == 0 ? '空会话' : '$count 条消息'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openChat(context, chat),
            );
          },
        ),
      ),
    ];
  }

  // ---------- 底部主按钮 ----------

  Widget _buildStartChatBar(BuildContext context, TA ta) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _startNewChat(context, ta),
            icon: const Icon(Icons.add_comment_outlined),
            label: const FitText('开始新聊天'),
          ),
        ),
      ),
    );
  }

  // ---------- 动作 ----------

  void _openEditor(BuildContext context, TA ta) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            TaEditorPage(controller: widget.controller, ta: ta),
      ),
    );
  }

  void _openChat(BuildContext context, Conversation chat) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChatPage(
          controller: widget.controller,
          conversationId: chat.id,
          isGroup: chat.isGroup,
        ),
      ),
    );
  }

  /// 新建一个空会话并直接进入 —— 这是本页的主按钮。
  Future<void> _startNewChat(BuildContext context, TA ta) async {
    String id = newId();
    final Set<String> existing = widget.controller.conversations
        .map((Conversation c) => c.id)
        .toSet();
    while (existing.contains(id)) {
      id = newId();
    }
    final Conversation conversation = Conversation(
      id: id,
      taId: ta.id,
      worldId: null,
      note: '',
      messages: const <ConversationMessage>[],
      backgroundMode: 'none',
      summaries: const <ConversationSummary>[],
      archived: false,
      isGroup: false,
      groupName: '',
      groupPrompt: '',
      memberTaIds: <String>[ta.id],
      activeTaId: ta.id,
    );
    await widget.controller.upsertConversation(conversation);
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChatPage(
          controller: widget.controller,
          conversationId: id,
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, TA ta, String value) async {
    if (value == 'archive') {
      await widget.controller.setTaArchived(id: ta.id, archived: true);
      return;
    }
    if (value == 'unarchive') {
      await widget.controller.setTaArchived(id: ta.id, archived: false);
      return;
    }
    if (value != 'delete' || !context.mounted) {
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => DeleteConfirmPage(
          controller: widget.controller,
          title: '删除角色',
          entityName: ta.name,
          validNames: <String>[ta.name],
          promptHint: '请完整输入角色名「${ta.name}」以确认删除',
          contentBuilder: (BuildContext ctx) =>
              buildTaPreviewSections(ctx, ta),
          onDelete: () => widget.controller.deleteTaWithBackup(ta.id),
          requireName: widget.controller.settings.requireNameToDelete,
        ),
      ),
    );
    // 删掉之后这一页就没有主体了,退回列表。
    if (context.mounted && widget.controller.getTaById(ta.id) == null) {
      Navigator.of(context).maybePop();
    }
  }
}
