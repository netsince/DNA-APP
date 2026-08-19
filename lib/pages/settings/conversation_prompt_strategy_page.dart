// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../models/prompt_strategy.dart';
import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 对话与策略 → 提示词策略。
///
/// 控制回复的推进方式、沉浸程度与字数范围。
class PromptStrategyPage extends StatefulWidget {
  const PromptStrategyPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<PromptStrategyPage> createState() => _PromptStrategyPageState();
}

class _PromptStrategyPageState extends State<PromptStrategyPage> {
  late PromptStrategy _strategy;
  late final TextEditingController _customMinCtrl;
  late final TextEditingController _customMaxCtrl;

  @override
  void initState() {
    super.initState();
    _strategy = widget.controller.settings.promptStrategy;
    _customMinCtrl =
        TextEditingController(text: _strategy.customMinChars?.toString() ?? '');
    _customMaxCtrl =
        TextEditingController(text: _strategy.customMaxChars?.toString() ?? '');
  }

  @override
  void dispose() {
    _customMinCtrl.dispose();
    _customMaxCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveStrategy() =>
      widget.controller.savePromptStrategy(_strategy);

  Future<void> _saveCustomRange() async {
    final int? min = int.tryParse(_customMinCtrl.text.trim());
    final int? max = int.tryParse(_customMaxCtrl.text.trim());
    setState(() {
      _strategy = _strategy.copyWith(customMinChars: min, customMaxChars: max);
    });
    await _saveStrategy();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextTheme ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('提示词策略')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 1. 剧情推进策略 =====
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
                      Icon(Icons.trending_up, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText(
                        '剧情推进策略',
                        style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '控制 AI 在回复中是主动抛出新事件，还是以顺应倾听为主。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<AdvanceStrategy>(
                    segments: const <ButtonSegment<AdvanceStrategy>>[
                      ButtonSegment<AdvanceStrategy>(
                        value: AdvanceStrategy.forced,
                        label: FitText('强制推进'),
                      ),
                      ButtonSegment<AdvanceStrategy>(
                        value: AdvanceStrategy.free,
                        label: FitText('自由发展'),
                      ),
                    ],
                    selected: <AdvanceStrategy>{_strategy.advance},
                    onSelectionChanged: (Set<AdvanceStrategy> val) {
                      setState(() => _strategy = _strategy.copyWith(advance: val.first));
                      _saveStrategy();
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FitText(
                      _strategy.advance == AdvanceStrategy.forced
                          ? '强制推进：AI 会在每轮回复中积极引发新事件、抛出行动建议，主动推动剧情走向。'
                          : '自由发展：AI 更多顺应当前话题倾听与回应，不急于展开新冲突，适合轻松闲聊。',
                      style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 2. 沉浸描写策略 =====
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
                      Icon(Icons.theater_comedy_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText(
                        '沉浸描写策略',
                        style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '控制动作、心理活动与环境氛围描写的详略程度。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ImmersionStrategy>(
                    segments: const <ButtonSegment<ImmersionStrategy>>[
                      ButtonSegment<ImmersionStrategy>(
                        value: ImmersionStrategy.restrained,
                        label: FitText('克制描写'),
                      ),
                      ButtonSegment<ImmersionStrategy>(
                        value: ImmersionStrategy.strong,
                        label: FitText('更强沉浸'),
                      ),
                    ],
                    selected: <ImmersionStrategy>{_strategy.immersion},
                    onSelectionChanged: (Set<ImmersionStrategy> val) {
                      setState(() => _strategy = _strategy.copyWith(immersion: val.first));
                      _saveStrategy();
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FitText(
                      _strategy.immersion == ImmersionStrategy.restrained
                          ? '克制描写：以简明对话为主，减少大段动作描写与心理独白。'
                          : '更强沉浸：增加细腻的动作、心理活动与场景细节描写，代入感更强。',
                      style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 3. 字数控制 =====
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
                      Icon(Icons.text_fields_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText(
                        '回复字数控制',
                        style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '要求 AI 每次回复的中文文本长度区间。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      ChoiceChip(
                        label: const FitText('简短 (50-150字)'),
                        selected: _strategy.length == LengthStrategy.strict,
                        onSelected: (bool s) {
                          if (s) {
                            setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.strict));
                            _saveStrategy();
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const FitText('适中 (150-250字)'),
                        selected: _strategy.length == LengthStrategy.medium,
                        onSelected: (bool s) {
                          if (s) {
                            setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.medium));
                            _saveStrategy();
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const FitText('详尽 (250-500字)'),
                        selected: _strategy.length == LengthStrategy.unlimited,
                        onSelected: (bool s) {
                          if (s) {
                            setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.unlimited));
                            _saveStrategy();
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const FitText('自定义范围'),
                        selected: _strategy.length == LengthStrategy.custom,
                        onSelected: (bool s) {
                          if (s) {
                            setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.custom));
                            _saveStrategy();
                          }
                        },
                      ),
                    ],
                  ),
                  if (_strategy.length == LengthStrategy.custom) ...<Widget>[
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _customMinCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '最少字数',
                              hintText: '如 50',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _saveCustomRange(),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: FitText('至'),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _customMaxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '最多字数',
                              hintText: '如 300',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _saveCustomRange(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: _saveCustomRange,
                      child: const FitText('应用自定义字数'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
