// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_collapsible.dart';
import 'package:dna/widgets/setting_section.dart';

/// 模型专属采样参数设置全屏页。
///
/// 拥有与全局采样设置完全对齐的全部场景预设与专业级参数（包含温度、Top-P、Top-K、Min-P、存在惩罚、频率惩罚、重复惩罚等）。
///
/// **本次重构**(见 `SETTINGS_AUDIT.md`):
/// * 9 个滑块从「一张卡里全部平铺(+ Divider)」改为**每个参数独立折叠**,
///   收起态只显示「参数名 + 当前值」;
/// * 范围交给滑块边界表达,删掉「默认 0.70」这类描述性文案;
/// * 手写的 `Card > Padding > Column` 样板换成 [SettingSection];
/// * 与全局采样页的分工**未改动**(设计规范记录的重复问题本轮不处理)。
class ModelSamplerSettingsPage extends StatefulWidget {
  const ModelSamplerSettingsPage({
    super.key,
    required this.initialTemperature,
    required this.initialFrequencyPenalty,
    required this.initialPresencePenalty,
    required this.initialTopP,
    required this.initialTopK,
    required this.initialMinP,
    required this.initialRepetitionPenalty,
    required this.initialRepetitionPenaltySlope,
    required this.initialMaxContextMessages,
    required this.initialMaxContextTokens,
  });

  final double? initialTemperature;
  final double? initialFrequencyPenalty;
  final double? initialPresencePenalty;
  final double? initialTopP;
  final double? initialTopK;
  final double? initialMinP;
  final double? initialRepetitionPenalty;
  final double? initialRepetitionPenaltySlope;
  final int? initialMaxContextMessages;
  final int? initialMaxContextTokens;

  @override
  State<ModelSamplerSettingsPage> createState() =>
      _ModelSamplerSettingsPageState();
}

class _ModelSamplerSettingsPageState extends State<ModelSamplerSettingsPage> {
  late double _temperature;
  late double _frequencyPenalty;
  late double _presencePenalty;
  late double _topP;
  late double _topK;
  late double _minP;
  late double _repetitionPenalty;
  late double _repetitionPenaltySlope;
  late int _maxContextMessages;
  late int _maxContextTokens;

  static const double _defaultTemperature = 0.7;
  static const double _defaultFrequencyPenalty = 0.0;
  static const double _defaultPresencePenalty = 0.0;
  static const double _defaultTopP = 1.0;
  static const double _defaultTopK = 0.0;
  static const double _defaultMinP = 0.0;
  static const double _defaultRepetitionPenalty = 1.0;
  static const double _defaultRepetitionPenaltySlope = 0.0;
  static const int _defaultMaxContextMessages = 120;
  static const int _defaultMaxContextTokens = 8000;

  @override
  void initState() {
    super.initState();
    _temperature = widget.initialTemperature ?? _defaultTemperature;
    _frequencyPenalty =
        widget.initialFrequencyPenalty ?? _defaultFrequencyPenalty;
    _presencePenalty = widget.initialPresencePenalty ?? _defaultPresencePenalty;
    _topP = widget.initialTopP ?? _defaultTopP;
    _topK = widget.initialTopK ?? _defaultTopK;
    _minP = widget.initialMinP ?? _defaultMinP;
    _repetitionPenalty =
        widget.initialRepetitionPenalty ?? _defaultRepetitionPenalty;
    _repetitionPenaltySlope =
        widget.initialRepetitionPenaltySlope ?? _defaultRepetitionPenaltySlope;
    _maxContextMessages =
        widget.initialMaxContextMessages ?? _defaultMaxContextMessages;
    _maxContextTokens =
        widget.initialMaxContextTokens ?? _defaultMaxContextTokens;
  }

