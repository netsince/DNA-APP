// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../models/dialogue_style.dart';
import '../../widgets/adaptive_text_field.dart';
import '../../widgets/app_editor_frame.dart';
import '../../widgets/fit_text.dart';

/// 对话风格表单的句柄。
class DialogueStyleFormController extends ChangeNotifier {
  _DialogueStyleFormState? _state;

  String? _baseline;

  void _attach(_DialogueStyleFormState state) {
    _state = state;
    _baseline = _sig(state._currentTurns());
  }

  /// 是否有未保存改动（外壳返回时用来确认）。
  bool get isDirty {
    final _DialogueStyleFormState? state = _state;
    if (state == null || _baseline == null) {
      return false;
    }
    return _sig(state._currentTurns()) != _baseline;
  }

  /// 各轮的稳定指纹（user/assistant 用不可见分隔符拼接）。
  static String _sig(List<DialogueTurn> turns) => turns
      .map((DialogueTurn t) => '${t.user}\u0001${t.assistant}')
      .join('\u0002');

  void _detach(_DialogueStyleFormState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  /// 当前各轮范例。
  List<DialogueTurn> current() => _state?._currentTurns() ?? <DialogueTurn>[];

  /// 追加一轮（按钮在外壳上，动作在表单里）。
  void addTurn() => _state?._addTurn();
}

/// 对话风格（Few-shot 范例）**表单**：只有各轮输入输出，没有顶栏/保存/FAB。
class DialogueStyleForm extends StatefulWidget {
  const DialogueStyleForm({
    super.key,
    required this.initial,
    required this.formController,
  });

  /// 初始各轮（通常来自 TA.dialogueStyle）。
  final List<DialogueTurn> initial;

  final DialogueStyleFormController formController;

  @override
  State<DialogueStyleForm> createState() => _DialogueStyleFormState();
}

class _DialogueStyleFormState extends State<DialogueStyleForm> {
  late List<DialogueTurn> _turns;

  @override
  void initState() {
    super.initState();
    _turns = List<DialogueTurn>.from(widget.initial);
    if (_turns.isEmpty) {
      _turns = <DialogueTurn>[const DialogueTurn(user: '', assistant: '')];
    }
    widget.formController._attach(this);
  }

  @override
  void dispose() {
    widget.formController._detach(this);
    super.dispose();
  }

  List<DialogueTurn> _currentTurns() => List<DialogueTurn>.from(_turns);

  void _addTurn() {
    setState(() => _turns = <DialogueTurn>[
          ..._turns,
          const DialogueTurn(user: '', assistant: ''),
        ]);
  }

  void _removeTurn(int index) {
    if (_turns.length <= 1) {
      return;
    }
    setState(() {
      _turns = <DialogueTurn>[
        ..._turns.take(index),
        ..._turns.skip(index + 1),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView.builder(
      padding: AppEditorLayout.bodyPadding(context),
      itemCount: _turns.length + 1,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.info_outline,
                          size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      FitText(
                        '对话风格说明',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: AppWeight.medium,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '每轮示例包含【你的提问】与【TA的回答】。AI 会模仿示例中的用词、口吻、动作描写与语气习惯。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }

        final int turnIndex = index - 1;
        final DialogueTurn turn = _turns[turnIndex];

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    FitText(
                      '范例第 ${turnIndex + 1} 轮',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: AppWeight.medium),
                    ),
                    if (_turns.length > 1)
                      IconButton(
                        onPressed: () => _removeTurn(turnIndex),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: '删除此轮',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: turn.user,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: '你的发言（输入）',
                    hintText: '例如：今天天气真好，一起去散步吗？',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  onChanged: (String value) {
                    _turns[turnIndex] = _turns[turnIndex].copyWith(user: value);
                  },
                ),
                const SizedBox(height: 8),
                AdaptiveTextField(
                  key: ValueKey<String>(
                      'assist_${turnIndex}_${turn.assistant.hashCode}'),
                  controller: TextEditingController(text: turn.assistant),
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: 'TA 的回答 / 语气范例（输出）',
                    hintText: '例如：哼，既然你都邀请了，本小姐就勉为其难陪你走走吧。',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.smart_toy_outlined, size: 20),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  onChanged: (String value) {
                    _turns[turnIndex] =
                        _turns[turnIndex].copyWith(assistant: value);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
