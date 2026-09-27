// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

import 'widgets.dart';

/// 简易模式的「用哪个模型」卡片。
///
/// 收起态只有「模型名称 + 当前值」一行,展开后才出现输入框与拉取按钮
/// —— 与 `CollapsibleNumberSetting` 的语序保持一致。
/// (模型名是文本标识符,因此用普通输入框而不是 `CollapsibleTextSetting`。)
class AiModelSection extends StatefulWidget {
  const AiModelSection({
    super.key,
    required this.nameController,
    required this.selectedModel,
    required this.models,
    required this.loading,
    required this.errorMessage,
    required this.onNameChanged,
    required this.onNameSubmitted,
    required this.onCreateModel,
    required this.onFetchModels,
    required this.onPickModel,
  });

  /// 模型名输入框(用户可手动填写)。
  final TextEditingController nameController;

  /// 当前生效模型(为空表示未选定)。
  final String? selectedModel;

  /// 已拉取到的可选模型。
  final List<String> models;

  final bool loading;
  final String? errorMessage;

  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onNameSubmitted;
  final VoidCallback onCreateModel;
  final VoidCallback onFetchModels;
  final ValueChanged<String> onPickModel;

  @override
  State<AiModelSection> createState() => _AiModelSectionState();
}

class _AiModelSectionState extends State<AiModelSection> {
  bool _expanded = false;

  bool get _missing => (widget.selectedModel ?? '').trim().isEmpty;

  String get _displayValue => _missing ? '未选定' : widget.selectedModel!.trim();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return SettingSection(
      icon: Icons.smart_toy_outlined,
      title: '用哪个模型',
      description: '不同模型的风格和能力不一样。',
      children: <Widget>[
        // ===== 收起态:名称 + 当前值 =====
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: AppRadius.xsAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FitText('模型名称', style: AppTextStyles.body(theme)),
                ),
                AppSpacing.wMd,
                Flexible(
                  child: FitText(
                    _displayValue,
                    style: AppTextStyles.body(theme).copyWith(
                      color: _missing ? cs.error : cs.primary,
                      fontWeight: AppWeight.medium,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AppSpacing.wXs,
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: AppSize.iconInline,
                  color: cs.outline,
                ),
              ],
            ),
          ),
        ),

        // ===== 展开态:输入框 + 拉取 + 可选列表 =====
        if (_expanded) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AiModelNameField(
              controller: widget.nameController,
              hintText: '例如 deepseek-chat',
              errorText: _missing ? '填一个模型名称才能开始聊天' : null,
              onChanged: widget.onNameChanged,
              onSubmitted: widget.onNameSubmitted,
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: widget.loading ? null : widget.onFetchModels,
                icon: widget.loading
                    ? const SizedBox(
                        width: AppSize.iconInline,
                        height: AppSize.iconInline,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: FitText(widget.loading ? '获取中…' : '获取可用模型'),
              ),
              OutlinedButton.icon(
                onPressed: widget.onCreateModel,
                icon: const Icon(Icons.edit_outlined),
                label: const FitText('新建模型预设'),
              ),
            ],
          ),

          if (widget.errorMessage != null) ...<Widget>[
            AppSpacing.hSm,
            FitText(
              widget.errorMessage!,
              style: AppTextStyles.caption(theme).copyWith(color: cs.error),
            ),
          ],

          AppSpacing.hMd,
          if (widget.models.isEmpty)
            AiInlineNote(
              child: FitText(
                _missing
                    ? '还没有可选项。点「获取可用模型」自动拉取，或直接填写名称。'
                    : '已记录：$_displayValue',
                style: AppTextStyles.caption(theme)
                    .copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else ...<Widget>[
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                border: Border.all(color: AppBorder.color(cs)),
                borderRadius: AppRadius.xsAll,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.models.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final String model = widget.models[index];
                  final bool selected = model == widget.selectedModel;

                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: AppInsets.group,
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: AppSize.iconInline,
                      color: selected ? cs.primary : cs.outline,
                    ),
                    title: FitText(
                      model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(theme).copyWith(
                        color: selected ? cs.primary : null,
                        fontWeight:
                            selected ? AppWeight.medium : AppWeight.regular,
                      ),
                    ),
                    onTap: () => widget.onPickModel(model),
                  );
                },
              ),
            ),
          ],
        ],
      ],
    );
  }
}
