/// 声明 → 界面的唯一渲染器。
///
/// 输入是 [FieldsEntry]（字段树），输出是一个完整的设置页。页面里**没有任何
/// 业务文案和取值逻辑**：标题、说明、范围、单位、读写 key 全在声明里。
///
/// 取值走 AppSettings.toJson() 一次（每帧一次，不是每字段一次），
/// 写值走 [AppController.patchSettings]（或声明上的 writeOverride）。
library;

import 'package:flutter/material.dart';

import '../../../models/app_settings.dart';
import '../../../state/app_controller.dart';
import '../../../theme/tokens.dart';
import '../../../utils/platform_capabilities.dart';
import '../../../widgets/app_content_frame.dart';
import '../../../widgets/fit_text.dart';
import '../../../widgets/setting_collapsible.dart';
import '../../../widgets/setting_section.dart';
import 'settings_spec.dart';

/// 平台能力门槛是否满足。
bool settingsGateOpen(SettingsGate gate) => switch (gate) {
  SettingsGate.always => true,
  SettingsGate.tts => PlatformCapabilities.ttsSupported,
  SettingsGate.biometric => PlatformCapabilities.biometricAuthSupported,
};

/// 整项是否出现。
bool settingsItemVisible(SettingItemSpec item, SettingsRuntime runtime) =>
    settingsGateOpen(item.gate) && (item.visibleWhen?.call(runtime) ?? true);

/// 整项是否可用（出现但可能置灰）。
bool settingsItemEnabled(SettingItemSpec item, SettingsRuntime runtime) =>
    item.enabledWhen?.call(runtime) ?? true;

/// 分组是否出现（组里所有项都不可见时整组不渲染，避免空卡片）。
bool settingsSectionVisible(
  SettingSectionSpec section,
  SettingsRuntime runtime,
) {
  if (section.items.isEmpty) return true;
  return section.items.any(
    (SettingItemSpec item) => settingsItemVisible(item, runtime),
  );
}

/// 由字段声明渲染出的设置页。
class SettingsFieldsPage extends StatelessWidget {
  const SettingsFieldsPage({
    super.key,
    required this.entry,
    required this.controller,
    this.biometricEnrolled = false,
    this.ttsModelsReady,
    this.focusItemId,
  });

  final FieldsEntry entry;
  final AppController controller;

  /// 由调用方异步探测后传入（生物识别是否真的可用）。
  final bool biometricEnrolled;

  /// 由调用方异步探测后传入（端侧 TTS 模型是否就绪）；null = 不关心。
  final bool? ttsModelsReady;

  /// 是否有端侧模型正在下载。

  /// 从搜索跳进来时命中的字段 id：该字段会展开并滚到可见位置。
  final String? focusItemId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: FitText(entry.title)),
      body: ListenableBuilder(
        // 这一页只渲染设置项，只关心设置组：以前订阅整个 controller，
        // 聊天流每吐一个字（会话 upsert → 数据组）都会把设置页重建一次。
        listenable: controller.settingsChanges,
        builder: (BuildContext context, Widget? _) {
          final AppSettings settings = controller.settings;
          final SettingsRuntime runtime = SettingsRuntime(
            settings: settings,
            biometricEnrolled: biometricEnrolled,
            ttsModelsReady: ttsModelsReady,
                );
          // 每帧只序列化一次，向下传同一份快照。
          final Map<String, dynamic> json = settings.toJson();
          final List<Widget> sections = <Widget>[];
          for (final SettingSectionSpec section in entry.sections) {
            if (!settingsSectionVisible(section, runtime)) continue;
            sections.add(
              SettingSection(
                icon: section.icon,
                title: section.title,
                description: section.description,
                trailing: section.trailing,
                children: <Widget>[
                  for (final SettingItemSpec item in section.items)
                    if (settingsItemVisible(item, runtime))
                      _SettingItemView(
                        key: ValueKey<String>(item.id),
                        item: item,
                        controller: controller,
                        runtime: runtime,
                        json: json,
                        focusItemId: focusItemId,
                      ),
                ],
              ),
            );
          }
          return AppContentFrame(
            maxWidth: AppSize.pageMaxWidth,
            child: ListView(padding: AppInsets.page, children: sections),
          );
        },
      ),
    );
  }
}

