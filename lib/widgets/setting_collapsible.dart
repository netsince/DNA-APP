import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'fit_text.dart';

/// 可折叠的数值设置项。
///
/// **信息设计规矩**(见 `SETTINGS_AUDIT.md` 规矩 1):
/// 收起态只显示「名称 + 当前值」一行只读摘要,展开后才出现控件。
///
/// 这样一屏从「看 N 个输入框」变成「看 N 行摘要」,视觉噪音大幅下降;
/// 用户需要改哪一项时再展开,**控件只在需要时占位**。
///
/// 用法:
/// ```dart
/// CollapsibleNumberSetting(
///   title: '按对话轮数触发',
///   unit: '轮',
///   value: _turns,
///   min: 10, max: 1000, step: 10,
///   helper: '对话达到该轮数时自动生成剧情摘要。',
///   onChanged: (v) => setState(() => _turns = v),
/// )
/// ```
class CollapsibleNumberSetting extends StatefulWidget {
  const CollapsibleNumberSetting({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit,
    this.step,
    this.helper,
    this.zeroLabel,
    this.divisions,
  });

  /// 设置项名称。
  final String title;

  /// 当前值。
  final int value;

  /// 取值范围下限。
  final int min;

  /// 取值范围上限。
  final int max;

  /// 值变化回调(已 clamp 到 [min]..[max])。
  final ValueChanged<int> onChanged;

  /// 单位(如「轮」「字」),显示在收起态数值后面。
  final String? unit;

  /// 步进值。为 null 时按范围自动推导。
  final int? step;

  /// 展开后的补充说明(参数含义、默认值等)。
  ///
  /// **规矩 3**:这类信息不应出现在收起态,避免长文案撑高列表。
  final String? helper;

  /// 值为 0 时显示的文案(如「不限」)。为 null 时直接显示 0。
  final String? zeroLabel;

  /// 滑块刻度数。为 null 时按范围自动推导。
  final int? divisions;

  @override
  State<CollapsibleNumberSetting> createState() =>
      _CollapsibleNumberSettingState();
}

class _CollapsibleNumberSettingState extends State<CollapsibleNumberSetting> {
  bool _expanded = false;

  /// 收起态显示的数值文案。
  String get _displayValue {
    if (widget.value == 0 && widget.zeroLabel != null) return widget.zeroLabel!;
    return widget.unit == null
        ? '${widget.value}'
        : '${widget.value} ${widget.unit}';
  }

