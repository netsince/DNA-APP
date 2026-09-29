// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_collapsible.dart';
import 'package:dna/widgets/setting_section.dart';

/// 高级采样参数设置页。
///
/// 提供常见场景一键预设与专业级参数微调。
///
/// **本次重构**(见 `SETTINGS_AUDIT.md`):
/// * 原来的 `ExpansionTile` 一次展开 3~5 个滑块,粒度太粗 ——
///   现改为每个参数各自独立折叠([CollapsibleDoubleSetting]),
///   收起态只显示「参数名 + 当前值」;
/// * 范围交给滑块边界表达,删掉「默认 0.7」这类描述性文案,
///   默认值移入展开后的 helper;
/// * 手写的 `Card > Padding > Column` 样板换成 [SettingSection];
/// * 两条超长提示(30 字 / 38 字)压到 20 字以内。
class SamplerSettingsPage extends StatefulWidget {
  const SamplerSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SamplerSettingsPage> createState() => _SamplerSettingsPageState();
}

class _SamplerSettingsPageState extends State<SamplerSettingsPage> {
  late double _temperature;
  late double _frequencyPenalty;
  late double _presencePenalty;
  late double _topP;
  late double _topK;
  late double _minP;
  late double _repetitionPenalty;
  late double _repetitionPenaltySlope;

