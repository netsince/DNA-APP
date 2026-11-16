import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../models/prompt_strategy.dart';
import '../../state/app_controller.dart';
import 'prompt_strategy_advanced_page.dart';
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
  late final TextEditingController _bannedCtrl;

  @override
  void initState() {
    super.initState();
    _strategy = widget.controller.settings.promptStrategy;
    _customMinCtrl =
        TextEditingController(text: _strategy.customMinChars?.toString() ?? '');
    _customMaxCtrl =
        TextEditingController(text: _strategy.customMaxChars?.toString() ?? '');
    _bannedCtrl = TextEditingController(text: _strategy.bannedWords.join('，'));
  }

  @override
  void dispose() {
    _customMinCtrl.dispose();
    _customMaxCtrl.dispose();
    _bannedCtrl.dispose();
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

  /// 禁词支持用中英文逗号、顿号、空格或换行分隔，重复项自动去重。
  Future<void> _saveBannedWords() async {
    final List<String> words = _bannedCtrl.text
        .split(RegExp(r'[,，、\s]+'))
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toSet()
        .toList();
    setState(() {
      _strategy = _strategy.copyWith(bannedWords: words);
    });
    await _saveStrategy();
  }

  /// 内容尺度的一行：名称 + 滑杆 + 当前档位。
  Widget _intensityRow(
    String label,
    String hint,
    IntensityLevel value,
    ValueChanged<IntensityLevel> onChanged,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextTheme ts = theme.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: FitText(
                label,
                style: ts.bodyMedium?.copyWith(fontWeight: AppWeight.medium),
              ),
            ),
            FitText(
              value.label,
              style: ts.bodySmall?.copyWith(color: cs.primary),
            ),
          ],
        ),
        Slider(
          value: value.value.toDouble(),
          min: 0,
          max: 5,
          divisions: 5,
          label: value.label,
          onChanged: (double v) => onChanged(
            IntensityLevel.fromValue(v.round()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: FitText(
            hint,
            style: ts.bodySmall?.copyWith(color: cs.outline),
          ),
        ),
      ],
    );
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
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: AppAlpha.half)),
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
                        style: ts.titleMedium?.copyWith(fontWeight: AppWeight.medium),
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: AppAlpha.a40),
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
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: AppAlpha.half)),
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
                        style: ts.titleMedium?.copyWith(fontWeight: AppWeight.medium),
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: AppAlpha.a40),
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
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: AppAlpha.half)),
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
                        style: ts.titleMedium?.copyWith(fontWeight: AppWeight.medium),
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

          const SizedBox(height: 16),

          // ===== 4. 内容尺度 =====
          // 这是**用户的接受度**，跨角色生效，所以放在全局设置而不是角色卡。
          Card(
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
                      Icon(Icons.shield_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText(
                        '内容尺度',
                        style: ts.titleMedium?.copyWith(
                          fontWeight: AppWeight.medium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '你能接受的上限。超出时 AI 会用留白或暗示带过，而不是硬写。默认不限。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 8),
                  _intensityRow(
                    '冲突与对抗',
                    '角色之间的争执、对抗与张力强度。',
                    _strategy.conflictIntensity,
                    (IntensityLevel v) {
                      setState(() =>
                          _strategy = _strategy.copyWith(conflictIntensity: v));
                      _saveStrategy();
                    },
                  ),
                  _intensityRow(
                    '暴力描写',
                    '打斗、受伤等场面的写实程度。',
                    _strategy.violenceIntensity,
                    (IntensityLevel v) {
                      setState(() =>
                          _strategy = _strategy.copyWith(violenceIntensity: v));
                      _saveStrategy();
                    },
                  ),
                  _intensityRow(
                    '恐怖与惊悚',
                    '压抑感、惊悚氛围与不适感的浓度。',
                    _strategy.horrorIntensity,
                    (IntensityLevel v) {
                      setState(() =>
                          _strategy = _strategy.copyWith(horrorIntensity: v));
                      _saveStrategy();
                    },
                  ),
                  _intensityRow(
                    '亲密描写',
                    '亲密互动的展开程度。',
                    _strategy.intimacyIntensity,
                    (IntensityLevel v) {
                      setState(() =>
                          _strategy = _strategy.copyWith(intimacyIntensity: v));
                      _saveStrategy();
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 5. 用词限制 =====
          // 用户不想看到的表达，跨角色生效。世界的「禁止输出词语」是设定层面，
          // 这里是使用者的阅读偏好，两者互不覆盖。
          Card(
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
                      Icon(Icons.block_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText(
                        '用词限制',
                        style: ts.titleMedium?.copyWith(
                          fontWeight: AppWeight.medium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '不想让 AI 说出口的词。用逗号、顿号或空格分隔，留空表示不限制。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bannedCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '禁止输出词语',
                      hintText: '如：该死，随便，无所谓',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _saveBannedWords(),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _saveBannedWords,
                    child: const FitText('应用'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 6. 高级 =====
          // 三层结构的进阶项都在这一页：预设 / 主轴 / 细项 / 冲突提示 / 预览。
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: AppAlpha.half)),
            ),
            child: ListTile(
              leading: Icon(Icons.tune, color: cs.primary, size: 20),
              title: FitText(
                '高级',
                style: ts.bodyLarge?.copyWith(fontWeight: AppWeight.medium),
              ),
              subtitle: FitText(
                '预设方案、叙事结构、节奏、冲突来源等进阶项',
                style: ts.bodySmall?.copyWith(color: cs.outline),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      PromptStrategyAdvancedPage(controller: widget.controller),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
