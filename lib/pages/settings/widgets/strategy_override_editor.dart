import 'package:flutter/material.dart';

import '../../../models/prompt_strategy.dart';
import 'strategy_field_rows.dart';

/// 这些策略项归谁管。
///
/// 角色卡负责「这个人怎么说话」，世界卡负责「这个故事怎么走」；
/// 两边的可选项不重叠，所以用两套固定的字段清单，而不是让调用方随便挑。
enum StrategyScope {
  character,
  world,
}

/// 角色卡 / 世界卡里的策略覆盖编辑器。
///
/// 每一项都可以停在「未设置」——那表示完全继承上一层（世界卡继承全局、
/// 角色卡继承世界卡），而不是「关掉」。
class StrategyOverrideEditor extends StatefulWidget {
  const StrategyOverrideEditor({
    super.key,
    required this.scope,
    required this.value,
    required this.onChanged,
  });

  final StrategyScope scope;
  final StrategyDetails? value;
  final ValueChanged<StrategyDetails?> onChanged;

  @override
  State<StrategyOverrideEditor> createState() => _StrategyOverrideEditorState();
}

class _StrategyOverrideEditorState extends State<StrategyOverrideEditor> {
  final TextEditingController _structureGoal = TextEditingController();
  final TextEditingController _revealMax = TextEditingController();
  final TextEditingController _ambientTime = TextEditingController();
  final TextEditingController _ambientWeather = TextEditingController();
  final TextEditingController _npcMax = TextEditingController();
  final TextEditingController _addressValue = TextEditingController();
  final TextEditingController _catchphrases = TextEditingController();
  final TextEditingController _anchorTraits = TextEditingController();
  final TextEditingController _voiceSample = TextEditingController();
  final TextEditingController _motifName = TextEditingController();
  final TextEditingController _motifEvery = TextEditingController();

  StrategyDetails get _d => widget.value ?? const StrategyDetails();

  @override
  void initState() {
    super.initState();
    _syncTextFields();
  }

  @override
  void didUpdateWidget(covariant StrategyOverrideEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _syncTextFields();
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _structureGoal,
      _revealMax,
      _ambientTime,
      _ambientWeather,
      _npcMax,
      _addressValue,
      _catchphrases,
      _anchorTraits,
      _voiceSample,
      _motifName,
      _motifEvery,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncTextFields() {
    final StrategyDetails d = _d;
    _structureGoal.text = d.structureGoal ?? '';
    _revealMax.text = d.revealMaxPerTurn?.toString() ?? '';
    _ambientTime.text = d.ambientTime ?? '';
    _ambientWeather.text = d.ambientWeather ?? '';
    _npcMax.text = d.npcMax?.toString() ?? '';
    _addressValue.text = d.addressValue ?? '';
    _catchphrases.text = (d.catchphrases ?? const <String>[]).join('，');
    _anchorTraits.text = (d.anchorTraits ?? const <String>[]).join('，');
    _voiceSample.text = d.anchorVoiceSample ?? '';
    _motifName.text = d.motifName ?? '';
    _motifEvery.text = d.motifEveryN?.toString() ?? '';
  }

  void _update(StrategyDetails next) {
    widget.onChanged(next.isEmpty ? null : next);
  }

  List<String> _split(String raw) {
    return raw
        .split(RegExp(r'[,，、\s]+'))
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  int? _parseInt(String raw) {
    final String t = raw.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  String? _parseText(String raw) {
    final String t = raw.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    return widget.scope == StrategyScope.character
        ? _buildCharacter()
        : _buildWorld();
  }

  Widget _buildCharacter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        StrategyEnumRow<Pov>(
          title: '视角与人称',
          values: Pov.values,
          selected: _d.pov,
          labelOf: (Pov v) => v.label,
          onChanged: (Pov? v) => _update(_d.copyWith(pov: v)),
        ),
        StrategyEnumRow<AddressMode>(
          title: '称呼方式',
          values: AddressMode.values,
          selected: _d.addressMode,
          labelOf: (AddressMode v) => v.label,
          onChanged: (AddressMode? v) => _update(_d.copyWith(addressMode: v)),
        ),
        StrategyTextFieldRow(
          controller: _addressValue,
          label: '固定称呼（可选）',
          hint: '如：老师、阿澈',
          onSubmitted: (String v) =>
              _update(_d.copyWith(addressValue: _parseText(v))),
        ),
        StrategyEnumRow<EmotionTone>(
          title: '情绪基调',
          values: EmotionTone.values,
          selected: _d.emotionTone,
          labelOf: (EmotionTone v) => v.label,
          onChanged: (EmotionTone? v) => _update(_d.copyWith(emotionTone: v)),
        ),
        StrategyLevelRow(
          title: '情绪强度',
          selected: _d.emotionIntensity,
          onChanged: (int? v) => _update(_d.copyWith(emotionIntensity: v)),
        ),
        StrategyLevelRow(
          title: '句长（1 短 → 5 长）',
          selected: _d.sentenceLength,
          onChanged: (int? v) => _update(_d.copyWith(sentenceLength: v)),
        ),
        StrategyLevelRow(
          title: '每段比喻数',
          selected: _d.metaphorPerParagraph,
          onChanged: (int? v) =>
              _update(_d.copyWith(metaphorPerParagraph: v)),
        ),
        StrategyLevelRow(
          title: '幽默度',
          selected: _d.humorLevel,
          onChanged: (int? v) => _update(_d.copyWith(humorLevel: v)),
        ),
        StrategyTextFieldRow(
          controller: _catchphrases,
          label: '口头禅（逗号分隔）',
          onSubmitted: (String v) => _update(
            _d.copyWith(
              catchphrases: _split(v).isEmpty ? null : _split(v),
            ),
          ),
        ),
        StrategyTextFieldRow(
          controller: _anchorTraits,
          label: '必须守住的特质（逗号分隔）',
          onSubmitted: (String v) => _update(
            _d.copyWith(
              anchorTraits: _split(v).isEmpty ? null : _split(v),
            ),
          ),
        ),
        StrategyTextFieldRow(
          controller: _voiceSample,
          label: '口吻样本（可选）',
          hint: '一句它平时会说的话',
          maxLines: 3,
          onSubmitted: (String v) =>
              _update(_d.copyWith(anchorVoiceSample: _parseText(v))),
        ),
        StrategyTextFieldRow(
          controller: _motifName,
          label: '意象母题（可选）',
          hint: '如：雨、旧照片',
          onSubmitted: (String v) =>
              _update(_d.copyWith(motifName: _parseText(v))),
        ),
      ],
    );
  }

