import 'dart:io';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/dialogue_style.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../state/app_controller.dart';

/// 删除确认页的「内容预览」构建器集合。
///
/// 每个函数返回一组可直接放入滚动列表的 Widget，供 [DeleteConfirmPage]
/// 在 5 秒滚动确认期间展示，方便用户最后核查要删除的内容。

// ===== 角色卡 =====

List<Widget> buildTaPreviewSections(BuildContext context, TA ta) {
  final ColorScheme cs = Theme.of(context).colorScheme;
  final TextTheme tt = Theme.of(context).textTheme;

  Widget imageOrPlaceholder(String? p) {
    if (p == null || p.isEmpty) {
      return Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
      );
    }
    return Image.file(
      File(p),
      fit: BoxFit.cover,
      errorBuilder: (BuildContext c, Object e, StackTrace? s) => Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
      ),
    );
  }

  List<Widget> slots = <Widget>[
    _previewSlot(cs, tt, '1:1 形象', ta.images['square'], 1, imageOrPlaceholder),
    _previewSlot(cs, tt, '16:9 形象', ta.images['landscape'], 16 / 9, imageOrPlaceholder),
    _previewSlot(cs, tt, '9:16 形象', ta.images['portrait'], 9 / 16, imageOrPlaceholder),
  ];

  return <Widget>[
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('TA 形象', style: tt.titleLarge),
            const SizedBox(height: 12),
            ...slots,
          ],
        ),
      ),
    ),
    const SizedBox(height: 12),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('人设', style: tt.titleLarge),
            const SizedBox(height: 12),
            _infoRow(cs, tt, '名字', ta.name),
            _infoRow(cs, tt, '性别', ta.gender),
            _infoRow(cs, tt, '设定', ta.persona),
            _infoRow(cs, tt, '介绍', ta.intro),
            _infoRow(cs, tt, '开场白', ta.opening),
            if (ta.tags.isNotEmpty) ...<Widget>[
              Text('标签',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    ta.tags.map((String t) => Chip(label: Text(t))).toList(),
              ),
            ],
          ],
        ),
      ),
    ),
    if (ta.dialogueStyle.isNotEmpty) ...<Widget>[
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('对话风格', style: tt.titleLarge),
              const SizedBox(height: 12),
              for (final DialogueTurn turn in ta.dialogueStyle) ...<Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('我：${turn.user}',
                          style: tt.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('TA：${turn.assistant}', style: tt.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    ],
  ];
}

// ===== 世界 =====

List<Widget> buildWorldPreviewSections(BuildContext context, World world) {
  final ColorScheme cs = Theme.of(context).colorScheme;
  final TextTheme tt = Theme.of(context).textTheme;

  return <Widget>[
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('世界信息', style: tt.titleLarge),
            const SizedBox(height: 12),
            _infoRow(cs, tt, '名称', world.name),
            _infoRow(cs, tt, '简介', world.summary),
            _infoRow(cs, tt, '描述', world.description),
            if (world.tags.isNotEmpty) ...<Widget>[
              Text('标签',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: world.tags
                    .map((String t) => Chip(label: Text(t)))
                    .toList(),
              ),
            ],
            if (world.forbiddenWords.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('屏蔽词',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: world.forbiddenWords
                    .map((String t) => Chip(label: Text(t)))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    ),
    if (world.entries.isNotEmpty) ...<Widget>[
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('词条（${world.entries.length}）', style: tt.titleLarge),
              const SizedBox(height: 12),
              for (final WorldEntry entry in world.entries) ...<Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(entry.name,
                          style: tt.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(entry.description, style: tt.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    ],
  ];
}

// ===== 对话（单聊 / 群聊） =====

List<Widget> buildConversationPreviewSections(
  BuildContext context,
  AppController controller,
  Conversation conv,
) {
  final ColorScheme cs = Theme.of(context).colorScheme;
  final TextTheme tt = Theme.of(context).textTheme;

  final String displayTitle = conv.isGroup
      ? (conv.groupName.trim().isNotEmpty ? conv.groupName.trim() : '未命名群聊')
      : (controller.getTaById(conv.taId)?.name.isNotEmpty == true
          ? controller.getTaById(conv.taId)!.name
          : '未命名会话');
  final World? world = controller.getWorldById(conv.worldId);

  String speakerName(String? taId) {
    if (taId == null || taId.isEmpty) return 'TA';
    return controller.getTaById(taId)?.name.isNotEmpty == true
        ? controller.getTaById(taId)!.name
        : 'TA';
  }

  return <Widget>[
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(conv.isGroup ? '群聊信息' : '对话信息', style: tt.titleLarge),
            const SizedBox(height: 12),
            _infoRow(cs, tt, conv.isGroup ? '群名' : '角色', displayTitle),
            if (world != null) _infoRow(cs, tt, '世界', world.name),
            if (conv.note.isNotEmpty) _infoRow(cs, tt, '备注', conv.note),
            _infoRow(cs, tt, '消息数', '${conv.messages.length}'),
          ],
        ),
      ),
    ),
    const SizedBox(height: 12),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('消息记录', style: tt.titleLarge),
            const SizedBox(height: 12),
            for (final ConversationMessage m in conv.messages) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      m.role == 'user'
                          ? '我'
                          : (conv.isGroup
                              ? speakerName(m.speakerTaId)
                              : 'TA'),
                      style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(m.text.isEmpty ? '（空）' : m.text,
                        style: tt.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    ),
  ];
}

// ===== 共享小部件 =====

Widget _infoRow(
  ColorScheme cs,
  TextTheme tt,
  String label,
  String value,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value.isEmpty ? '（空）' : value, style: tt.bodyMedium),
      ],
    ),
  );
}

Widget _previewSlot(
  ColorScheme cs,
  TextTheme tt,
  String title,
  String? path,
  double aspect,
  Widget Function(String?) imageOrPlaceholder,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: tt.titleMedium),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: aspect,
            child: imageOrPlaceholder(path),
          ),
        ),
      ],
    ),
  );
}
