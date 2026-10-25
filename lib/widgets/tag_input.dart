import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 标签输入：输入后回车 / 逗号落成可移除的 chips。
///
/// 与社区角色卡发布页原来那个私有实现是同一套交互，抽成公共组件后角色卡
/// （发布 / 本体编辑器）和世界卡（发布 / 本体编辑器）共用一份 —— 四处各自
/// 写一个「逗号分隔的文本框」正是标签数据散装、筛选条空着的根因。
///
/// [suggestions] 是可选的热门标签候选：点一下直接加。它是把自由文本慢慢
/// 收敛成受控词表的唯一低成本办法（否则「科幻 / 科幻小说 / sci-fi」永远并存）。
class TagInput extends StatefulWidget {
  const TagInput({
    super.key,
    required this.tags,
    required this.onChanged,
    this.suggestions = const <String>[],
    this.maxTags = 20,
    this.hintText = '输入标签后按回车或逗号添加，中英文逗号均可',
    this.suggestionTitle = '热门标签',
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final List<String> suggestions;
  final int maxTags;
  final String hintText;
  final String suggestionTitle;

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final List<String> parts = raw
        .split(RegExp(r'[,，]'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      _controller.clear();
      return;
    }
    final List<String> next = List<String>.from(widget.tags);
    for (final String p in parts) {
      if (next.length >= widget.maxTags) break;
      if (!next.contains(p)) next.add(p);
    }
    _controller.clear();
    if (next.length != widget.tags.length) widget.onChanged(next);
  }

  void _add(String tag) {
    if (widget.tags.contains(tag) || widget.tags.length >= widget.maxTags) return;
    widget.onChanged(<String>[...widget.tags, tag]);
  }

  void _remove(String tag) {
    widget.onChanged(widget.tags.where((String t) => t != tag).toList());
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<String> suggestions = widget.suggestions
        .where((String s) => s.trim().isNotEmpty && !widget.tags.contains(s))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.tags.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final String tag in widget.tags)
                InputChip(
                  label: Text(tag),
                  // 显式给删除图标：默认图标随主题变化，测试与截图都不稳定。
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => _remove(tag),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: widget.hintText,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: _commit,
          onChanged: (String v) {
            // 输入中英文逗号时直接落为标签。
            if (v.contains(',') || v.contains('，')) _commit(v);
          },
          onTapOutside: (_) => _commit(_controller.text),
        ),
        const SizedBox(height: 4),
        Text(
          '点击标签上的 × 可移除（最多 ${widget.maxTags} 个）',
          style: TextStyle(
          fontSize: AppFontSize.caption,
          color: cs.onSurfaceVariant,
        ),
        ),
        if (suggestions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            widget.suggestionTitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final String s in suggestions.take(12))
                ActionChip(
                  label: Text(s),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _add(s),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
