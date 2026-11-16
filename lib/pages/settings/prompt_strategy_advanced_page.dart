import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../models/prompt_strategy.dart';
import '../../models/strategy_conflicts.dart';
import '../../pages/chat/chat_system_prompt.dart';
import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 设置 → 提示词策略 → 高级。
///
/// 三层结构：预设方案 → 主轴 → 细项。
/// 这里的每一项都是**可选的**：不选就不写进提示词，行为与升级前一致。
/// 角色卡与世界卡可以各自覆盖其中与自己相关的那部分。
class PromptStrategyAdvancedPage extends StatefulWidget {
  const PromptStrategyAdvancedPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<PromptStrategyAdvancedPage> createState() =>
      _PromptStrategyAdvancedPageState();
}

class _PromptStrategyAdvancedPageState
    extends State<PromptStrategyAdvancedPage> {
  late PromptStrategy _strategy;

  final TextEditingController _goalCtrl = TextEditingController();
  final TextEditingController _revealMaxCtrl = TextEditingController();
  final TextEditingController _npcMaxCtrl = TextEditingController();
  final TextEditingController _ambientTimeCtrl = TextEditingController();
  final TextEditingController _ambientWeatherCtrl = TextEditingController();
  final TextEditingController _motifCtrl = TextEditingController();
  final TextEditingController _motifEveryCtrl = TextEditingController();
  final TextEditingController _catchCtrl = TextEditingController();
  final TextEditingController _anchorCtrl = TextEditingController();
  final TextEditingController _voiceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _strategy = widget.controller.settings.promptStrategy;
    final StrategyDetails d = _strategy.details;
    _goalCtrl.text = d.structureGoal ?? '';
    _revealMaxCtrl.text = d.revealMaxPerTurn?.toString() ?? '';
    _npcMaxCtrl.text = d.npcMax?.toString() ?? '';
    _ambientTimeCtrl.text = d.ambientTime ?? '';
    _ambientWeatherCtrl.text = d.ambientWeather ?? '';
    _motifCtrl.text = d.motifName ?? '';
    _motifEveryCtrl.text = d.motifEveryN?.toString() ?? '';
    _catchCtrl.text = (d.catchphrases ?? const <String>[]).join('，');
    _anchorCtrl.text = (d.anchorTraits ?? const <String>[]).join('，');
    _voiceCtrl.text = d.anchorVoiceSample ?? '';
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _goalCtrl,
      _revealMaxCtrl,
      _npcMaxCtrl,
      _ambientTimeCtrl,
      _ambientWeatherCtrl,
      _motifCtrl,
      _motifEveryCtrl,
      _catchCtrl,
      _anchorCtrl,
      _voiceCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  StrategyDetails get _d => _strategy.details;

  void _updateDetails(StrategyDetails next) {
    setState(() => _strategy = _strategy.copyWith(details: next));
    widget.controller.savePromptStrategy(_strategy);
  }

  void _applyPreset(StrategyPreset? preset) {
    setState(() {
      _strategy = preset == null
          ? _strategy.copyWith(details: const StrategyDetails())
          : applyPreset(_strategy, preset);
    });
    _syncFields();
    widget.controller.savePromptStrategy(_strategy);
  }

  /// 预设或清除之后，把文本框内容同步回当前状态。
  void _syncFields() {
    final StrategyDetails d = _strategy.details;
    _goalCtrl.text = d.structureGoal ?? '';
    _revealMaxCtrl.text = d.revealMaxPerTurn?.toString() ?? '';
    _npcMaxCtrl.text = d.npcMax?.toString() ?? '';
    _ambientTimeCtrl.text = d.ambientTime ?? '';
    _ambientWeatherCtrl.text = d.ambientWeather ?? '';
    _motifCtrl.text = d.motifName ?? '';
    _motifEveryCtrl.text = d.motifEveryN?.toString() ?? '';
    _catchCtrl.text = (d.catchphrases ?? const <String>[]).join('，');
    _anchorCtrl.text = (d.anchorTraits ?? const <String>[]).join('，');
    _voiceCtrl.text = d.anchorVoiceSample ?? '';
  }

  List<String> _split(String raw) {
    return raw
        .split(RegExp(r'[,，、\s]+'))
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  int? _parseInt(String raw) {
    final String t = raw.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  String? _parseText(String raw) {
    final String t = raw.trim();
    return t.isEmpty ? null : t;
  }

  /// 提示词预览。
  ///
  /// 一段**长文本只读预览**：按审计 3.2 从 dialog 换成大号 sheet（占屏 85%）。
  /// dialog 装长文的毛病是内容一多就自己变成滚动区、还挤在屏幕中间一块小方框里；
  /// sheet 既保留了上下文，又能真正读完整段提示词。
  /// 正文仍限宽 560，避免宽窗口下行长拉到不可读。
  void _showPreview() {
    final String text = ChatSystemPrompt.previewStrategy(_strategy);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.md,
                  ),
                  child: FitText('提示词预览', style: theme.textTheme.titleLarge),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      0,
                      AppSpacing.xl,
                      AppSpacing.lg,
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: SelectableText(
                          text,
                          // 字号与行高一律走主题令牌（font_scale 结构约束）。
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: Row(
                    children: <Widget>[
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const FitText('关闭'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> conflicts = strategyConflicts(_strategy);

    return Scaffold(
      appBar: AppBar(
        title: const FitText('高级'),
        actions: <Widget>[
          IconButton(
            tooltip: '提示词预览',
            icon: const Icon(Icons.description_outlined),
            onPressed: _showPreview,
          ),
        ],
      ),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          if (conflicts.isNotEmpty) ...<Widget>[
            _ConflictCard(conflicts: conflicts),
            AppSpacing.hLg,
          ],
          _Section(
            icon: Icons.auto_awesome_outlined,
            title: '预设方案',
            description: '一次配好整组细节项；不点就一直保持未设置。',
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const FitText('清除'),
                    selected: _d.isEmpty,
                    onSelected: (bool v) {
                      if (v) _applyPreset(null);
                    },
                  ),
                  for (final StrategyPreset preset in StrategyPreset.values)
                    ChoiceChip(
                      label: FitText(preset.label),
                      selected: false,
                      onSelected: (bool v) {
                        if (v) _applyPreset(preset);
                      },
                    ),
                ],
              ),
            ],
          ),
          AppSpacing.hLg,
          _Section(
            icon: Icons.visibility_outlined,
            title: '视角与人称',
            description: '故事由谁来看、用什么人称讲。',
            children: <Widget>[
              _enumRow<Pov>(
                values: Pov.values,
                selected: _d.pov,
                labelOf: (Pov v) => v.label,
                onChanged: (Pov? v) => _updateDetails(_d.copyWith(pov: v)),
              ),
            ],
          ),
          AppSpacing.hLg,
          _Section(
            icon: Icons.menu_book_outlined,
            title: '叙事结构',
            description: '故事按什么架子排；「本段目标」写一句就够。',
            children: <Widget>[
              _enumRow<NarrativeStructure>(
                values: NarrativeStructure.values,
                selected: _d.narrativeStructure,
                labelOf: (NarrativeStructure v) => v.label,
                onChanged: (NarrativeStructure? v) =>
                    _updateDetails(_d.copyWith(narrativeStructure: v)),
              ),
              AppSpacing.hSm,
              TextField(
                controller: _goalCtrl,
                decoration: const InputDecoration(
                  labelText: '本段目标（可选）',
                  hintText: '如：让两人第一次正面交锋',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (String v) =>
                    _updateDetails(_d.copyWith(structureGoal: _parseText(v))),
              ),
            ],
          ),
          AppSpacing.hLg,
          _Section(
            icon: Icons.timeline_outlined,
            title: '节奏与张力',
            description: '事件推进的快慢，以及紧张感怎么起伏。',
            children: <Widget>[
              _enumRow<Pacing>(
                values: Pacing.values,
                selected: _d.pacing,
                labelOf: (Pacing v) => v.label,
                onChanged: (Pacing? v) =>
                    _updateDetails(_d.copyWith(pacing: v)),
              ),
              AppSpacing.hSm,
              _enumRow<TensionCurve>(
                values: TensionCurve.values,
                selected: _d.tensionCurve,
                labelOf: (TensionCurve v) => v.label,
                onChanged: (TensionCurve? v) =>
                    _updateDetails(_d.copyWith(tensionCurve: v)),
              ),
            ],
          ),
          AppSpacing.hLg,
          _Section(
            icon: Icons.unfold_more_outlined,
            title: '信息揭示',
            description: '底细什么时候给、一次给多少。',
            children: <Widget>[
              _enumRow<Reveal>(
                values: Reveal.values,
                selected: _d.reveal,
                labelOf: (Reveal v) => v.label,
                onChanged: (Reveal? v) =>
                    _updateDetails(_d.copyWith(reveal: v)),
              ),
              AppSpacing.hSm,
              TextField(
                controller: _revealMaxCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '每轮最多揭示几条（留空不限制）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (String v) => _updateDetails(
                  _d.copyWith(revealMaxPerTurn: _parseInt(v)),
                ),
              ),
            ],
          ),
          AppSpacing.hLg,
          _Section(
            icon: Icons.flash_on_outlined,
            title: '冲突来源',
            description: '「有冲突」不够，得知道冲突从哪来。',
            children: <Widget>[
              _enumRow<ConflictSource>(
                values: ConflictSource.values,
                selected: _d.conflictPrimary,
                labelOf: (ConflictSource v) => v.label,
                onChanged: (ConflictSource? v) =>
                    _updateDetails(_d.copyWith(conflictPrimary: v)),
              ),
              AppSpacing.hSm,
              _enumRow<ConflictSource>(
                values: ConflictSource.values,
                selected: _d.conflictSecondary,
                labelOf: (ConflictSource v) => '次要：${v.label}',
                onChanged: (ConflictSource? v) =>
                    _updateDetails(_d.copyWith(conflictSecondary: v)),
              ),
            ],
          ),
          AppSpacing.hLg,
          _FoldSection(
            icon: Icons.flag_outlined,
            title: '结局收束',
            description: '这一段怎么落地、要不要留钩子。',
            children: <Widget>[
              _enumRow<EndingStyle>(
                values: EndingStyle.values,
                selected: _d.endingStyle,
                labelOf: (EndingStyle v) => v.label,
                onChanged: (EndingStyle? v) =>
                    _updateDetails(_d.copyWith(endingStyle: v)),
              ),
              _TriSwitchRow(
                title: '结尾留钩子',
                value: _d.closureHook,
                onChanged: (bool? v) =>
                    _updateDetails(_d.copyWith(closureHook: v)),
              ),
            ],
          ),
          AppSpacing.hLg,
          _FoldSection(
            icon: Icons.landscape_outlined,
            title: '环境设定',
            description: '场景的时间、天气，以及要不要写环境。',
            children: <Widget>[
              _TriSwitchRow(
                title: '主动描写环境',
                value: _d.ambientEnabled,
                onChanged: (bool? v) =>
                    _updateDetails(_d.copyWith(ambientEnabled: v)),
              ),
              AppSpacing.hXs,
              TextField(
                controller: _ambientTimeCtrl,
                decoration: const InputDecoration(
                  labelText: '时间（可选）',
                  hintText: '如：深夜、黄昏',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (String v) =>
                    _updateDetails(_d.copyWith(ambientTime: _parseText(v))),
              ),
              AppSpacing.hXs,
              TextField(
                controller: _ambientWeatherCtrl,
                decoration: const InputDecoration(
                  labelText: '天气（可选）',
                  hintText: '如：细雨、闷热',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (String v) => _updateDetails(
                  _d.copyWith(ambientWeather: _parseText(v)),
                ),
              ),
            ],
          ),
          AppSpacing.hLg,
          _FoldSection(
            icon: Icons.groups_outlined,
            title: '配角与调度',
            description: '同场能有几个配角，以及能不能由 AI 代演。',
            children: <Widget>[
              TextField(
                controller: _npcMaxCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '同场最多几个配角（留空不限制）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (String v) =>
                    _updateDetails(_d.copyWith(npcMax: _parseInt(v))),
              ),
              _TriSwitchRow(
                title: 'AI 可以代演配角',
                value: _d.aiPlaysNpc,
                onChanged: (bool? v) =>
                    _updateDetails(_d.copyWith(aiPlaysNpc: v)),
              ),
            ],
          ),
          AppSpacing.hLg,
          _FoldSection(
            icon: Icons.text_fields_outlined,
            title: '文风与句式',
            description: '句子长短、比喻密度、幽默与对白占比。',
            children: <Widget>[
              _LevelRow(
                label: '句长（1 短 → 5 长）',
                selected: _d.sentenceLength,
                onChanged: (int? v) =>
                    _updateDetails(_d.copyWith(sentenceLength: v)),
              ),
              _LevelRow(
                label: '每段比喻数',
                selected: _d.metaphorPerParagraph,
                onChanged: (int? v) =>
                    _updateDetails(_d.copyWith(metaphorPerParagraph: v)),
              ),
              _LevelRow(
                label: '幽默度',
                selected: _d.humorLevel,
                onChanged: (int? v) =>
                    _updateDetails(_d.copyWith(humorLevel: v)),
              ),
              _LevelRow(
                label: '对白占比（每档 +20%）',
                selected: _d.dialogueRatio == null
                    ? null
                    : (_d.dialogueRatio! / 20).round(),
                onChanged: (int? v) => _updateDetails(
                  _d.copyWith(dialogueRatio: v == null ? null : v * 20),
                ),
              ),
            ],
          ),
          AppSpacing.hLg,
          _FoldSection(
            icon: Icons.record_voice_over_outlined,
            title: '角色口吻',
            description: '称呼、口头禅与必须守住的特质。',
            children: <Widget>[
              _enumRow<EmotionTone>(
                values: EmotionTone.values,
                selected: _d.emotionTone,
                labelOf: (EmotionTone v) => v.label,
                onChanged: (EmotionTone? v) =>
                    _updateDetails(_d.copyWith(emotionTone: v)),
              ),
              _LevelRow(
                label: '情绪强度',
                selected: _d.emotionIntensity,
                onChanged: (int? v) =>
                    _updateDetails(_d.copyWith(emotionIntensity: v)),
              ),
              _enumRow<AddressMode>(
                values: AddressMode.values,
                selected: _d.addressMode,
                labelOf: (AddressMode v) => v.label,
                onChanged: (AddressMode? v) =>
                    _updateDetails(_d.copyWith(addressMode: v)),
              ),
              AppSpacing.hXs,
              TextField(
                controller: _voiceCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '口吻样本（可选）',
                  hintText: '一句它平时会说的话',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (String v) => _updateDetails(
                  _d.copyWith(anchorVoiceSample: _parseText(v)),
                ),
              ),
              AppSpacing.hXs,
              TextField(
                controller: _catchCtrl,
                decoration: const InputDecoration(
                  labelText: '口头禅（逗号分隔，留空不设置）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (String v) => _updateDetails(
                  _d.copyWith(
                    catchphrases: _split(v).isEmpty ? null : _split(v),
                  ),
                ),
              ),
              AppSpacing.hXs,
              TextField(
                controller: _anchorCtrl,
                decoration: const InputDecoration(
                  labelText: '必须守住的特质（逗号分隔）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (String v) => _updateDetails(
                  _d.copyWith(
                    anchorTraits: _split(v).isEmpty ? null : _split(v),
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.hLg,
          _FoldSection(
            icon: Icons.spa_outlined,
            title: '意象母题',
            description: '反复出现的意象，用来做暗线。',
            children: <Widget>[
              TextField(
                controller: _motifCtrl,
                decoration: const InputDecoration(
                  labelText: '母题（可选）',
                  hintText: '如：雨、钟表、旧照片',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (String v) =>
                    _updateDetails(_d.copyWith(motifName: _parseText(v))),
              ),
              AppSpacing.hXs,
              TextField(
                controller: _motifEveryCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '大约每几段出现一次（留空不限制）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (String v) =>
                    _updateDetails(_d.copyWith(motifEveryN: _parseInt(v))),
              ),
            ],
          ),
          AppSpacing.hLg,
          FilledButton.tonalIcon(
            onPressed: _showPreview,
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const FitText('预览最终提示词'),
          ),
          AppSpacing.hLg,        ],
      ),
    );
  }

  Widget _enumRow<T extends Enum>({
    required List<T> values,
    required T? selected,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        ChoiceChip(
          label: const FitText('未设置'),
          selected: selected == null,
          onSelected: (bool v) {
            if (v) onChanged(null);
          },
        ),
        for (final T v in values)
          ChoiceChip(
            label: FitText(labelOf(v)),
            selected: selected == v,
            onSelected: (bool s) {
              if (s) onChanged(v);
            },
          ),
      ],
    );
  }
}

/// 一块设置卡片：图标 + 标题 + 说明 + 内容。
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextTheme ts = theme.textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: AppAlpha.half)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                FitText(
                  title,
                  style: ts.titleMedium?.copyWith(
                    fontWeight: AppWeight.medium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FitText(
              description,
              style: ts.bodySmall?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 冲突提示：只提示、不阻止。
class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.conflicts});

  final List<String> conflicts;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextTheme ts = theme.textTheme;
    return Card(
      elevation: 0,
      color: cs.errorContainer.withValues(alpha: AppAlpha.a35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.error.withValues(alpha: AppAlpha.a35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.report_outlined, color: cs.error, size: 20),
                const SizedBox(width: 8),
                FitText(
                  '冲突提示',
                  style: ts.titleSmall?.copyWith(
                    fontWeight: AppWeight.medium,
                    color: cs.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final String line in conflicts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: FitText(
                  '· $line',
                  style: ts.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 折叠的分区：默认收起，展开才看到细项。
class _FoldSection extends StatelessWidget {
  const _FoldSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextTheme ts = theme.textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: AppAlpha.half)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, color: cs.primary, size: 20),
        title: FitText(
          title,
          style: ts.titleMedium?.copyWith(fontWeight: AppWeight.medium),
        ),
        subtitle: FitText(
          description,
          style: ts.bodySmall?.copyWith(color: cs.outline),
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// 三态开关：未设置 / 开 / 关。
///
/// 用「未设置」这一档，是因为这些项的默认语义是「不写进提示词」，
/// 简单开关没法表达「我不管这件事」。
class _TriSwitchRow extends StatelessWidget {
  const _TriSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme ts = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FitText(title, style: ts.bodyMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const FitText('未设置'),
              selected: value == null,
              onSelected: (bool v) {
                if (v) onChanged(null);
              },
            ),
            ChoiceChip(
              label: const FitText('开'),
              selected: value == true,
              onSelected: (bool v) {
                if (v) onChanged(true);
              },
            ),
            ChoiceChip(
              label: const FitText('关'),
              selected: value == false,
              onSelected: (bool v) {
                if (v) onChanged(false);
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// 1–5 档 + 「未设置」。
class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme ts = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FitText(label, style: ts.bodyMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const FitText('未设置'),
                selected: selected == null,
                onSelected: (bool v) {
                  if (v) onChanged(null);
                },
              ),
              for (int i = 1; i <= 5; i++)
                ChoiceChip(
                  label: FitText('$i'),
                  selected: selected == i,
                  onSelected: (bool v) {
                    if (v) onChanged(i);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