  Widget _buildWorld() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        StrategyEnumRow<NarrativeStructure>(
          title: '叙事结构',
          values: NarrativeStructure.values,
          selected: _d.narrativeStructure,
          labelOf: (NarrativeStructure v) => v.label,
          onChanged: (NarrativeStructure? v) =>
              _update(_d.copyWith(narrativeStructure: v)),
        ),
        StrategyTextFieldRow(
          controller: _structureGoal,
          label: '本段目标（可选）',
          hint: '如：让两人第一次正面交锋',
          onSubmitted: (String v) =>
              _update(_d.copyWith(structureGoal: _parseText(v))),
        ),
        StrategyEnumRow<Pacing>(
          title: '场景与时序',
          values: Pacing.values,
          selected: _d.pacing,
          labelOf: (Pacing v) => v.label,
          onChanged: (Pacing? v) => _update(_d.copyWith(pacing: v)),
        ),
        StrategyEnumRow<TensionCurve>(
          title: '张力曲线',
          values: TensionCurve.values,
          selected: _d.tensionCurve,
          labelOf: (TensionCurve v) => v.label,
          onChanged: (TensionCurve? v) =>
              _update(_d.copyWith(tensionCurve: v)),
        ),
        StrategyEnumRow<Reveal>(
          title: '信息揭示',
          values: Reveal.values,
          selected: _d.reveal,
          labelOf: (Reveal v) => v.label,
          onChanged: (Reveal? v) => _update(_d.copyWith(reveal: v)),
        ),
        StrategyTextFieldRow(
          controller: _revealMax,
          label: '每轮最多揭示几条（留空不限制）',
          numeric: true,
          onSubmitted: (String v) =>
              _update(_d.copyWith(revealMaxPerTurn: _parseInt(v))),
        ),
        StrategyEnumRow<ConflictSource>(
          title: '冲突来源',
          values: ConflictSource.values,
          selected: _d.conflictPrimary,
          labelOf: (ConflictSource v) => v.label,
          onChanged: (ConflictSource? v) =>
              _update(_d.copyWith(conflictPrimary: v)),
        ),
        StrategyEnumRow<ConflictSource>(
          title: '次要冲突来源',
          values: ConflictSource.values,
          selected: _d.conflictSecondary,
          labelOf: (ConflictSource v) => v.label,
          onChanged: (ConflictSource? v) =>
              _update(_d.copyWith(conflictSecondary: v)),
        ),
        StrategyEnumRow<EndingStyle>(
          title: '结局收束',
          values: EndingStyle.values,
          selected: _d.endingStyle,
          labelOf: (EndingStyle v) => v.label,
          onChanged: (EndingStyle? v) =>
              _update(_d.copyWith(endingStyle: v)),
        ),
        StrategyTriSwitchRow(
          title: '结尾留钩子',
          value: _d.closureHook,
          onChanged: (bool? v) => _update(_d.copyWith(closureHook: v)),
        ),
        StrategyTriSwitchRow(
          title: '主动描写环境',
          value: _d.ambientEnabled,
          onChanged: (bool? v) => _update(_d.copyWith(ambientEnabled: v)),
        ),
        StrategyTextFieldRow(
          controller: _ambientTime,
          label: '时间（可选）',
          hint: '如：深夜、黄昏',
          onSubmitted: (String v) =>
              _update(_d.copyWith(ambientTime: _parseText(v))),
        ),
        StrategyTextFieldRow(
          controller: _ambientWeather,
          label: '天气（可选）',
          hint: '如：细雨、闷热',
          onSubmitted: (String v) =>
              _update(_d.copyWith(ambientWeather: _parseText(v))),
        ),
        StrategyTextFieldRow(
          controller: _npcMax,
          label: '同场最多几个配角（留空不限制）',
          numeric: true,
          onSubmitted: (String v) =>
              _update(_d.copyWith(npcMax: _parseInt(v))),
        ),
        StrategyTriSwitchRow(
          title: 'AI 可以代演配角',
          value: _d.aiPlaysNpc,
          onChanged: (bool? v) => _update(_d.copyWith(aiPlaysNpc: v)),
        ),
      ],
    );
  }
}