/// 单条设置项。
///
/// 有状态：数值项在拖动过程中要维护本地草稿值（否则每帧写一次盘），
/// 文本项要持有 TextEditingController。
class _SettingItemView extends StatefulWidget {
  const _SettingItemView({
    super.key,
    required this.item,
    required this.controller,
    required this.runtime,
    required this.json,
    this.focusItemId,
  });

  final SettingItemSpec item;
  final AppController controller;
  final SettingsRuntime runtime;
  final Map<String, dynamic> json;
  final String? focusItemId;

  @override
  State<_SettingItemView> createState() => _SettingItemViewState();
}

class _SettingItemViewState extends State<_SettingItemView> {
  /// 数值项拖动中的草稿值。null = 未在拖动，显示上游真实值。
  num? _draft;

  /// 文本数值项的输入框。
  TextEditingController? _textController;

  /// 是否是搜索命中的那一项。
  bool get _focused => widget.focusItemId == widget.item.id;

  @override
  void initState() {
    super.initState();
    final SettingItemSpec item = widget.item;
    if (item is SettingNumber && item.editor == NumberEditor.textField) {
      _textController = TextEditingController(text: '${_rawValue()}');
    }
    if (_focused) {
      // 搜索命中：滚到该项。放在帧后，等布局完成才有位置可滚。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.2,
          duration: AppMotion.medium,
          curve: AppMotion.standard,
        );
      });
    }
  }

  @override
  void dispose() {
    _textController?.dispose();
    super.dispose();
  }

  Object? _rawValue() {
    final SettingItemSpec item = widget.item;
    if (item is! SettingValueItem) return null;
    return widget.json[item.key];
  }

  Future<void> _write(Object? value) async {
    final SettingItemSpec item = widget.item;
    if (item is! SettingValueItem) return;
    final Future<void> Function(AppController, dynamic)? override =
        item.writeOverride;
    if (override != null) {
      await override(widget.controller, value);
      return;
    }
    await widget.controller.patchSettings(item.key, value);
  }

  @override
  Widget build(BuildContext context) {
    final SettingItemSpec item = widget.item;
    final bool enabled = settingsItemEnabled(item, widget.runtime);
    final Widget body = switch (item) {
      SettingToggle i => _toggle(i, enabled),
      SettingChoice i => _choice(i, enabled),
      SettingInt i => _int(i, enabled),
      SettingDouble i => _double(i, enabled),
      SettingAction i => i.builder(context, widget.controller),
      SettingInfo i => _info(i, enabled),
    };
    if (item.hint == null || _hintIsInline(item)) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[body, SettingHint(item.hint!)],
    );
  }

  /// 折叠数值项的 hint 已经作为「展开态说明」传给控件本身，不再额外画第二行。
  ///
  /// 旧页面里这些说明只在展开后出现；渲染器若无条件补一行 SettingHint，
  /// 同一句话会同时出现在收起态下方和展开态里。
  bool _hintIsInline(SettingItemSpec item) => item is SettingNumber;

  /// 副标题：`subtitleOf` 优先（状态指示型副标题两态切换），否则用常量文案。
  String? _subtitle(SettingItemSpec item) =>
      item.subtitleOf?.call(widget.runtime) ?? item.subtitle;

  // ---- 开关 ----
  Widget _toggle(SettingToggle item, bool enabled) {
    return SettingSwitch(
      title: item.title,
      subtitle: _subtitle(item),
      description: item.inlineNote,
      value: _rawValue() as bool? ?? item.defaultValue,
      enabled: enabled,
      onChanged: (bool v) => _write(v),
    );
  }

  // ---- 枚举 ----
  Widget _choice(SettingChoice<dynamic> item, bool enabled) {
    final dynamic current = _rawValue() ?? item.defaultValue;
    final ThemeData theme = Theme.of(context);
    switch (item.layout) {
      case ChoiceLayout.segmented:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (item.showTitle)
                FitText(item.title, style: AppTextStyles.body(theme)),
              if (_subtitle(item) != null) ...<Widget>[
                AppSpacing.hXs,
                FitText(
                  _subtitle(item)!,
                  style: AppTextStyles.caption(
                    theme,
                  ).copyWith(color: theme.colorScheme.outline),
                ),
              ],
              AppSpacing.hSm,
              SegmentedButton<dynamic>(
                segments: <ButtonSegment<dynamic>>[
                  for (final ChoiceOption<dynamic> o in item.options)
                    ButtonSegment<dynamic>(
                      value: o.value,
                      // SegmentedButton 按**固有宽度**排段，段里没有换行的余地：
                      // 这里必须保留「缩字保单行」，否则大字号下段内换行会把
                      // 整条撑爆（审计 4.3 的换行策略不适用于定宽控件）。
                      label: FitText(o.label, wrapWhenTooNarrow: false),
                      icon: o.icon == null ? null : Icon(o.icon),
                    ),
                ],
                selected: <dynamic>{current},
                showSelectedIcon: false,
                onSelectionChanged: enabled
                    ? (Set<dynamic> v) => _write(v.first)
                    : null,
              ),
            ],
          ),
        );
      case ChoiceLayout.radioList:
        // 组值与回调由 RadioGroup 统一管：RadioListTile 自带的
        // groupValue/onChanged 已是弃用 API（审计 4.4）。禁用态用
        // RadioListTile.enabled 表达，不再靠"回调传 null"。
        return RadioGroup<dynamic>(
          groupValue: current,
          onChanged: (dynamic v) => _write(v),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (item.showTitle && _subtitle(item) != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.md,
                    top: AppSpacing.sm,
                  ),
                  child: FitText(item.title, style: AppTextStyles.body(theme)),
                ),
              for (final ChoiceOption<dynamic> o in item.options)
                RadioListTile<dynamic>(
                  contentPadding: AppInsets.tile,
                  value: o.value,
                  enabled: enabled,
                  title: FitText(o.label),
                  subtitle: o.subtitle == null ? null : FitText(o.subtitle!),
                ),
            ],
          ),
        );
      case ChoiceLayout.dropdown:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: DropdownButtonFormField<dynamic>(
            // 新 API：initialValue 取代废弃的 value；设置变化时页面重建，
            // FormFieldState 会跟随 initialValue 更新显示。
            initialValue: current,
            decoration: InputDecoration(labelText: item.title),
            items: <DropdownMenuItem<dynamic>>[
              for (final ChoiceOption<dynamic> o in item.options)
                DropdownMenuItem<dynamic>(
                  value: o.value,
                  child: FitText(o.label),
                ),
            ],
            onChanged: enabled ? (dynamic v) => _write(v) : null,
          ),
        );
    }
  }

  // ---- 整数 ----
  Widget _int(SettingInt item, bool enabled) {
    final Object? raw = _rawValue();
    final int current =
        _draft?.toInt() ?? (raw is num ? raw.toInt() : item.defaultValue);
    switch (item.editor) {
      case NumberEditor.collapsibleStepper:
        return CollapsibleNumberSetting(
          title: item.title,
          value: current,
          min: item.min,
          max: item.max,
          step: item.step,
          unit: item.unit,
          helper: item.hint ?? _subtitle(item),
          zeroLabel: item.zeroLabel,
          initiallyExpanded: _focused,
          onChanged: (int v) {
            if (!enabled) return;
            setState(() => _draft = v);
            // saveMode 是声明的一部分，必须真的被消费：immediate 就在拖动过程中
            // 逐格落盘（旧页面的行为），onRelease 才等松手。
            if (item.saveMode == SettingsSaveMode.immediate) _write(v);
          },
          onChangeEnd: enabled
              ? (int v) => _commit(() => setState(() => _draft = null), v)
              : null,
        );
      case NumberEditor.slider:
        return CollapsibleSliderSetting(
          title: item.title,
          display: _intLabel(item, current),
          helper: item.hint ?? _subtitle(item),
          initiallyExpanded: _focused,
          value: current.toDouble(),
          min: item.min.toDouble(),
          max: item.max.toDouble(),
          divisions: item.step <= 0
              ? null
              : ((item.max - item.min) / item.step).round().clamp(1, 200),
          onChanged: (double v) {
            if (!enabled) return;
            setState(() => _draft = v.round());
            if (item.saveMode == SettingsSaveMode.immediate) _write(v.round());
          },
          onChangeEnd: enabled
              ? (double v) =>
                    _commit(() => setState(() => _draft = null), v.round())
              : null,
        );
      case NumberEditor.textField:
        return CollapsibleTextSetting(
          title: item.title,
          controller: _textController!,
          helper: item.hint ?? _subtitle(item),
          unit: item.unit,
          zeroLabel: item.zeroLabel,
          clampMin: item.min,
          clampMax: item.max,
          onSubmitted: (int v) {
            if (!enabled) return;
            _write(v);
          },
        );
    }
  }

  // ---- 小数 ----
  Widget _double(SettingDouble item, bool enabled) {
    final Object? raw = _rawValue();
    final double current =
        _draft?.toDouble() ?? (raw is num ? raw.toDouble() : item.defaultValue);
    if (item.editor == NumberEditor.collapsibleStepper) {
      return CollapsibleDoubleSetting(
        title: item.title,
        value: current,
        min: item.min,
        max: item.max,
        step: item.step,
        unit: item.unit,
        helper: item.hint ?? _subtitle(item),
        zeroLabel: item.zeroLabel,
        decimals: item.decimals,
        initiallyExpanded: _focused,
        onChanged: (double v) {
          if (!enabled) return;
          setState(() => _draft = v);
          if (item.saveMode == SettingsSaveMode.immediate) _write(v);
        },
        onChangeEnd: enabled
            ? (double v) => _commit(() => setState(() => _draft = null), v)
            : null,
      );
    }
    return CollapsibleDoubleSetting(
      title: item.title,
      value: current,
      min: item.min,
      max: item.max,
      step: item.step,
      unit: item.unit,
      helper: item.hint ?? _subtitle(item),
      zeroLabel: item.zeroLabel,
      decimals: item.decimals,
      initiallyExpanded: _focused,
      onChanged: (double v) {
        if (!enabled) return;
        setState(() => _draft = v);
        if (item.saveMode == SettingsSaveMode.immediate) _write(v);
      },
      onChangeEnd: enabled
          ? (double v) => _commit(() => setState(() => _draft = null), v)
          : null,
    );
  }

  /// 数值的显示文案：语义化档位优先，其次「0 的特殊文案」，最后「数值 + 单位」。
  ///
  /// **必须在具体类型分支里取 `labelOf`**，不能写 `item is SettingNumber` 再读字段：
  /// 裸写泛型类会「实例化到边界」，`SettingNumber` 被当成 `SettingNumber<num>`，
  /// 于是字段类型变成 `String Function(num)`；而声明里实际存的是
  /// `(int) => String`，协变检查当场抛 TypeError，整页构建失败。
  String _intLabel(SettingInt item, int value) {
    if (item.labelOf != null) return item.labelOf!(value);
    return _plainLabel(item.zeroLabel, item.unit, value);
  }

  String _plainLabel(String? zeroLabel, String? unit, num value) {
    if (value == 0 && zeroLabel != null) return zeroLabel;
    final String text = value is int ? '$value' : value.toStringAsFixed(2);
    return unit == null ? text : '$text $unit';
  }

  /// 先落盘、再清草稿：落盘期间 UI 仍显示草稿值，避免闪回旧值。
  Future<void> _commit(VoidCallback clearDraft, Object? value) async {
    await _write(value);
    if (mounted) clearDraft();
  }

  Widget _info(SettingInfo item, bool enabled) {
    return ListTile(
      enabled: enabled,
      contentPadding: AppInsets.tile,
      title: FitText(item.title),
      subtitle: _subtitle(item) == null ? null : FitText(_subtitle(item)!),
      trailing: FitText(
        item.read(widget.runtime.settings),
        style: AppTextStyles.body(Theme.of(context)),
      ),
    );
  }
}
