// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

/// AI 服务页共用的展示型小组件。
///
/// 这里只放**无状态、无业务**的视觉零件;凡涉及 `AppController` 读写
/// 的部分都留在各 Step 页面里,便于对照改动前后的行为。

/// 卡片内的次级信息块(圆角 [AppRadius.xs] + 极淡底色)。
///
/// 用于「暂无模型」「已选定 xxx」这类结果回执,以及凭据安全提示。
class AiInlineNote extends StatelessWidget {
  const AiInlineNote({
    super.key,
    required this.child,
    this.icon,
    this.iconColor,
    this.background,
  });

  final Widget child;
  final IconData? icon;
  final Color? iconColor;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: background ??
            cs.surfaceContainerHighest.withValues(alpha: AppAlpha.half),
        borderRadius: AppRadius.xsAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: AppSize.iconInline, color: iconColor ?? cs.outline),
            AppSpacing.wSm,
          ],
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 状态回执行(成功 / 失败 + 一行说明)。
///
/// 「是否成功」由调用方给出,不做文案匹配 —— 文案属于展示层,不应参与判断。
class AiStatusRow extends StatelessWidget {
  const AiStatusRow({
    super.key,
    required this.message,
    required this.success,
  });

  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color color = success ? cs.primary : cs.error;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            success ? Icons.check_circle : Icons.error_outline,
            size: AppSize.iconInline,
            color: color,
          ),
          AppSpacing.wXs,
          Expanded(
            child: FitText(
              message,
              style: AppTextStyles.caption(Theme.of(context))
                  .copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「服务商管理 / 模型预设管理 / 采样参数」这类跳转入口卡片。
///
/// 替代原先三处手写的 `Card > ListTile > Container(icon)`,
/// 由 [SettingSection] 的 `trailing` 提供右箭头。
class AiEntryCard extends StatelessWidget {
  const AiEntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Card(
      child: ListTile(
        contentPadding: AppInsets.tile,
        leading: Container(
          width: AppSize.iconBox,
          height: AppSize.iconBox,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: AppAlpha.half),
            borderRadius: AppRadius.xsAll,
          ),
          child: Icon(icon, color: cs.primary),
        ),
        title: FitText(title),
        subtitle: FitText(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// 当前生效模型的只读摘要(模型名 + 服务商)。
///
/// 高级模式下这张卡是页面的锚点:一眼看到「现在在用哪个」。
class AiActiveModelSummary extends StatelessWidget {
  const AiActiveModelSummary({
    super.key,
    required this.title,
    required this.modelName,
    required this.providerLabel,
    this.trailing,
  });

  final String title;
  final String modelName;
  final String providerLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FitText(
                title,
                style: AppTextStyles.caption(theme).copyWith(color: cs.outline),
              ),
              AppSpacing.hXs,
              FitText(
                modelName,
                style: AppTextStyles.sectionTitle(theme),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              AppSpacing.hXs,
              FitText(
                providerLabel,
                style: AppTextStyles.caption(theme)
                    .copyWith(color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[AppSpacing.wMd, trailing!],
      ],
    );
  }
}

/// 需要在本页内快速切换模型时使用的「模型胶囊」。
///
/// 仅展示名称,完整信息由 [AiActiveModelSummary] 承担。
class AiModelBadge extends StatelessWidget {
  const AiModelBadge({super.key, required this.model});

  final String model;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: AppRadius.xsAll,
      ),
      child: FitText(
        model,
        style: AppTextStyles.tiny(Theme.of(context))
            .copyWith(color: cs.onPrimaryContainer),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 「未选定模型」警示条。
///
/// 保留原有阻断提示的全部信息:标题 + 怎么解决,只是不再写第二遍用例名。
class AiMissingModelNotice extends StatelessWidget {
  const AiMissingModelNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Card(
      color: cs.errorContainer.withValues(alpha: AppAlpha.half),
      child: Padding(
        padding: AppInsets.card,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, color: cs.error),
            AppSpacing.wSm,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText(
                    '还没有选定模型',
                    style: AppTextStyles.body(theme)
                        .copyWith(color: cs.error, fontWeight: AppWeight.medium),
                  ),
                  AppSpacing.hXs,
                  FitText(
                    '聊天暂时无法发起请求。请在下方手动填写模型名，'
                    '或点「获取可用模型」自动拉取。',
                    style: AppTextStyles.caption(theme)
                        .copyWith(color: cs.onErrorContainer),
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

/// 「API」等术语的通俗解释开关。
///
/// 收起时只占一行:「这些词是什么意思?」;展开后才给出对照表。
/// 属于 `SETTINGS_AUDIT.md` 规矩 3 所说的「参考手册,移出设置项旁边」。
class AiGlossary extends StatefulWidget {
  const AiGlossary({super.key, required this.entries});

  /// 术语 → 通俗解释。
  final Map<String, String> entries;

  @override
  State<AiGlossary> createState() => _AiGlossaryState();
}

class _AiGlossaryState extends State<AiGlossary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: AppRadius.xsAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.help_outline,
                  size: AppSize.iconInline,
                  color: cs.outline,
                ),
                AppSpacing.wSm,
                Expanded(
                  child: FitText(
                    '这些词是什么意思？',
                    style: AppTextStyles.caption(theme)
                        .copyWith(color: cs.outline),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: AppSize.iconInline,
                  color: cs.outline,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final MapEntry<String, String> e in widget.entries.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: FitText(
                      '${e.key} —— ${e.value}',
                      style: AppTextStyles.caption(theme)
                          .copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 一组互斥选项(服务商 / 思考强度 / 界面模式)。
///
/// 用 [ChoiceChip] 而不是手写容器,圆角与配色交给主题。
class AiChoiceGroup<T> extends StatelessWidget {
  const AiChoiceGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.subtitle,
  });

  final List<T> options;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  /// 选项下方的一行说明(可选)。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final T option in options)
              ChoiceChip(
                label: FitText(labelOf(option)),
                selected: option == selected,
                onSelected: (_) => onSelected(option),
              ),
          ],
        ),
        if (subtitle != null) ...<Widget>[
          AppSpacing.hXs,
          FitText(
            subtitle!,
            style: AppTextStyles.caption(theme)
                .copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ],
    );
  }
}

/// 模型名称输入框。
///
/// 模型名是**文本标识符**,按规范不套折叠组件,保持普通输入框。
class AiModelNameField extends StatelessWidget {
  const AiModelNameField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onSubmitted,
    this.errorText,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: '模型名称',
        hintText: hintText,
        border: const OutlineInputBorder(),
        errorText: errorText,
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// 页面上方的模式切换:简易模式(少选项)↔ 完整模式。
///
/// 行为与原 `SwitchListTile` 完全一致,只是把术语换成了人话。
class AiModeSection extends StatelessWidget {
  const AiModeSection({
    super.key,
    required this.simpleMode,
    required this.onChanged,
  });

  final bool simpleMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingSection(
      icon: Icons.tune,
      title: '显示多少选项',
      description: simpleMode ? '只留最常用的：填地址、填密钥、选模型。' : '展示服务商与模型预设的完整管理入口。',
      children: <Widget>[
        SettingSwitch(
          title: '精简模式',
          subtitle: simpleMode ? '只显示常用设置' : '显示全部设置',
          value: simpleMode,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