  int get _divisions {
    if (widget.divisions != null) return widget.divisions!;
    final int span = widget.max - widget.min;
    // 目标:拖动一格大约是 [step],且刻度数不超过 200(避免性能问题)。
    final int step = widget.step ?? (span / 100).ceil().clamp(1, 1 << 30);
    return (span / step).round().clamp(1, 200);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ===== 收起态:名称 + 当前值(整行可点) =====
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: AppRadius.xsAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FitText(widget.title, style: AppTextStyles.body(theme)),
                ),
                AppSpacing.wMd,
                FitText(
                  _displayValue,
                  style: AppTextStyles.body(theme).copyWith(
                    color: cs.primary,
                    fontWeight: AppWeight.medium,
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

        // ===== 展开态:滑块 + 说明 =====
        //
        // 刻意不用 `AnimatedCrossFade`:它会把两个子树**都**建进 widget tree
        // (只做透明度/尺寸动画),导致收起态依然创建 Slider、说明文字等控件 ——
        // 页面上的实例数与"折叠"的初衷相反,长列表下白白付出构建与布局开销。
        // 这里用条件插入:收起时子树根本不存在。
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Slider(
                        value: widget.value
                            .clamp(widget.min, widget.max)
                            .toDouble(),
                        min: widget.min.toDouble(),
                        max: widget.max.toDouble(),
                        divisions: _divisions,
                        label: _displayValue,
                        onChanged: (double v) => setState(() {
                          widget.onChanged(
                              v.round().clamp(widget.min, widget.max));
                        }),
                      ),
                      // 范围边界:用控件的物理位置表达,不需要文字描述范围。
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            FitText('${widget.min}',
                                style: AppTextStyles.tiny(theme)
                                    .copyWith(color: cs.outline)),
                            FitText('${widget.max}',
                                style: AppTextStyles.tiny(theme)
                                    .copyWith(color: cs.outline)),
                          ],
                        ),
                      ),
                      if (widget.helper != null) ...<Widget>[
                        AppSpacing.hSm,
                        FitText(
                          widget.helper!,
                          style: AppTextStyles.caption(theme)
                              .copyWith(color: cs.outline),
                        ),
                      ],
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// 可折叠的浮点数值设置项(如采样温度、Top-P)。
///
/// 与 [CollapsibleNumberSetting] 完全同构,唯一区别是承载 **double** 值:
/// 采样参数(温度 0.0~2.0 等)需要连续小数,Counter 版只支持整数。
///
/// **信息设计规矩**(见 `SETTINGS_AUDIT.md`):
/// * 收起态只显示「名称 + 当前值」,展开才出现滑块;
/// * 范围由滑块边界表达,**不写「默认 0.7」这类描述性文案** ——
///   默认值属于参考信息,放进 [helper];
/// * 显示精度由 [decimals] 控制(如温度 2 位、重复惩罚斜率 1 位)。
///
/// 用法:
/// ```dart
/// CollapsibleDoubleSetting(
///   title: '温度 (Temperature)',
///   value: _temperature,
///   min: 0, max: 2, decimals: 2,
///   helper: '控制回复随机性,默认 0.70。',
///   onChanged: (double v) => setState(() => _temperature = v),
/// )
/// ```
class CollapsibleDoubleSetting extends StatefulWidget {
  const CollapsibleDoubleSetting({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit,
    this.step,
    this.helper,
    this.zeroLabel,
    this.divisions,
    this.decimals = 2,
  });

  /// 设置项名称。
  final String title;

  /// 当前值。
  final double value;

  /// 取值范围下限。
  final double min;

  /// 取值范围上限。
  final double max;

  /// 值变化回调(已 clamp 到 [min]..[max])。
  final ValueChanged<double> onChanged;

  /// 单位(如「轮」「字」),显示在收起态数值后面。
  final String? unit;

  /// 步进值。为 null 时按范围自动推导。
  final double? step;

  /// 展开后的补充说明(参数含义、默认值等)。
  ///
  /// **规矩 3**:这类信息不应出现在收起态,避免长文案撑高列表。
  final String? helper;

  /// 值为 0 时显示的文案(如「关闭」)。为 null 时直接显示 0。
  final String? zeroLabel;

  /// 滑块刻度数。为 null 时按范围自动推导。
  final int? divisions;

  /// 收起态与滑块气泡的显示小数位。
  final int decimals;

  @override
  State<CollapsibleDoubleSetting> createState() =>
      _CollapsibleDoubleSettingState();
}

class _CollapsibleDoubleSettingState extends State<CollapsibleDoubleSetting> {
  bool _expanded = false;

  /// 按 [CollapsibleDoubleSetting.decimals] 格式化数值。
  String _format(double v) => v.toStringAsFixed(widget.decimals);

  /// 收起态显示的数值文案。
  String get _displayValue {
    if (widget.value == 0 && widget.zeroLabel != null) return widget.zeroLabel!;
    return widget.unit == null
        ? _format(widget.value)
        : '${_format(widget.value)} ${widget.unit}';
  }

