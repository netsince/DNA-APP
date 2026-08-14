import 'package:flutter/material.dart';

import '../../models/prompt_strategy.dart';
import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 对话与策略 → 提示词策略
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
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('提示词策略')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FitText('推进策略', style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const FitText('强制推进'),
                selected: _strategy.advance == AdvanceStrategy.forced,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(advance: AdvanceStrategy.forced)); _saveStrategy(); },
              ),
              ChoiceChip(
                label: const FitText('自由发展'),
                selected: _strategy.advance == AdvanceStrategy.free,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(advance: AdvanceStrategy.free)); _saveStrategy(); },
              ),
            ],
          ),
          const SizedBox(height: 12),
          FitText('沉浸策略', style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const FitText('克制'),
                selected: _strategy.immersion == ImmersionStrategy.restrained,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(immersion: ImmersionStrategy.restrained)); _saveStrategy(); },
              ),
              ChoiceChip(
                label: const FitText('更强'),
                selected: _strategy.immersion == ImmersionStrategy.strong,
                onSelected: (s) { setState(() => _strategy = _strategy.copyWith(immersion: ImmersionStrategy.strong)); },
              ),
            ],
          ),
          const SizedBox(height: 12),
          FitText('字数控制', style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const FitText('严格 80-120 字'),
                selected: _strategy.length == LengthStrategy.strict,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.strict)); _saveStrategy(); },
              ),
              ChoiceChip(
                label: const FitText('适中 150-250 字'),
                selected: _strategy.length == LengthStrategy.medium,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.medium)); _saveStrategy(); },
              ),
              ChoiceChip(
                label: const FitText('无限制'),
                selected: _strategy.length == LengthStrategy.unlimited,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.unlimited)); _saveStrategy(); },
              ),
              ChoiceChip(
                label: const FitText('自定义'),
                selected: _strategy.length == LengthStrategy.custom,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.custom)); _saveStrategy(); },
              ),
            ],
          ),
          if (_strategy.length == LengthStrategy.custom) ...[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(child: TextField(
                  controller: _customMinCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '最少字数', isDense: true),
                  onChanged: (_) => _saveCustomRange(),
                )),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: FitText('~')),
                Expanded(child: TextField(
                  controller: _customMaxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '最多字数', isDense: true),
                  onChanged: (_) => _saveCustomRange(),
                )),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
