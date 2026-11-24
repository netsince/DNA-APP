import 'package:flutter/material.dart';

import 'package:dna/models/ta.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

/// 群聊的「发言控制」条：横向成员列表 + 末尾「添加成员」。
///
/// 从 `chat_surface.dart` 的 State 里搬出来。原来是一个 113 行的私有方法，
/// 只依赖「成员列表 / 当前发言者 / 头像 / 三个回调」，没有别的隐式依赖。
class SpeakerBar extends StatelessWidget {
  const SpeakerBar({
    super.key,
    required this.showBar,
    required this.members,
    required this.activeTaId,
    required this.avatarFor,
    required this.onSpeak,
    required this.onAddMember,
    required this.primaryContainer,
    required this.surfaceContainerHighest,
    required this.textTheme,
  });

  /// 只有群聊且成员非空时才显示。
  final bool showBar;
  final List<TA> members;
  final String? activeTaId;
  final ImageProvider? Function(TA ta) avatarFor;
  final void Function(TA ta) onSpeak;
  final VoidCallback onAddMember;
  final Color primaryContainer;
  final Color surfaceContainerHighest;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    if (!showBar) {
      return const SizedBox.shrink();
    }
    final List<TA> tas = members;
    if (tas.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          const FitText('发言控制'),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              // 60 而不是 56：选中态外圈描边（2 内边距 + 2 描边）会让单项
              // 高 4px，56 时正好溢出 2px（RenderFlex overflow）。
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tas.length,
                separatorBuilder: (_, int index) => const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  final TA ta = tas[index];
                  final bool active = ta.id == activeTaId;
                  final ImageProvider? avatar = avatarFor(ta);
                  // 发言者选择：既是"可点的目标"也是"当前选中的一项"，
                  // 所以要有涟漪、按钮语义与 selected 语义，且选中态不能只靠
                  // 底色（审计 4.3「只用颜色表达状态」）。外圈描边是非颜色冗余。
                  return Semantics(
                    button: true,
                    selected: active,
                    label: ta.name.isNotEmpty ? ta.name : '未命名TA',
                    hint: active ? '当前发言者' : '点击让它发言',
                    child: InkWell(
                      borderRadius: AppRadius.smAll,
                      onTap: () => onSpeak(ta),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxs,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: active
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        width: 2,
                                      ),
                                    )
                                  : null,
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: active
                                    ? primaryContainer
                                    : surfaceContainerHighest,
                                foregroundImage: avatar,
                                child: avatar == null
                                    ? FitText(
                                        ta.name.isNotEmpty ? ta.name[0] : '?',
                                        style: textTheme.labelMedium,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              width: 56,
                              child: FitText(
                                ta.name.isEmpty ? '未命名' : ta.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: textTheme.labelSmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          IconButton(
            onPressed: onAddMember,
            tooltip: '添加成员',
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
    );
  }
}