  int get _divisions {
    if (widget.divisions != null) return widget.divisions!;
    final double span = widget.max - widget.min;
    // 目标:拖动一格大约是 [step],且刻度数不超过 200(避免性能问题)。
    final double step =
        widget.step ?? (span / 100).clamp(1e-9, double.infinity);
    return (span / step).round().clamp(1, 200);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ===== 收起态:名称 + 当前值(整行可点) =====
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: AppRadius.xsAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FitText(widget.title, style: AppTextStyles.body(theme)),
                ),
                AppSpacing.wMd,
                FitText(
                  _displayValue,
                  style: AppTextStyles.body(theme).copyWith(
                    color: cs.primary,
                    fontWeight: AppWeight.medium,
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

        // ===== 展开态:滑块 + 说明 =====
        //
        // 同 CollapsibleNumberSetting:不用 AnimatedCrossFade(它会同时
        // 构建两个子树),改条件插入,收起态不产生任何控件。
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded ? Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Slider(
                  value: widget.value.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  divisions: _divisions,
                  label: _displayValue,
                  onChanged: (double v) => setState(() {
                    widget.onChanged(v.clamp(widget.min, widget.max));
                  }),
                ),
                // 范围边界:用控件的物理位置表达,不需要文字描述范围。
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      FitText(
                        _format(widget.min),
                        style: AppTextStyles.tiny(theme)
                            .copyWith(color: cs.outline),
                      ),
                      FitText(
                        _format(widget.max),
                        style: AppTextStyles.tiny(theme)
                            .copyWith(color: cs.outline),
                      ),
                    ],
                  ),
                ),
                if (widget.helper != null) ...<Widget>[
                  AppSpacing.hSm,
                  FitText(
                    widget.helper!,
                    style: AppTextStyles.caption(theme)
                        .copyWith(color: cs.outline),
                  ),
                ],
              ],
            ),
          )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// 可折叠的文本输入设置项(用于范围过大、不适合滑块的场景)。
///
/// 与 [CollapsibleNumberSetting] 同样是「收起态只读、展开才可编辑」,
/// 区别是编辑控件为文本框 —— 仅用于范围极大或不确定的情况(如 Token 预算)。
class CollapsibleTextSetting extends StatefulWidget {
  const CollapsibleTextSetting({
    super.key,
    required this.title,
    required this.controller,
    required this.onSubmitted,
    this.unit,
    this.helper,
    this.zeroLabel,
    this.clampMin = 0,
    this.clampMax = 100000,
  });

  final String title;
  final TextEditingController controller;

  /// 输入结束(失焦)时回调,传入已解析并 clamp 的整数。
  final ValueChanged<int> onSubmitted;

  final String? unit;
  final String? helper;
  final String? zeroLabel;
  final int clampMin;
  final int clampMax;

  @override
  State<CollapsibleTextSetting> createState() => _CollapsibleTextSettingState();
}

class _CollapsibleTextSettingState extends State<CollapsibleTextSetting> {
  bool _expanded = false;

  String get _displayValue {
    final int v = int.tryParse(widget.controller.text.trim()) ?? 0;
    if (v == 0 && widget.zeroLabel != null) return widget.zeroLabel!;
    return widget.unit == null ? '$v' : '$v ${widget.unit}';
  }

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
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FitText(widget.title, style: AppTextStyles.body(theme)),
                ),
                AppSpacing.wMd,
                FitText(
                  _displayValue,
                  style: AppTextStyles.body(theme).copyWith(
                    color: cs.primary,
                    fontWeight: AppWeight.medium,
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
        // 同 CollapsibleNumberSetting:不用 AnimatedCrossFade(它会同时
        // 构建两个子树),改条件插入,收起态不产生 TextField。
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        controller: widget.controller,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (String raw) {
                          final int v =
                              (int.tryParse(raw.trim()) ?? widget.clampMin)
                                  .clamp(widget.clampMin, widget.clampMax);
                          widget.controller.text = v.toString();
                          widget.onSubmitted(v);
                        },
                        onEditingComplete: () {
                          final int v = (int.tryParse(
                                      widget.controller.text.trim()) ??
                                  widget.clampMin)
                              .clamp(widget.clampMin, widget.clampMax);
                          widget.controller.text = v.toString();
                          widget.onSubmitted(v);
                        },
                      ),
                      if (widget.helper != null) ...<Widget>[
                        AppSpacing.hSm,
                        FitText(
                          widget.helper!,
                          style: AppTextStyles.caption(theme)
                              .copyWith(color: cs.outline),
                        ),
                      ],
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
