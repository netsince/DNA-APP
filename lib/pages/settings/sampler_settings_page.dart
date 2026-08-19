// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 高级采样参数设置页。
///
/// 提供常见场景一键预设与专业级参数微调。
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

  Widget _buildSlider({
    required String label,
    required String description,
    required double value,
    required double max,
    required int? divisions,
    required ValueChanged<double> onChanged,
    double min = 0.0,
    int fractionDigits = 2,
  }) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: FitText(
                  label,
                  style: ts.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: FitText(
                  value.toStringAsFixed(fractionDigits),
                  style: ts.labelMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FitText(
            description,
            style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) {
              onChanged(v);
              _save();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextTheme ts = theme.textTheme;

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: <Widget>[
          // ===== 场景预设卡片 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.auto_awesome, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText(
                        '场景预设',
                        style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '可直接套用典型场景参数，下方滑块会联动更新并支持自由微调。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      ActionChip(
                        avatar: const Icon(Icons.balance, size: 16),
                        label: const FitText('标准平衡'),
                        onPressed: () => _applyPreset(
                          temp: 0.7,
                          freq: 0.0,
                          pres: 0.0,
                          topP: 1.0,
                          topK: 0.0,
                          minP: 0.0,
                          rep: 1.0,
                          slope: 0.0,
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.psychology, size: 16),
                        label: const FitText('天马行空'),
                        onPressed: () => _applyPreset(
                          temp: 1.05,
                          freq: 0.2,
                          pres: 0.2,
                          topP: 0.95,
                          topK: 40.0,
                          minP: 0.05,
                          rep: 1.05,
                          slope: 0.0,
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.menu_book, size: 16),
                        label: const FitText('长篇叙事'),
                        onPressed: () => _applyPreset(
                          temp: 0.85,
                          freq: 0.1,
                          pres: 0.15,
                          topP: 0.9,
                          topK: 0.0,
                          minP: 0.0,
                          rep: 1.05,
                          slope: 0.0,
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.shield_outlined, size: 16),
                        label: const FitText('强力防复读'),
                        onPressed: () => _applyPreset(
                          temp: 0.7,
                          freq: 0.6,
                          pres: 0.4,
                          topP: 0.95,
                          topK: 0.0,
                          minP: 0.0,
                          rep: 1.15,
                          slope: 0.1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 核心采样参数 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText(
                    '核心采样参数',
                    style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildSlider(
                    label: '温度 (Temperature)',
                    description: '控制回复随机性。越低越确定、严谨；越高越发散、富有想象力。默认 0.7。',
                    value: _temperature,
                    max: 2.0,
                    divisions: 40,
                    onChanged: (v) => setState(() => _temperature = v),
                  ),
                  _buildSlider(
                    label: '频率惩罚 (Frequency Penalty)',
                    description: '根据词语在文本中出现的绝对频次施加惩罚，降低复读倾向。默认 0.0。',
                    value: _frequencyPenalty,
                    max: 2.0,
                    divisions: 40,
                    onChanged: (v) => setState(() => _frequencyPenalty = v),
                  ),
                  _buildSlider(
                    label: '存在惩罚 (Presence Penalty)',
                    description: '只要词语出现过即施加固定惩罚，鼓励引入新话题。默认 0.0。',
                    value: _presencePenalty,
                    max: 2.0,
                    divisions: 40,
                    onChanged: (v) => setState(() => _presencePenalty = v),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 进阶采样参数 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText(
                    '进阶核采样与惩罚',
                    style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildSlider(
                    label: 'Top-P (核采样)',
                    description: '仅从累积概率达到 P 的候选词中采样。1.0 表示不截断。默认 1.0。',
                    value: _topP,
                    max: 1.0,
                    divisions: 20,
                    onChanged: (v) => setState(() => _topP = v),
                  ),
                  _buildSlider(
                    label: 'Top-K',
                    description: '仅从概率最高的前 K 个候选词中采样。0 表示不限制。默认 0。',
                    value: _topK,
                    max: 100.0,
                    divisions: 100,
                    fractionDigits: 0,
                    onChanged: (v) => setState(() => _topK = v),
                  ),
                  _buildSlider(
                    label: 'Min-P',
                    description: '过滤概率低于「最高概率 × Min-P」的候选词。0 表示不限制。默认 0.0。',
                    value: _minP,
                    max: 1.0,
                    divisions: 20,
                    onChanged: (v) => setState(() => _minP = v),
                  ),
                  _buildSlider(
                    label: '重复惩罚 (Repetition Penalty)',
                    description: '直接降低已出现词的生成概率。1.0 为无惩罚，通常取 1.05~1.2。默认 1.0。',
                    value: _repetitionPenalty,
                    min: 1.0,
                    max: 2.0,
                    divisions: 20,
                    onChanged: (v) => setState(() => _repetitionPenalty = v),
                  ),
                  _buildSlider(
                    label: '重复惩罚斜率 (Slope)',
                    description: '距离越近的重复词惩罚越重。0 表示平权惩罚。默认 0.0。',
                    value: _repetitionPenaltySlope,
                    max: 10.0,
                    divisions: 20,
                    fractionDigits: 1,
                    onChanged: (v) => setState(() => _repetitionPenaltySlope = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
