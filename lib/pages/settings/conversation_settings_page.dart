import 'package:flutter/material.dart';

import '../../models/prompt_strategy.dart';
import '../../state/app_controller.dart';
import 'quick_replies_page.dart';
import 'package:dna/widgets/fit_text.dart';
import 'regex_rules_page.dart';

class ConversationSettingsPage extends StatefulWidget {
  const ConversationSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ConversationSettingsPage> createState() => _ConversationSettingsPageState();
}

class _ConversationSettingsPageState extends State<ConversationSettingsPage> {
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _wordCtrl;
  late PromptStrategy _strategy;
  bool _autoSummary = true;
  bool _retrySeq = false;
  bool _inspireSummary = false;
  bool _allowDeleteMessage = false;
  late final TextEditingController _ctxCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _stickyCtrl;
  late final TextEditingController _loreMaxEntriesCtrl;
  late final TextEditingController _loreBudgetTokensCtrl;
  late final TextEditingController _customMinCtrl;
  late final TextEditingController _customMaxCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _autoSummary = s.autoSummaryPrompt;
    _summaryCtrl = TextEditingController(text: s.summaryTurnInterval.toString());
    _wordCtrl = TextEditingController(text: s.summaryWordThreshold.toString());
    _retrySeq = s.retrySequential;
    _inspireSummary = s.inspirationIncludeSummary;
    _allowDeleteMessage = s.allowDeleteMessage;
    _strategy = s.promptStrategy;
    _ctxCtrl = TextEditingController(text: s.maxContextMessages.toString());
    _tokenCtrl = TextEditingController(text: s.maxContextTokens.toString());
    _stickyCtrl = TextEditingController(text: s.loreStickyRounds.toString());
    _loreMaxEntriesCtrl = TextEditingController(text: s.loreMaxEntries.toString());
    _loreBudgetTokensCtrl = TextEditingController(text: s.loreBudgetTokens.toString());
    _customMinCtrl = TextEditingController(text: s.promptStrategy.customMinChars?.toString() ?? '');
    _customMaxCtrl = TextEditingController(text: s.promptStrategy.customMaxChars?.toString() ?? '');
  }

  @override
  void dispose() { _summaryCtrl.dispose(); _wordCtrl.dispose(); _ctxCtrl.dispose(); _tokenCtrl.dispose(); _stickyCtrl.dispose(); _loreMaxEntriesCtrl.dispose(); _loreBudgetTokensCtrl.dispose(); _customMinCtrl.dispose(); _customMaxCtrl.dispose(); super.dispose(); }

  Future<void> _saveSummary() async {
    final turns = (int.tryParse(_summaryCtrl.text.trim()) ?? 200).clamp(10, 1000);
    _summaryCtrl.text = turns.toString();
    await widget.controller.saveSummarySettings(autoSummaryPrompt: _autoSummary, summaryTurnInterval: turns);
  }

  Future<void> _saveWord() async {
    final v = (int.tryParse(_wordCtrl.text.trim()) ?? 6000).clamp(0, 1000000);
    _wordCtrl.text = v.toString();
    await widget.controller.saveSummaryWordThreshold(v);
  }

  Future<void> _saveRetry() => widget.controller.saveRetryStrategy(retrySequential: _retrySeq);
  Future<void> _saveInspire() => widget.controller.saveInspirationSettings(includeSummary: _inspireSummary);
  Future<void> _saveStrategy() => widget.controller.savePromptStrategy(_strategy);

  Future<void> _saveCustomRange() async {
    final int? min = int.tryParse(_customMinCtrl.text.trim());
    final int? max = int.tryParse(_customMaxCtrl.text.trim());
    setState(() {
      _strategy = _strategy.copyWith(customMinChars: min, customMaxChars: max);
    });
    await _saveStrategy();
  }

  Future<void> _saveContext() async {
    final int v = (int.tryParse(_ctxCtrl.text.trim()) ?? 120).clamp(0, 1000);
    _ctxCtrl.text = v.toString();
    await widget.controller.saveMaxContextMessages(v);
  }

  Future<void> _saveTokens() async {
    final int v = (int.tryParse(_tokenCtrl.text.trim()) ?? 8000).clamp(0, 100000);
    _tokenCtrl.text = v.toString();
    await widget.controller.saveMaxContextTokens(v);
  }

  Future<void> _saveSticky() async {
    final int v = (int.tryParse(_stickyCtrl.text.trim()) ?? 3).clamp(0, 30);
    _stickyCtrl.text = v.toString();
    await widget.controller.saveLoreStickyRounds(v);
  }

  Future<void> _saveLoreMaxEntries() async {
    final int v = (int.tryParse(_loreMaxEntriesCtrl.text.trim()) ?? 8).clamp(0, 50);
    _loreMaxEntriesCtrl.text = v.toString();
    await widget.controller.saveLoreMaxEntries(v);
  }

  Future<void> _saveLoreBudgetTokens() async {
    final int v = (int.tryParse(_loreBudgetTokensCtrl.text.trim()) ?? 0).clamp(0, 100000);
    _loreBudgetTokensCtrl.text = v.toString();
    await widget.controller.saveLoreBudgetTokens(v);
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
            title: const FitText('打开从此处分叉'),
            subtitle: const FitText('开启后，在聊天页右键对方的气泡会出现「从此处分叉」选项，可把该处之后的内容另起新会话继续。'),
            value: widget.controller.settings.enableForking,
            onChanged: (v) {
              setState(() {});
              widget.controller.saveEnableForking(v);
            },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('命令宏'),
            subtitle: const FitText('启用 {{char}}/{{user}}/{{roll}}/{{random}} 等动态占位符。默认启用。'),
            value: widget.controller.settings.enableCommandMacros,
            onChanged: (v) {
              setState(() {});
              widget.controller.saveEnableCommandMacros(v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('正则替换'),
            subtitle: const FitText('按规则对消息进行正则替换。默认启用。'),
            value: widget.controller.settings.enableRegexReplacement,
            onChanged: (v) {
              setState(() {});
              widget.controller.saveEnableRegexReplacement(v);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.find_replace),
            title: const FitText('正则替换规则'),
            subtitle: FitText('管理正则替换规则（${widget.controller.settings.regexRules.length} 条）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RegexRulesPage(controller: widget.controller),
                ),
              );
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
          const SizedBox(height: 12),
          TextField(
            controller: _wordCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '按词数触发（距上次摘要新增字符数）',
              hintText: '默认 6000，范围 0-1000000，0 表示禁用',
              isDense: true,
            ),
            onChanged: (_) => _saveWord(),
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
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '历史消息 token 预算（精确逐条裁剪）',
              hintText: '默认 8000，范围 0-100000，0 表示不限',
              isDense: true,
            ),
            onChanged: (_) => _saveTokens(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _stickyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '世界词条 sticky 轮数',
              hintText: '默认 3，范围 0-30，0 表示禁用',
              isDense: true,
            ),
            onChanged: (_) => _saveSticky(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _loreMaxEntriesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '世界知识注入条数上限',
              hintText: '默认 8，范围 0-50，0 表示不限',
              isDense: true,
            ),
            onChanged: (_) => _saveLoreMaxEntries(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _loreBudgetTokensCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '世界知识注入 token 预算',
              hintText: '默认 0（不限），超出自动裁剪并告警',
              isDense: true,
            ),
            onChanged: (_) => _saveLoreBudgetTokens(),
          ),
          const Divider(),
          // --- Quick Replies ---
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bolt),
            title: const FitText('快速回复'),
            subtitle: const FitText('管理聊天输入栏上方的一键发送按钮'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      QuickRepliesPage(controller: widget.controller),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
