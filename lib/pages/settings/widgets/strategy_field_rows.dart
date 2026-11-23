import 'package:flutter/material.dart';

import 'package:dna/widgets/fit_text.dart';

/// 策略设置的可复用行组件。
///
/// 设置页的「高级」、角色卡的「对话策略」、世界卡的「叙事策略」三处共用，
/// 保证同一个选项在三个地方的观感与操作完全一致。

/// 一组单选：包含「未设置」这一档。
class StrategyEnumRow<T extends Enum> extends StatelessWidget {
  const StrategyEnumRow({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.title,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final TextTheme ts = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            FitText(title!, style: ts.bodyMedium),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const FitText('未设置'),
                selected: selected == null,
                onSelected: (bool v) {
                  if (v) onChanged(null);
                },
              ),
              for (final T v in values)
                ChoiceChip(
                  label: FitText(labelOf(v)),
                  selected: selected == v,
                  onSelected: (bool s) {
                    if (s) onChanged(v);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 1–5 档 +「未设置」。
class StrategyLevelRow extends StatelessWidget {
  const StrategyLevelRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onChanged,
    this.max = 5,
  });

  final String title;
  final int? selected;
  final ValueChanged<int?> onChanged;
  final int max;

  @override
  Widget build(BuildContext context) {
    final TextTheme ts = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FitText(title, style: ts.bodyMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const FitText('未设置'),
                selected: selected == null,
                onSelected: (bool v) {
                  if (v) onChanged(null);
                },
              ),
              for (int i = 1; i <= max; i++)
                ChoiceChip(
                  label: FitText('$i'),
                  selected: selected == i,
                  onSelected: (bool v) {
                    if (v) onChanged(i);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 三态开关：未设置 / 开 / 关。
class StrategyTriSwitchRow extends StatelessWidget {
  const StrategyTriSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme ts = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FitText(title, style: ts.bodyMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const FitText('未设置'),
                selected: value == null,
                onSelected: (bool v) {
                  if (v) onChanged(null);
                },
              ),
              ChoiceChip(
                label: const FitText('开'),
                selected: value == true,
                onSelected: (bool v) {
                  if (v) onChanged(true);
                },
              ),
              ChoiceChip(
                label: const FitText('关'),
                selected: value == false,
                onSelected: (bool v) {
                  if (v) onChanged(false);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单行/多行文本项：留空即「未设置」。
class StrategyTextFieldRow extends StatelessWidget {
  const StrategyTextFieldRow({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.numeric = false,
    this.maxLines = 1,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool numeric;
  final int maxLines;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: numeric ? TextInputType.number : null,
        minLines: 1,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}