  void _applyPreset({
    required double temp,
    required double freq,
    required double pres,
    required double topP,
    required double topK,
    required double minP,
    required double rep,
    required double slope,
  }) {
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: FitText('已应用预设参数'),
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  void _resetToDefault() {
    setState(() {
      _temperature = _defaultTemperature;
      _frequencyPenalty = _defaultFrequencyPenalty;
      _presencePenalty = _defaultPresencePenalty;
      _topP = _defaultTopP;
      _topK = _defaultTopK;
      _minP = _defaultMinP;
      _repetitionPenalty = _defaultRepetitionPenalty;
      _repetitionPenaltySlope = _defaultRepetitionPenaltySlope;
      _maxContextMessages = _defaultMaxContextMessages;
      _maxContextTokens = _defaultMaxContextTokens;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: FitText('已恢复默认参数'),
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  void _saveAndExit() {
    Navigator.of(context).pop(<String, dynamic>{
      'temperature': _temperature,
      'frequencyPenalty': _frequencyPenalty,
      'presencePenalty': _presencePenalty,
      'topP': _topP,
      'topK': _topK,
      'minP': _minP,
      'repetitionPenalty': _repetitionPenalty,
      'repetitionPenaltySlope': _repetitionPenaltySlope,
      'maxContextMessages': _maxContextMessages,
      'maxContextTokens': _maxContextTokens,
    });
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
        title: const FitText('模型专属采样微调'),
        actions: <Widget>[
          TextButton(
            onPressed: _resetToDefault,
            child: const FitText('重置默认'),
          ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存',
            onPressed: _saveAndExit,
          ),
        ],
      ),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          // ===== 1. 常见场景一键预设 =====
          SettingSection(
            icon: Icons.auto_awesome_outlined,
            title: '常见场景预设',
            description: '按任务类型一键套用参数组合。',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    _preset(
                      icon: Icons.favorite_border,
                      label: '角色扮演 (沉浸)',
                      temp: 0.85,
                      freq: 0.2,
                      pres: 0.1,
                      topP: 0.95,
                      topK: 40,
                      minP: 0.05,
                      rep: 1.1,
                      slope: 0.2,
                    ),
                    _preset(
                      icon: Icons.brush_outlined,
                      label: '创意写作 (发散)',
                      temp: 1.1,
                      freq: 0.3,
                      pres: 0.2,
                      topP: 0.98,
                      topK: 60,
                      minP: 0.02,
                      rep: 1.15,
                      slope: 0.3,
                    ),
                    _preset(
                      icon: Icons.code,
                      label: '严谨代码 / 逻辑',
                      temp: 0.2,
                      freq: 0.0,
                      pres: 0.0,
                      topP: 0.8,
                      topK: 20,
                      minP: 0.0,
                      rep: 1.0,
                      slope: 0.0,
                    ),
                    _preset(
                      icon: Icons.chat_bubble_outline,
                      label: '日常闲聊 (均衡)',
                      temp: 0.7,
                      freq: 0.0,
                      pres: 0.0,
                      topP: 1.0,
                      topK: 0,
                      minP: 0.0,
                      rep: 1.0,
                      slope: 0.0,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ===== 2. 基础随机性(每个参数独立折叠) =====
          SettingSection(
            icon: Icons.thermostat_outlined,
            title: '基础随机性',
            description: '决定输出有多发散。',
            children: <Widget>[
              CollapsibleDoubleSetting(
                title: '温度 (Temperature)',
                value: _temperature,
                min: 0.0,
                max: 2.0,
                divisions: 40,
                helper: '越低越确定，越高越有创意。默认 0.70。',
                onChanged: (double v) => setState(() => _temperature = v),
              ),
              CollapsibleDoubleSetting(
                title: '核采样 (Top-P)',
                value: _topP,
                min: 0.01,
                max: 1.0,
                divisions: 99,
                helper: '只从累积概率达到 P 的候选词里采样。默认 1.00（全选）。',
                onChanged: (double v) => setState(() => _topP = v),
              ),
              CollapsibleDoubleSetting(
                title: 'Top-K 截断',
                value: _topK,
                min: 0.0,
                max: 100.0,
                divisions: 100,
                decimals: 0,
                zeroLabel: '关闭 (0)',
                helper: '只保留概率最高的 K 个候选词。默认 0。',
                onChanged: (double v) => setState(() => _topK = v),
              ),
              CollapsibleDoubleSetting(
                title: 'Min-P 动态截断',
                value: _minP,
                min: 0.0,
                max: 0.5,
                divisions: 50,
                zeroLabel: '关闭 (0)',
                helper: '只保留概率不低于「最高概率 × Min-P」的词。默认 0。',
                onChanged: (double v) => setState(() => _minP = v),
              ),
            ],
          ),

          // ===== 3. 防复读与惩罚(每个参数独立折叠) =====
          SettingSection(
            icon: Icons.repeat_on_outlined,
            title: '防复读与惩罚',
            description: '抑制重复用词与复读。',
            children: <Widget>[
              CollapsibleDoubleSetting(
                title: '频率惩罚 (Frequency Penalty)',
                value: _frequencyPenalty,
                min: -2.0,
                max: 2.0,
                divisions: 40,
                helper: '按词在文本中出现的频次施加惩罚。越高越不易重复。默认 0.00。',
                onChanged: (double v) => setState(() => _frequencyPenalty = v),
              ),
              CollapsibleDoubleSetting(
                title: '存在惩罚 (Presence Penalty)',
                value: _presencePenalty,
                min: -2.0,
                max: 2.0,
                divisions: 40,
                helper: '词出现过就施加惩罚。越高越倾向引入新话题。默认 0.00。',
                onChanged: (double v) => setState(() => _presencePenalty = v),
              ),
              CollapsibleDoubleSetting(
                title: '重复惩罚 (Repetition Penalty)',
                value: _repetitionPenalty,
                min: 1.0,
                max: 2.0,
                divisions: 50,
                helper: '对已出现词的硬性惩罚。1.00 表示无惩罚。默认 1.00。',
                onChanged: (double v) => setState(() => _repetitionPenalty = v),
              ),
            ],
          ),

          AppSpacing.hXl,

          FilledButton.icon(
            onPressed: _saveAndExit,
            icon: const Icon(Icons.check),
            label: const FitText('完成微调并返回'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            ),
          ),
        ],
      ),
    );
  }
}
