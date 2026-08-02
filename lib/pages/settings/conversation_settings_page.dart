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
  }

  @override
  void dispose() { _summaryCtrl.dispose(); super.dispose(); }

  Future<void> _saveSummary() async {
    final turns = (int.tryParse(_summaryCtrl.text.trim()) ?? 200).clamp(10, 1000);
    _summaryCtrl.text = turns.toString();
    await widget.controller.saveSummarySettings(autoSummaryPrompt: _autoSummary, summaryTurnInterval: turns);
  }

  Future<void> _saveRetry() => widget.controller.saveRetryStrategy(retrySequential: _retrySeq);
  Future<void> _saveInspire() => widget.controller.saveInspirationSettings(includeSummary: _inspireSummary);
  Future<void> _saveStrategy() => widget.controller.savePromptStrategy(_strategy);

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
        ],
      ),
    );
  }
}