  static const double _defaultTemperature = 0.7;
  static const double _defaultFrequencyPenalty = 0.0;
  static const double _defaultPresencePenalty = 0.0;
  static const double _defaultTopP = 1.0;
  static const double _defaultTopK = 0.0;
  static const double _defaultMinP = 0.0;
  static const double _defaultRepetitionPenalty = 1.0;
  static const double _defaultRepetitionPenaltySlope = 0.0;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _temperature = s.temperature;
    _frequencyPenalty = s.frequencyPenalty;
    _presencePenalty = s.presencePenalty;
    _topP = s.topP;
    _topK = s.topK;
    _minP = s.minP;
    _repetitionPenalty = s.repetitionPenalty;
    _repetitionPenaltySlope = s.repetitionPenaltySlope;
  }

  bool get _isDefault =>
      _temperature == _defaultTemperature &&
      _frequencyPenalty == _defaultFrequencyPenalty &&
      _presencePenalty == _defaultPresencePenalty &&
      _topP == _defaultTopP &&
      _topK == _defaultTopK &&
      _minP == _defaultMinP &&
      _repetitionPenalty == _defaultRepetitionPenalty &&
      _repetitionPenaltySlope == _defaultRepetitionPenaltySlope;

  Future<void> _save() async {
    await widget.controller.saveSampling(
      temperature: _temperature,
      frequencyPenalty: _frequencyPenalty,
      presencePenalty: _presencePenalty,
    );
    await widget.controller.saveAdvancedSampling(
      topP: _topP,
      topK: _topK,
      minP: _minP,
      repetitionPenalty: _repetitionPenalty,
      repetitionPenaltySlope: _repetitionPenaltySlope,
    );
  }

  Future<void> _applyPreset({
    required double temp,
    required double freq,
    required double pres,
    required double topP,
    required double topK,
    required double minP,
    required double rep,
    required double slope,
  }) async {
    setState(() {
      _temperature = temp;
      _frequencyPenalty = freq;
      _presencePenalty = pres;
      _topP = topP;
      _topK = topK;
      _minP = minP;
      _repetitionPenalty = rep;
      _repetitionPenaltySlope = slope;
    });
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: FitText('已应用预设参数'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _reset() async {
    setState(() {
      _temperature = _defaultTemperature;
      _frequencyPenalty = _defaultFrequencyPenalty;
      _presencePenalty = _defaultPresencePenalty;
      _topP = _defaultTopP;
      _topK = _defaultTopK;
      _minP = _defaultMinP;
      _repetitionPenalty = _defaultRepetitionPenalty;
      _repetitionPenaltySlope = _defaultRepetitionPenaltySlope;
    });
    await widget.controller.saveSampling(
      temperature: _temperature,
      frequencyPenalty: _frequencyPenalty,
      presencePenalty: _presencePenalty,
    );
    await widget.controller.resetAdvancedSampling();
  }

  /// 场景预设按钮(参数组合与改动前完全一致)。
  Widget _preset({
    required IconData icon,
    required String label,
    required double temp,
    required double freq,
    required double pres,
    required double topP,
    required double topK,
    required double minP,
    required double rep,
    required double slope,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: AppSize.iconInline),
      label: FitText(label),
      onPressed: () => _applyPreset(
        temp: temp,
        freq: freq,
        pres: pres,
        topP: topP,
        topK: topK,
        minP: minP,
        rep: rep,
        slope: slope,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FitText('采样参数'),
        actions: <Widget>[
          if (!_isDefault)
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              label: const FitText('恢复默认'),
            ),
        ],
      ),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          // ===== 1. 场景预设 =====
          SettingSection(
            icon: Icons.auto_awesome_outlined,
            title: '场景预设',
            description: '套用典型场景参数，下方会同步更新。',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    _preset(
                      icon: Icons.balance,
                      label: '标准平衡',
                      temp: 0.7,
                      freq: 0.0,
                      pres: 0.0,
                      topP: 1.0,
                      topK: 0.0,
                      minP: 0.0,
                      rep: 1.0,
                      slope: 0.0,
                    ),
                    _preset(
                      icon: Icons.psychology,
                      label: '天马行空',
                      temp: 1.05,
                      freq: 0.2,
                      pres: 0.2,
                      topP: 0.95,
                      topK: 40.0,
                      minP: 0.05,
                      rep: 1.05,
                      slope: 0.0,
                    ),
                    _preset(
                      icon: Icons.menu_book,
                      label: '长篇叙事',
                      temp: 0.85,
                      freq: 0.1,
                      pres: 0.15,
                      topP: 0.9,
                      topK: 0.0,
                      minP: 0.0,
                      rep: 1.05,
                      slope: 0.0,
                    ),
                    _preset(
                      icon: Icons.shield_outlined,
                      label: '强力防复读',
                      temp: 0.7,
                      freq: 0.6,
                      pres: 0.4,
                      topP: 0.95,
                      topK: 0.0,
                      minP: 0.0,
                      rep: 1.15,
                      slope: 0.1,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ===== 2. 核心采样参数(每个参数独立折叠) =====
          SettingSection(
            icon: Icons.thermostat_outlined,
            title: '核心采样参数',
            description: '决定回复的随机程度。',
            children: <Widget>[
              CollapsibleDoubleSetting(
                title: '温度 (Temperature)',
                value: _temperature,
                min: 0.0,
                max: 2.0,
                divisions: 40,
                helper: '越低越确定、严谨；越高越发散、富有想象力。默认 0.70。',
                onChanged: (double v) {
                  setState(() => _temperature = v);
                  _save();
                },
              ),
              CollapsibleDoubleSetting(
                title: '频率惩罚 (Frequency Penalty)',
                value: _frequencyPenalty,
                min: 0.0,
                max: 2.0,
                divisions: 40,
                helper: '按词语出现的绝对次数施加惩罚，降低复读倾向。默认 0.00。',
                onChanged: (double v) {
                  setState(() => _frequencyPenalty = v);
                  _save();
                },
              ),
              CollapsibleDoubleSetting(
                title: '存在惩罚 (Presence Penalty)',
                value: _presencePenalty,
                min: 0.0,
                max: 2.0,
                divisions: 40,
                helper: '词语出现过就施加固定惩罚，鼓励引入新话题。默认 0.00。',
                onChanged: (double v) {
                  setState(() => _presencePenalty = v);
                  _save();
                },
              ),
            ],
          ),

          // ===== 3. 进阶核采样与惩罚(每个参数独立折叠) =====
          SettingSection(
            icon: Icons.filter_alt_outlined,
            title: '进阶核采样与惩罚',
            description: '多数模型无需调整。',
            children: <Widget>[
              CollapsibleDoubleSetting(
                title: 'Top-P (核采样)',
                value: _topP,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                helper: '只从累积概率达到 P 的候选词里采样。1.00 表示不截断。默认 1.00。',
                onChanged: (double v) {
                  setState(() => _topP = v);
                  _save();
                },
              ),
              CollapsibleDoubleSetting(
                title: 'Top-K',
                value: _topK,
                min: 0.0,
                max: 100.0,
                divisions: 100,
                decimals: 0,
                zeroLabel: '不限制',
                helper: '只从概率最高的前 K 个候选词里采样。默认 0。',
                onChanged: (double v) {
                  setState(() => _topK = v);
                  _save();
                },
              ),
              CollapsibleDoubleSetting(
                title: 'Min-P',
                value: _minP,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                zeroLabel: '不限制',
                helper: '过滤概率低于「最高概率 × Min-P」的候选词。默认 0.00。',
                onChanged: (double v) {
                  setState(() => _minP = v);
                  _save();
                },
              ),
              CollapsibleDoubleSetting(
                title: '重复惩罚 (Repetition Penalty)',
                value: _repetitionPenalty,
                min: 1.0,
                max: 2.0,
                divisions: 20,
                helper: '直接降低已出现词的生成概率。1.00 为无惩罚，常用 1.05~1.20。',
                onChanged: (double v) {
                  setState(() => _repetitionPenalty = v);
                  _save();
                },
              ),
              CollapsibleDoubleSetting(
                title: '重复惩罚斜率 (Slope)',
                value: _repetitionPenaltySlope,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                decimals: 1,
                zeroLabel: '平权',
                helper: '距离越近的重复词惩罚越重。默认 0.0。',
                onChanged: (double v) {
                  setState(() => _repetitionPenaltySlope = v);
                  _save();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
