import 'package:flutter/material.dart';

import '../../models/prompt_strategy.dart';
import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

class ConversationSettingsPage extends StatefulWidget {
  const ConversationSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ConversationSettingsPage> createState() => _ConversationSettingsPageState();
}

class _ConversationSettingsPageState extends State<ConversationSettingsPage> {
  late final TextEditingController _summaryCtrl;
  late PromptStrategy _strategy;
  bool _autoSummary = true;
  bool _retrySeq = false;
  bool _inspireSummary = false;
  bool _allowDeleteMessage = false;
  late final TextEditingController _ctxCtrl;
  late double _temperature;
  late double _frequencyPenalty;
  late double _presencePenalty;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _autoSummary = s.autoSummaryPrompt;
    _summaryCtrl = TextEditingController(text: s.summaryTurnInterval.toString());
    _retrySeq = s.retrySequential;
    _inspireSummary = s.inspirationIncludeSummary;
    _allowDeleteMessage = s.allowDeleteMessage;
    _strategy = s.promptStrategy;
    _ctxCtrl = TextEditingController(text: s.maxContextMessages.toString());
    _temperature = s.temperature;
    _frequencyPenalty = s.frequencyPenalty;
    _presencePenalty = s.presencePenalty;
  }

  @override
  void dispose() { _summaryCtrl.dispose(); _ctxCtrl.dispose(); super.dispose(); }

  Future<void> _saveSummary() async {
    final turns = (int.tryParse(_summaryCtrl.text.trim()) ?? 200).clamp(10, 1000);
    _summaryCtrl.text = turns.toString();
    await widget.controller.saveSummarySettings(autoSummaryPrompt: _autoSummary, summaryTurnInterval: turns);
  }

  Future<void> _saveRetry() => widget.controller.saveRetryStrategy(retrySequential: _retrySeq);
  Future<void> _saveInspire() => widget.controller.saveInspirationSettings(includeSummary: _inspireSummary);
  Future<void> _saveStrategy() => widget.controller.savePromptStrategy(_strategy);

  Future<void> _saveContext() async {
    final int v = (int.tryParse(_ctxCtrl.text.trim()) ?? 120).clamp(0, 1000);
    _ctxCtrl.text = v.toString();
    await widget.controller.saveMaxContextMessages(v);
  }

  Future<void> _saveSampling() => widget.controller.saveSampling(
        temperature: _temperature,
        frequencyPenalty: _frequencyPenalty,
        presencePenalty: _presencePenalty,
      );

  Widget _buildSamplingSlider(
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged,
  ) {
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
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            FitText(
              value.toStringAsFixed(2),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        Slider(value: value.clamp(0.0, max), max: max, onChanged: onChanged),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('对话与策略')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // --- Prompt strategy ---
          FitText('提示词策略', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          FitText('推进策略', style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: ChoiceChip(
                label: const FitText('强制推进'),
                selected: _strategy.advance == AdvanceStrategy.forced,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(advance: AdvanceStrategy.forced)); _saveStrategy(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: ChoiceChip(
                label: const FitText('自由发展'),
                selected: _strategy.advance == AdvanceStrategy.free,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(advance: AdvanceStrategy.free)); _saveStrategy(); },
              )),
            ],
          ),
          const SizedBox(height: 12),
          FitText('沉浸策略', style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: ChoiceChip(
                label: const FitText('克制'),
                selected: _strategy.immersion == ImmersionStrategy.restrained,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(immersion: ImmersionStrategy.restrained)); _saveStrategy(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: ChoiceChip(
                label: const FitText('更强'),
                selected: _strategy.immersion == ImmersionStrategy.strong,
                onSelected: (s) { setState(() => _strategy = _strategy.copyWith(immersion: ImmersionStrategy.strong)); },
              )),
            ],
          ),
          const SizedBox(height: 12),
          FitText('字数控制', style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: ChoiceChip(
                label: const FitText('严格 80-120 字'),
                selected: _strategy.length == LengthStrategy.strict,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.strict)); _saveStrategy(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: ChoiceChip(
                label: const FitText('无限制'),
                selected: _strategy.length == LengthStrategy.unlimited,
                onSelected: (s) { if (s) setState(() => _strategy = _strategy.copyWith(length: LengthStrategy.unlimited)); _saveStrategy(); },
              )),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          // --- Inspiration ---
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('灵感附带最近摘要'),
            subtitle: const FitText('开启后会在生成灵感时附带最近摘要。默认关闭以节省 token。'),
            value: _inspireSummary,
            onChanged: (v) { setState(() => _inspireSummary = v); _saveInspire(); },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('任意删除对话项'),
            subtitle: const FitText('开启后，在聊天页长按/右键单条消息会显示「删除本条」，仅删除该条消息。'),
            value: _allowDeleteMessage,
            onChanged: (v) {
              setState(() => _allowDeleteMessage = v);
              widget.controller.saveAllowDeleteMessage(v);
            },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('输入框旁显示括号按钮'),
            subtitle: const FitText('在聊天输入框旁显示「（）」按钮，点击在末尾追加括号并把光标置于中间。'),
            value: widget.controller.settings.showParenButton,
            onChanged: (v) {
              setState(() {});
              widget.controller.saveShowParenButton(v);
            },
          ),
          const Divider(),
          // --- Enter key behavior ---
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FitText(
              '回车键行为',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          RadioGroup<String>(
            groupValue: widget.controller.settings.enterToSend ? 'send' : 'newline',
            onChanged: (String? v) {
              if (v == null) return;
              setState(() {});
              widget.controller.saveEnterToSend(v == 'send');
            },
            child: const Column(
              children: <Widget>[
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'send',
                  title: FitText('回车发送，Shift + 回车换行'),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'newline',
                  title: FitText('回车换行，Shift + 回车发送'),
                ),
              ],
            ),
          ),
          const Divider(),
          // --- Summary ---
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('允许自动提示摘要'),
            value: _autoSummary,
            onChanged: (v) { setState(() => _autoSummary = v); _saveSummary(); },
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _summaryCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '触发轮数（按用户消息计）',
              hintText: '默认 200，范围 10-1000',
              isDense: true,
            ),
            onChanged: (_) => _saveSummary(),
          ),
          const Divider(),
          // --- Retry ---
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('多个请求按顺序单次执行'),
            subtitle: const FitText('开启后重说会顺序发送三次请求。关闭则并发请求三次。'),
            value: _retrySeq,
            onChanged: (v) { setState(() => _retrySeq = v); _saveRetry(); },
          ),
          const Divider(),
          // --- Context retention ---
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FitText('上下文保留条数',
                style: ts.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _ctxCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '单次请求最多携带的历史消息条数',
              hintText: '默认 120，范围 0-1000，0 表示不限',
              isDense: true,
            ),
            onChanged: (_) => _saveContext(),
          ),
          const Divider(),
          // --- Sampling ---
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FitText('采样参数（抑制复读）',
                style: ts.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          _buildSamplingSlider('温度', _temperature, 2.0,
              (v) => setState(() => _temperature = v)),
          _buildSamplingSlider('频率惩罚', _frequencyPenalty, 2.0,
              (v) => setState(() => _frequencyPenalty = v)),
          _buildSamplingSlider('存在惩罚', _presencePenalty, 2.0,
              (v) => setState(() => _presencePenalty = v)),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _saveSampling,
              child: const FitText('应用采样参数'),
            ),
          ),
        ],
      ),
    );
  }
}
