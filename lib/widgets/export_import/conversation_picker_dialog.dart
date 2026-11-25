import 'package:material_ui/material_ui.dart';

import '../../models/conversation.dart';
import 'package:dna/widgets/fit_text.dart';

/// 选择要导出的对话。
///
/// 容器是 bottom sheet（`DraggableScrollableSheet`）而不是 dialog ——
/// 这是一张**可多选的管理列表**，不是需要立刻拍板的决定（审计 3.2）。
/// 旧实现把列表塞进 `AlertDialog` 并把高度写死 400：对话多时列表被截，
/// 少时留一大片空白，两者都不跟窗口走。
///
/// 返回值语义保持不变：确定 → 选中 id 列表（可能为空）；取消/下滑关闭 → null。
Future<List<String>?> showConversationPickerDialog({
  required BuildContext context,
  required List<Conversation> conversations,
  required Map<String, String> nameById,
}) async {
  final selected = <String>{};
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (bc, setSB) => DraggableScrollableSheet(
          // expand: false —— 高度由下面的比例决定，而不是撑满整屏。
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (bc2, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: FitText(
                  '选择要导出的对话',
                  style: Theme.of(bc2).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: conversations.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        child: FitText('没有可导出的对话'),
                      )
                    : ListView(
                        controller: scrollController,
                        children: conversations.map((c) {
                          final n = nameById[c.id] ?? '未命名';
                          final sel = selected.contains(c.id);
                          return CheckboxListTile(
                            value: sel,
                            title: FitText(n),
                            onChanged: (v) {
                              setSB(() {
                                if (v == true) {
                                  selected.add(c.id);
                                } else {
                                  selected.remove(c.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(bc, null),
                          child: const FitText('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.pop(bc, selected.toList()),
                          child: const FitText('确定'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
