import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 高级采样参数设置页。
///
/// 这些参数默认值即「关闭/中性」，除非清楚其作用，否则建议保持默认。
/// 页面提供一键恢复默认值，避免误改后难以找回。
class SamplerSettingsPage extends StatefulWidget {
  const SamplerSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SamplerSettingsPage> createState() => _SamplerSettingsPageState();
}

class _SamplerSettingsPageState extends State<SamplerSettingsPage> {
  late double _topP;
  late double _topK;
  late double _minP;
  late double _repetitionPenalty;
  late double _repetitionPenaltySlope;

  static const double _defaultTopP = 1.0;
  static const double _defaultTopK = 0.0;
  static const double _defaultMinP = 0.0;
  static const double _defaultRepetitionPenalty = 1.0;
  static const double _defaultRepetitionPenaltySlope = 0.0;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _topP = s.topP;
    _topK = s.topK;
    _minP = s.minP;
    _repetitionPenalty = s.repetitionPenalty;
    _repetitionPenaltySlope = s.repetitionPenaltySlope;
  }

  bool get _isDefault =>
      _topP == _defaultTopP &&
      _topK == _defaultTopK &&
      _minP == _defaultMinP &&
      _repetitionPenalty == _defaultRepetitionPenalty &&
      _repetitionPenaltySlope == _defaultRepetitionPenaltySlope;

  Future<void> _save() => widget.controller.saveAdvancedSampling(
        topP: _topP,
        topK: _topK,
        minP: _minP,
        repetitionPenalty: _repetitionPenalty,
        repetitionPenaltySlope: _repetitionPenaltySlope,
      );

  Future<void> _reset() async {
    setState(() {
      _topP = _defaultTopP;
      _topK = _defaultTopK;
      _minP = _defaultMinP;
      _repetitionPenalty = _defaultRepetitionPenalty;
      _repetitionPenaltySlope = _defaultRepetitionPenaltySlope;
    });
    await widget.controller.resetAdvancedSampling();
  }

  Widget _buildSlider({
    required String label,
    required String description,
    required double value,
    required double max,
    required int? divisions,
    required ValueChanged<double> onChanged,
    required String Function(double) display,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: FitText(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            FitText(display(value),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        FitText(
          description,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        Slider(
          value: value.clamp(0.0, max),
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('高级功能')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: FitText(
                    '以下为采样高级参数。如果不懂就不要瞎改，改错可能影响生成质量。',
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSlider(
            label: 'Top-P（核采样）',
            description: '只从累积概率达到该阈值的词中采样，值越小越保守。1.0 表示关闭。',
            value: _topP,
            max: 1.0,
            divisions: 100,
            display: (v) => v.toStringAsFixed(2),
            onChanged: (v) => setState(() => _topP = v),
          ),
          _buildSlider(
            label: 'Top-K',
            description: '只从概率最高的前 K 个词中采样。0 表示关闭。',
            value: _topK,
            max: 200.0,
            divisions: 200,
            display: (v) => v.toStringAsFixed(0),
            onChanged: (v) => setState(() => _topK = v),
          ),
          _buildSlider(
            label: 'Min-P（最小概率）',
            description: '过滤掉概率低于「最高概率 × 该值」的词。0 表示关闭。',
            value: _minP,
            max: 1.0,
            divisions: 100,
            display: (v) => v.toStringAsFixed(2),
            onChanged: (v) => setState(() => _minP = v),
          ),
          _buildSlider(
            label: '重复惩罚（Repetition Penalty）',
            description: '对重复出现过的词施加惩罚，缓解复读。1.0 表示关闭。',
            value: _repetitionPenalty,
            max: 2.0,
            divisions: 100,
            display: (v) => v.toStringAsFixed(2),
            onChanged: (v) => setState(() => _repetitionPenalty = v),
          ),
          _buildSlider(
            label: '重复惩罚斜率（Penalty Slope）',
            description: '对最近重复词的额外加权，值越大对越靠后的重复惩罚越强。0 表示关闭。',
            value: _repetitionPenaltySlope,
            max: 1.0,
            divisions: 100,
            display: (v) => v.toStringAsFixed(2),
            onChanged: (v) => setState(() => _repetitionPenaltySlope = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isDefault ? null : _reset,
                  icon: const Icon(Icons.restore),
                  label: const FitText('一键恢复默认值'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const FitText('应用采样参数'),
            ),
          ),
          const SizedBox(height: 8),
          FitText(
            '提示：Top-P / Top-K / Min-P 等参数仅在你修改后才会随请求发送，保持默认值不会影响已有行为。不同模型服务商对这些参数的支持程度不一，请以实际模型为准。',
            style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
