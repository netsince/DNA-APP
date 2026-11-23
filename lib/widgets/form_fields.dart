import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'fit_text.dart';
import 'form_draft.dart';

/// 编辑器表单的**通用构件**：一个分组标题 + 三类字段（文本 / 单选实体 / 多选实体）。
///
/// 这层只负责"长什么样 + 值怎么进草稿"，不负责保存与落盘 —— 那是页面的事。
/// 视觉沿用 2026-11 审计后的口径：字段分组不用 Card，靠字号阶与间距分节
/// （见 `setting_section.dart`），所以这四个构件都不画容器。

/// 一个下拉选项：值 + 显示文案。
typedef FormOption = ({String value, String label});

/// 字段分组（标题 + 间距 + 内容），与旧页面里的 `_section` 完全一致的视觉。
class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FitText(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: AppWeight.medium,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          AppSpacing.hSm,
          ...children,
        ],
      ),
    );
  }
}

/// 单行/多行文本字段。
class FormTextField extends StatelessWidget {
  const FormTextField({
    super.key,
    required this.draft,
    required this.id,
    required this.label,
    this.hint,
    this.helperText,
    this.minLines,
    this.maxLines = 1,
    this.autofocus = false,
    this.keyboardType,
    this.focusNode,
    this.obscureText = false,
    this.suffixIcon,
    this.maxLength,
    this.prefixIcon,
    this.border,
    this.isDense = false,
    this.filled = false,
    this.onChanged,
  });

  final FormDraft draft;
  final String id;
  final String label;
  final String? hint;

  /// 字段下方的说明文案（比如正则的写法提示）。
  final String? helperText;

  /// 初始可见行数（不传就按 [maxLines] 的行为：单行）。
  final int? minLines;
  final int maxLines;

  /// 进页面/弹层就聚焦（键盘直接弹起来）。
  final bool autofocus;

  /// 键盘类型（数字字段要 `TextInputType.number`，否则移动端弹全键盘）。
  final TextInputType? keyboardType;

  /// 外部持有的焦点节点（原文有些页面用来「校验失败后聚焦该字段」）。
  final FocusNode? focusNode;

  /// 是否密文显示（API Key 这类）。
  final bool obscureText;

  /// 后缀图标（如「显示 / 隐藏密文」）。
  final Widget? suffixIcon;

  /// 最大长度（如备注 120 字）。
  final int? maxLength;

  /// 前置图标（原有页面里 `Icons.title` 这类）。
  final Widget? prefixIcon;

  /// 输入框边框：默认 null = Material 默认下划线；描边页面传 `OutlineInputBorder()`。
  final InputBorder? border;

  /// 紧凑高度。
  final bool isDense;

  /// 是否填充底色。
  final bool filled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: draft.controller(id),
      focusNode: focusNode,
      obscureText: obscureText,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      autofocus: autofocus,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        errorText: draft.error(id),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        border: border,
        isDense: isDense,
        filled: filled,
      ),
      onChanged: (String v) {
        // 一输入就清掉该字段的旧错误（与既有页面行为一致）。
        if (draft.error(id) != null) draft.clearError(id);
        onChanged?.call(v);
      },
    );
  }
}

/// 单选实体字段（TA / 世界 / 身份 / 词条类型 …）。
///
/// * 数据源为空时**不渲染下拉**，只显示 [emptyHint]（原页面的处理方式）；
/// * [allowNone] 为 true 时第一项是「不选择」（值为空串，草稿里归一成 null）。
class FormEntitySelect extends StatelessWidget {
  const FormEntitySelect({
    super.key,
    required this.draft,
    required this.id,
    required this.label,
    required this.options,
    this.emptyHint,
    this.allowNone = false,
    this.noneLabel = '不选择',
    this.selectNoneInitially = false,
    this.border,
    this.isDense = false,
    this.onChanged,
  });

  final FormDraft draft;
  final String id;
  final String label;
  final List<FormOption> options;
  final String? emptyHint;
  final bool allowNone;
  final String noneLabel;

  /// 「不选择」项是否作为**初始选中**显示（原文某些页面是这种观感，
  /// 默认 false = 未选时下拉空白）。
  final bool selectNoneInitially;

  /// 下拉的边框（与旁边的描边输入框并排时传 `OutlineInputBorder()`）。
  final InputBorder? border;

  /// 紧凑高度。
  final bool isDense;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty && emptyHint != null) {
      return FitText(emptyHint!);
    }
    return DropdownButtonFormField<String>(
      initialValue:
          draft.selection(id) ?? (allowNone && selectNoneInitially ? '' : null),
      decoration: InputDecoration(
        labelText: label,
        errorText: draft.error(id),
        border: border,
        isDense: isDense,
      ),
      items: <DropdownMenuItem<String>>[
        if (allowNone)
          DropdownMenuItem<String>(
            value: '',
            child: FitText(noneLabel),
          ),
        ...options.map(
          (FormOption o) => DropdownMenuItem<String>(
            value: o.value,
            child: FitText(o.label),
          ),
        ),
      ],
      onChanged: (String? value) {
        draft.select(id, value);
        if (draft.error(id) != null) draft.clearError(id);
        onChanged?.call(draft.selection(id));
      },
    );
  }
}

/// 多选实体字段（群聊成员这类）：一行一个 CheckboxListTile。
///
/// [trailingOf] 给"随选择变化的派生展示"留了个口子（比如头像是谁）。
class FormEntityMulti extends StatelessWidget {
  const FormEntityMulti({
    super.key,
    required this.draft,
    required this.id,
    required this.options,
    this.emptyHint,
    this.titleOf,
    this.subtitleOf,
    this.trailingOf,
    this.onChanged,
    this.errorText,
    this.contentPadding,
  });

  final FormDraft draft;
  final String id;
  final List<FormOption> options;
  final String? emptyHint;
  final String Function(FormOption)? titleOf;
  final String Function(FormOption)? subtitleOf;
  final Widget Function(FormOption)? trailingOf;
  final VoidCallback? onChanged;
  final String? errorText;

  /// 行的内边距：**默认 null = 用 CheckboxListTile 的默认（水平 16）**，
  /// 与改造前手写 CheckboxListTile 的观感一致；要贴边再显式传 `EdgeInsets.zero`。
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty && emptyHint != null) {
      return FitText(emptyHint!);
    }
    final Set<String> selected = draft.multiSelection(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ...options.map((FormOption o) {
          final bool checked = selected.contains(o.value);
          return CheckboxListTile(
            value: checked,
            contentPadding: contentPadding,
            controlAffinity: ListTileControlAffinity.leading,
            title: FitText(titleOf?.call(o) ?? o.label),
            subtitle: subtitleOf == null
                ? null
                : FitText(subtitleOf!(o)),
            secondary: trailingOf?.call(o),
            onChanged: (bool? v) {
              draft.toggleMulti(id, o.value);
              onChanged?.call();
            },
          );
        }),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: FitText(
              errorText!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: AppFontSize.caption,
              ),
            ),
          ),
      ],
    );
  }
}
