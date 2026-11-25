import 'package:material_ui/material_ui.dart';

import 'package:dna/models/ta.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

/// 「添加群成员」的多选 sheet。
///
/// 从 `chat_surface.dart` 的 State 里搬出来：那是一段 175 行的内联闭包，
/// 跟聊天状态、消息渲染、发送链路挤在同一个类里，改它要在一千四百行里定位。
/// 这里有独立入参（候选列表 + 强调色主题），没有别的隐式依赖。
///
/// 返回选中的 id 列表；取消 / 下滑关闭返回 null。
Future<List<String>?> showGroupMemberPickerSheet({
  required BuildContext context,
  required List<TA> candidates,
  required ThemeData accentTheme,
}) async {
  final Set<String> selected = <String>{};
    // 「添加群成员」是一次多选任务（可能很长的名单），不是需要模态阻断的决定：
    // 用可滚动的大 sheet + 搜索，而不是把多选列表塞进 AlertDialog（审计 3.2）。
    // 返回语义不变：确认回传选中的 id 列表，取消/下滑关闭回传 null。
    final List<String>? updated = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        List<TA> visible = candidates;
        return Theme(
          data: accentTheme,
          child: StatefulBuilder(
            builder:
                (
                  BuildContext sheetContext,
                  void Function(void Function()) setSheet,
                ) {
                  final ThemeData theme = Theme.of(sheetContext);
                  final ColorScheme cs = theme.colorScheme;
                  return Padding(
                    // 键盘避让：搜索框聚焦时整块抬到键盘上方。
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.sizeOf(sheetContext).height * 0.85,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              0,
                              AppSpacing.lg,
                              AppSpacing.md,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: FitText(
                                    '添加群成员',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                if (selected.isNotEmpty)
                                  FitText(
                                    '已选 ${selected.length}',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(color: cs.primary),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                            ),
                            child: TextField(
                              decoration: const InputDecoration(
                                hintText: '搜索名字',
                                prefixIcon: Icon(Icons.search),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (String value) {
                                final String keyword = value.trim();
                                setSheet(() {
                                  visible = keyword.isEmpty
                                      ? candidates
                                      : candidates
                                            .where(
                                              (TA t) =>
                                                  t.name.contains(keyword),
                                            )
                                            .toList();
                                });
                              },
                            ),
                          ),
                          AppSpacing.hMd,
                          Flexible(
                            child: visible.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.xl,
                                    ),
                                    child: Center(
                                      child: FitText(
                                        '没有匹配的名字',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    itemCount: visible.length,
                                    itemBuilder:
                                        (
                                          BuildContext context,
                                          int index,
                                        ) {
                                          final TA ta = visible[index];
                                          return CheckboxListTile(
                                            value: selected.contains(
                                              ta.id,
                                            ),
                                            title: FitText(
                                              ta.name.isEmpty
                                                  ? '未命名TA'
                                                  : ta.name,
                                            ),
                                            onChanged: (bool? value) {
                                              setSheet(() {
                                                if (value == true) {
                                                  selected.add(ta.id);
                                                } else {
                                                  selected.remove(ta.id);
                                                }
                                              });
                                            },
                                          );
                                        },
                                  ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.md,
                              AppSpacing.lg,
                              AppSpacing.lg +
                                  MediaQuery.viewPaddingOf(
                                    sheetContext,
                                  ).bottom,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        Navigator.of(sheetContext).pop(),
                                    child: const FitText('取消'),
                                  ),
                                ),
                                AppSpacing.wMd,
                                Expanded(
                                  child: FilledButton(
                                    onPressed: selected.isEmpty
                                        ? null
                                        : () => Navigator.of(
                                            sheetContext,
                                          ).pop(selected.toList()),
                                    child: const FitText('添加'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
          ),
        );
      },
    );
  return updated;
}
