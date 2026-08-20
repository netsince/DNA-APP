// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:dna/widgets/fit_text.dart';

/// 模型专属采样参数设置全屏页。
///
/// 拥有与全局采样设置完全对齐的全部场景预设与专业级参数（包含温度、Top-P、Top-K、Min-P、存在惩罚、频率惩罚、重复惩罚等）。
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 常见场景一键预设 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
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
                      FitText('常见场景预设',
                          style: ts.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FitText('一键应用针对不同任务调优的参数组合：',
                      style:
                          ts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      ActionChip(
                        avatar: const Icon(Icons.favorite_border, size: 16),
                        label: const FitText('角色扮演 (沉浸)'),
                        onPressed: () => _applyPreset(
                          temp: 0.85,
                          freq: 0.2,
                          pres: 0.1,
                          topP: 0.95,
                          topK: 40,
                          minP: 0.05,
                          rep: 1.1,
                          slope: 0.2,
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.brush_outlined, size: 16),
                        label: const FitText('创意写作 (发散)'),
                        onPressed: () => _applyPreset(
                          temp: 1.1,
                          freq: 0.3,
                          pres: 0.2,
                          topP: 0.98,
                          topK: 60,
                          minP: 0.02,
                          rep: 1.15,
                          slope: 0.3,
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.code, size: 16),
                        label: const FitText('严谨代码 / 逻辑'),
                        onPressed: () => _applyPreset(
                          temp: 0.2,
                          freq: 0.0,
                          pres: 0.0,
                          topP: 0.8,
                          topK: 20,
                          minP: 0.0,
                          rep: 1.0,
                          slope: 0.0,
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const FitText('日常闲聊 (均衡)'),
                        onPressed: () => _applyPreset(
                          temp: 0.7,
                          freq: 0.0,
                          pres: 0.0,
                          topP: 1.0,
                          topK: 0,
                          minP: 0.0,
                          rep: 1.0,
                          slope: 0.0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 基础随机性参数 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('基础随机性',
                      style: ts.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildSlider(
                    context: context,
                    title: '温度 (Temperature)',
                    value: _temperature,
                    min: 0.0,
                    max: 2.0,
                    divisions: 40,
                    displayValue: _temperature.toStringAsFixed(2),
                    desc: '控制输出随机性。越低越确定，越高越有创意。默认 0.70。',
                    onChanged: (v) => setState(() => _temperature = v),
                  ),
                  const Divider(height: 24),
                  _buildSlider(
                    context: context,
                    title: '核采样 (Top-P)',
                    value: _topP,
                    min: 0.01,
                    max: 1.0,
                    divisions: 99,
                    displayValue: _topP.toStringAsFixed(2),
                    desc: '仅从累积概率达到 P 的候选词中采样。默认 1.00（全选）。',
                    onChanged: (v) => setState(() => _topP = v),
                  ),
                  const Divider(height: 24),
                  _buildSlider(
                    context: context,
                    title: 'Top-K 截断',
                    value: _topK,
                    min: 0.0,
                    max: 100.0,
                    divisions: 100,
                    displayValue: _topK == 0.0 ? '关闭 (0)' : _topK.toInt().toString(),
                    desc: '仅保留概率最高的 K 个候选词。0 表示不启用。默认 0。',
                    onChanged: (v) => setState(() => _topK = v),
                  ),
                  const Divider(height: 24),
                  _buildSlider(
                    context: context,
                    title: 'Min-P 动态截断',
                    value: _minP,
                    min: 0.0,
                    max: 0.5,
                    divisions: 50,
                    displayValue: _minP == 0.0 ? '关闭 (0)' : _minP.toStringAsFixed(2),
                    desc: '仅保留概率不低于最高概率 × Min-P 的词。0 表示不启用。默认 0。',
                    onChanged: (v) => setState(() => _minP = v),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 防复读与惩罚参数 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('防复读与惩罚',
                      style: ts.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildSlider(
                    context: context,
                    title: '频率惩罚 (Frequency Penalty)',
                    value: _frequencyPenalty,
                    min: -2.0,
                    max: 2.0,
                    divisions: 40,
                    displayValue: _frequencyPenalty.toStringAsFixed(2),
                    desc: '根据词在文本中出现的频次施加惩罚。越高越不容易重复用词。默认 0.00。',
                    onChanged: (v) => setState(() => _frequencyPenalty = v),
                  ),
                  const Divider(height: 24),
                  _buildSlider(
                    context: context,
                    title: '存在惩罚 (Presence Penalty)',
                    value: _presencePenalty,
                    min: -2.0,
                    max: 2.0,
                    divisions: 40,
                    displayValue: _presencePenalty.toStringAsFixed(2),
                    desc: '只要词在文本中出现过就施加惩罚。越高越倾向于引入新话题。默认 0.00。',
                    onChanged: (v) => setState(() => _presencePenalty = v),
                  ),
                  const Divider(height: 24),
                  _buildSlider(
                    context: context,
                    title: '重复惩罚 (Repetition Penalty)',
                    value: _repetitionPenalty,
                    min: 1.0,
                    max: 2.0,
                    divisions: 50,
                    displayValue: _repetitionPenalty.toStringAsFixed(2),
                    desc: '除以对数几率的硬性重复惩罚。1.00 表示无惩罚。默认 1.00。',
                    onChanged: (v) => setState(() => _repetitionPenalty = v),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _saveAndExit,
            icon: const Icon(Icons.check),
            label: const FitText('完成微调并返回'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required BuildContext context,
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required String desc,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            FitText(title,
                style: ts.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: FitText(
                displayValue,
                style: ts.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FitText(desc,
            style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
