import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_empty_state.dart';
import 'config_status_banner.dart';
import 'fit_text.dart';

/// 模型列表内嵌（非撑满）时的最大高度。
const double kModelListInlineMaxHeight = 240;

/// 模型选择：刷新 / 自定义按钮 + 错误提示 + 可选列表。
///
/// OOBE 的「模型选择」步骤与设置页「AI 服务（精简模式）」原先各写一份，
/// 连列表项密度、分隔线、空态文案都不一样。现在两边共用本组件。
///
/// [fill] 决定列表区的高度策略：
/// * true —— 列表撑满父级剩余高度。**调用方必须把本组件放进 Expanded**，
///   且父级 Column 的高度有界（OOBE 的步骤卡片就是这种）；
/// * false —— 列表限高 [kModelListInlineMaxHeight] 并加描边，供本身可滚动的
///   页面内嵌（设置页）。
class ModelPicker extends StatelessWidget {
  const ModelPicker({
    super.key,
    required this.models,
    required this.selectedModel,
    required this.loading,
    required this.onReload,
    required this.onSelect,
    required this.onCustom,
    this.error,
    this.fill = false,
    this.emptyTitle = '暂无可用模型',
    this.emptyDescription = '点「刷新模型列表」重新拉取，或使用自定义模型。',
    this.reloadLabel = '刷新模型列表',
    this.loadingLabel = '加载中...',
  });

  /// 已拉取到的模型列表。
  final List<String> models;

  /// 当前选中的模型 id。
  final String? selectedModel;

  /// 列表拉取中。
  final bool loading;

  /// 重新拉取。
  final VoidCallback onReload;

  /// 点选某个模型。
  final ValueChanged<String> onSelect;

  /// 手动添加自定义模型。
  final VoidCallback onCustom;

  /// 拉取失败信息；非空时展示失败横幅。
  final String? error;

  /// 列表区高度策略（见类注释）。
  final bool fill;

  /// 空态标题（列表为空且未选定模型时）。
  final String emptyTitle;

  /// 空态说明（列表为空且未选定模型时）。
  final String emptyDescription;

  /// 刷新按钮文案。
  final String reloadLabel;

  /// 刷新进行中的按钮文案。
  final String loadingLabel;

  /// 当前生效的模型 id（去掉空白后的结果），没有则为 null。
  String? get _current {
    final String value = (selectedModel ?? '').trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: loading ? null : onReload,
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: FitText(loading ? loadingLabel : reloadLabel),
            ),
            OutlinedButton.icon(
              onPressed: onCustom,
              icon: const Icon(Icons.edit_outlined),
              label: const FitText('自定义模型'),
            ),
          ],
        ),
        if (error != null) ...<Widget>[
          AppSpacing.hMd,
          ConfigStatusBanner(message: error!, isError: true),
        ],
        AppSpacing.hMd,
        _listOrEmpty(cs),
      ],
    );
  }

  /// 列表为空时给空态，否则给列表；两者都按 [fill] 决定是否撑满。
  Widget _listOrEmpty(ColorScheme cs) {
    if (models.isEmpty) {
      // 首次拉取（列表还空着）时先给转圈，别让用户盯着「暂无可用模型」发呆。
      // 已有列表时刷新则保留列表，只把按钮置灰 —— 比整块换成转圈更少跳变。
      if (loading) {
        final Widget spinner = const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: CircularProgressIndicator(),
          ),
        );
        return fill ? Expanded(child: spinner) : spinner;
      }
      // 列表空但已选定模型（例如设置里存过一个模型、还没点过刷新）时，
      // 直接告诉用户当前是哪个，而不是笼统说「暂无模型」。
      final String? current = _current;
      final Widget empty = current == null
          ? AppEmptyState(
              icon: Icons.model_training_outlined,
              title: emptyTitle,
              description: emptyDescription,
            )
          : AppEmptyState(
              icon: Icons.check_circle_outline,
              title: '已选定当前模型',
              description: current,
            );
      return fill ? Expanded(child: empty) : empty;
    }

    final Widget list = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppBorder.color(cs)),
        borderRadius: AppRadius.xsAll,
      ),
      child: ListView.separated(
        shrinkWrap: !fill,
        padding: EdgeInsets.zero,
        itemCount: models.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          final String model = models[index];
          final bool selected = model == selectedModel;
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: AppSize.iconInline,
              color: selected ? cs.primary : cs.outline,
            ),
            title: FitText(
              model,
              style: TextStyle(
                fontWeight: selected ? AppWeight.medium : AppWeight.regular,
                color: selected ? cs.primary : null,
              ),
            ),
            onTap: () => onSelect(model),
          );
        },
      ),
    );

    return fill
        ? Expanded(child: list)
        : ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: kModelListInlineMaxHeight,
            ),
            child: list,
          );
  }
}
