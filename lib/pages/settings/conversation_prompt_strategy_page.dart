// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import '../../models/prompt_strategy.dart';
import '../../state/app_controller.dart';
import '../chat/chat_system_prompt.dart';

/// 对话与策略 → 提示词策略（v2 三段式）。
///
/// 第一层：五个预设胶囊，点一下就把所有细项配好；
/// 第二层：六条主轴滑杆（尺度 / 张力 / 关系速度 / 台词占比 / 描写浓度 / 字数）；
/// 第三层：折叠的「高级」，二十余组细项，默认值都能直接用。
/// 底部固定一条「本轮提示」，告诉用户下一句大概该往哪写。
class PromptStrategyPage extends StatefulWidget {
  const PromptStrategyPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<PromptStrategyPage> createState() => _PromptStrategyPageState();
}

class _PromptStrategyPageState extends State<PromptStrategyPage> {
  late PromptStrategy _s;
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  late final TextEditingController _bannedCtrl;
  late final TextEditingController _catchCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _goalCtrl;
  late final TextEditingController _voiceCtrl;
  late final TextEditingController _motifCtrl;
  late final TextEditingController _timeCtrl;
  late final TextEditingController _weatherCtrl;

  @override
  void initState() {
    super.initState();
    _s = widget.controller.settings.promptStrategy;
    _minCtrl = TextEditingController(text: _s.customMinChars?.toString() ?? '');
    _maxCtrl = TextEditingController(text: _s.customMaxChars?.toString() ?? '');
    _bannedCtrl = TextEditingController(text: _s.bannedWords.join('，'));
    _catchCtrl = TextEditingController(text: _s.catchphrases.join('，'));
    _addressCtrl = TextEditingController(text: _s.addressValue);
    _goalCtrl = TextEditingController(text: _s.structureGoal);
    _voiceCtrl = TextEditingController(text: _s.anchorVoiceSample);
    _motifCtrl = TextEditingController(text: _s.motifName);
    _timeCtrl = TextEditingController(text: _s.ambientTime);
    _weatherCtrl = TextEditingController(text: _s.ambientWeather);
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _minCtrl,
      _maxCtrl,
      _bannedCtrl,
      _catchCtrl,
      _addressCtrl,
      _goalCtrl,
      _voiceCtrl,
      _motifCtrl,
      _timeCtrl,
      _weatherCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _apply(PromptStrategy next) async {
    setState(() => _s = next);
    await widget.controller.savePromptStrategy(next);
  }

  void _preview() {
    final String text = ChatSystemPrompt.previewStrategy(_s);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        final ThemeData t = Theme.of(ctx);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (BuildContext ctx, ScrollController sc) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.visibility_outlined, color: t.colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FitText('这一套会拼进系统提示的策略段',
                            style: t.textTheme.titleMedium
                                ?.copyWith(fontWeight: AppWeight.medium)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText('人设、世界背景、对话风格不在这里显示，它们由角色卡与设定决定。',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        controller: sc,
                        child: SelectableText(
                          text.isEmpty ? '（当前都是默认值，不会插入额外策略段）' : text,
                          style: t.textTheme.bodySmall?.copyWith(height: 1.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // —— 小部件 ——

  Widget _card(String title, String subtitle, IconData icon, Widget child) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: FitText(title,
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: AppWeight.medium)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FitText(subtitle, style: t.textTheme.bodySmall?.copyWith(color: cs.outline)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _chips<T>({
    required List<T> values,
    required T current,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
    Map<T, bool Function()>? disabled,
    Map<T, String>? hints,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((T v) {
        final bool off = disabled?[v]?.call() ?? false;
        final String? hint = hints?[v];
        return Tooltip(
          message: off ? (hint ?? '当前设置下不可用') : (hint ?? ''),
          child: ChoiceChip(
            label: FitText(label(v)),
            selected: current == v,
            onSelected: off ? null : (bool sel) {
              if (sel) onChanged(v);
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
    int? divisions,
    String Function(double)? fmt,
    String? hint,
  }) {
    final ThemeData t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: FitText(label, style: t.textTheme.bodyMedium)),
            FitText(fmt?.call(value) ?? value.toStringAsFixed(0),
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.primary)),
          ],
        ),
        Slider(
          value: value,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
        if (hint != null)
          FitText(hint, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
      ],
    );
  }

  Widget _switchRow(String label, String subtitle, bool value, ValueChanged<bool> onChanged) {
    final ThemeData t = Theme.of(context);
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: FitText(label, style: t.textTheme.bodyMedium),
      subtitle: FitText(subtitle, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _textRow(String label, TextEditingController ctrl, String hint,
      ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }

  String _relationshipLabel(RelationshipMode m) => kRelationshipLabels[m]!;

  double get _relationshipSpeed => switch (_s.relationshipMode) {
        RelationshipMode.frozen => 0,
        RelationshipMode.userOnly => 1,
        RelationshipMode.slowburn => 2,
        RelationshipMode.natural => 3,
        RelationshipMode.fast => 4,
      };

  RelationshipMode _speedToMode(double v) => switch (v.round()) {
        0 => RelationshipMode.frozen,
        1 => RelationshipMode.userOnly,
        2 => RelationshipMode.slowburn,
        3 => RelationshipMode.natural,
        _ => RelationshipMode.fast,
      };

  /// 描写浓度 0-100：同时调感官权重与沉浸档位。
  double get _density => _s.senseTotal <= 0
      ? 0
      : (_s.senseTotal / 14 * 100).clamp(0, 100).toDouble();

  PromptStrategy _withDensity(double v) {
    final int level = (v / 100 * 4).round().clamp(0, 4);
    final int s = level; // 0..4 统一缩放
    return _s.copyWith(
      senseVisual: (3 * s / 4).round(),
      senseAudio: (2 * s / 4).round(),
      senseTouch: (2 * s / 4).round(),
      senseSmell: s >= 3 ? 1 : 0,
      senseInteroception: s >= 2 ? 1 : 0,
      senseAmbient: s >= 2 ? 1 : 0,
      immersion: v >= 70
          ? ImmersionStrategy.cinematic
          : (v >= 35 ? ImmersionStrategy.strong : ImmersionStrategy.restrained),
    );
  }

  double get _lengthIndex => switch (_s.length) {
        LengthStrategy.tiny => 0,
        LengthStrategy.strict => 1,
        LengthStrategy.medium => 2,
        LengthStrategy.unlimited => 3,
        LengthStrategy.epic => 4,
        LengthStrategy.custom => 0,
      };

  LengthStrategy _indexToLength(double v) => switch (v.round()) {
        0 => LengthStrategy.tiny,
        1 => LengthStrategy.strict,
        2 => LengthStrategy.medium,
        3 => LengthStrategy.unlimited,
        _ => LengthStrategy.epic,
      };

  String _lengthLabel(LengthStrategy l) => switch (l) {
        LengthStrategy.tiny => '极简 20-50字',
        LengthStrategy.strict => '简短 80-120字',
        LengthStrategy.medium => '适中 150-250字',
        LengthStrategy.unlimited => '详尽 250-500字',
        LengthStrategy.epic => '长篇 600-1200字',
        LengthStrategy.custom => '自定义',
      };

  /// 底部「本轮提示」：按当前组合给一句可执行的话。
  String get _nextTurnTip {
    if (_s.agency == AgencyStrategy.respondOnly) {
      return '下一轮少推剧情，等对方先给方向，你只做细致回应。';
    }
    if (_s.tensionCurve == TensionCurve.suspended) {
      return '下一轮先把上一个钩子挂住，别急着揭晓。';
    }
    if (_s.relationshipMode == RelationshipMode.frozen) {
      return '关系锁在「${kRelationshipStages[_s.relationshipStage.clamp(0, 4)]}」，这一轮只做拉扯的细节。';
    }
    if (_s.reveal == RevealStrategy.layered) {
      return '这一轮放开 ${_s.revealMaxPerTurn} 条新信息，剩下的继续留白。';
    }
    if (_s.humorLevel >= 4) {
      return '这一轮可以抖一个梗，但只从角色嘴里出。';
    }
    return '这一轮让对手主动开口，你给一个有画面的反应。';
  }

  /// 冲突检测：把互斥/打架的组合翻译成人话。
  List<String> get _conflicts {
    final List<String> out = <String>[];
    if (_s.length == LengthStrategy.tiny && _s.dialogueRatio > 60) {
      out.add('「极简 20-50 字」撑不起 ${_s.dialogueRatio}% 的对白，已自动压到 60%。');
    }
    if (_s.pacing == PacingStrategy.montage && _s.length.index < LengthStrategy.medium.index) {
      out.add('蒙太奇剪辑需要空间，建议字数至少「适中」。');
    }
    if (_s.senseTotal > 10) {
      out.add('感官权重总和 ${_s.senseTotal}，超过 10 会写得又乱又腻。');
    }
    if (_s.pov == PovStrategy.followOther && _s.advance == AdvanceStrategy.forced) {
      out.add('「跟随对手视角」天然慢，强制推进已自动降为慢热。');
    }
    if (_s.anchorSelfCheck && _s.length.index < LengthStrategy.medium.index) {
      out.add('收尾自查要占字数，短回复里建议关掉。');
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final ColorScheme cs = t.colorScheme;
    final List<String> conflicts = _conflicts;

    return Scaffold(
      appBar: AppBar(
        title: const FitText('提示词策略'),
        actions: <Widget>[
          IconButton(
            tooltip: '预览最终提示词',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: _preview,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          // ===== 第一层：预设胶囊 =====
          _card(
            '先挑一个手感',
            '一次把所有细项配齐，之后还能在下面单独改。',
            Icons.auto_awesome_outlined,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StrategyPreset.values.map((StrategyPreset p) {
                final bool on = _s.preset == p;
                return ChoiceChip(
                  label: FitText(p.label),
                  selected: on,
                  onSelected: (bool sel) {
                    if (sel) {
                      _apply(_s.applyPreset(p));
                    } else {
                      _apply(_s.copyWith(clearPreset: true));
                    }
                  },
                );
              }).toList(),
            ),
          ),

          // ===== 第二层：六条主轴 =====
          _card(
            '六条主轴',
            '只调这几条就能用；细项在下面的「高级」里。',
            Icons.tune,
            Column(
              children: <Widget>[
                _slider(
                  label: '尺度（冲突/暴力/恐怖/亲密的总体上限）',
                  value: _s.intensityConflict.toDouble(),
                  max: 5,
                  divisions: 5,
                  onChanged: (double v) => _apply(_s.copyWith(
                    intensityConflict: v.round(),
                    intensityViolence: v.round(),
                    intensityHorror: v.round(),
                    intensityIntimacy: v.round(),
                  )),
                  hint: '想单独调某一项，去「高级 → 内容强度」。',
                ),
                _slider(
                  label: '张力强度',
                  value: _s.emotionIntensity.toDouble(),
                  max: 5,
                  divisions: 5,
                  onChanged: (double v) => _apply(_s.copyWith(emotionIntensity: v.round())),
                ),
                _slider(
                  label: '关系速度',
                  value: _relationshipSpeed,
                  max: 4,
                  divisions: 4,
                  fmt: (double v) => _relationshipLabel(_speedToMode(v)),
                  onChanged: (double v) => _apply(_s.copyWith(relationshipMode: _speedToMode(v))),
                ),
                _slider(
                  label: '台词占比',
                  value: _s.dialogueRatio.toDouble(),
                  max: 100,
                  divisions: 20,
                  fmt: (double v) => '${v.round()}%',
                  onChanged: (double v) => _apply(_s.copyWith(dialogueRatio: v.round())),
                ),
                _slider(
                  label: '描写浓度',
                  value: _density,
                  max: 100,
                  divisions: 4,
                  fmt: (double v) => '${(_withDensity(v).senseTotal * 100 ~/ 14)}%',
                  onChanged: (double v) => _apply(_withDensity(v)),
                ),
                _slider(
                  label: '字数',
                  value: _lengthIndex,
                  max: 4,
                  divisions: 4,
                  fmt: (double v) => _lengthLabel(_indexToLength(v)),
                  onChanged: (double v) => _apply(_s.copyWith(length: _indexToLength(v))),
                ),
              ],
            ),
          ),

          if (conflicts.isNotEmpty)
            _card(
              '组合冲突',
              '这些选项会打架，已按能用的方式处理。',
              Icons.warning_amber_outlined,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: conflicts
                    .map((String c) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: FitText('· $c',
                              style: t.textTheme.bodySmall
                                  ?.copyWith(color: cs.error, height: 1.4)),
                        ))
                    .toList(),
              ),
            ),

          // ===== 第三层：高级 =====
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(Icons.settings_suggest_outlined, color: cs.primary, size: 20),
            title: const FitText('高级（二十余组细项）'),
            subtitle: FitText('默认值就能直接用，不懂的可以先不碰。',
                style: t.textTheme.bodySmall?.copyWith(color: cs.outline)),
            children: <Widget>[
              _card(
                '视角与人称',
                '决定「谁在看、谁在说」。',
                Icons.remove_red_eye_outlined,
                _chips<PovStrategy>(
                  values: PovStrategy.values,
                  current: _s.pov,
                  label: (PovStrategy v) => kPovLabels[v]!,
                  onChanged: (PovStrategy v) => _apply(_s.copyWith(pov: v)),
                ),
              ),
              _card(
                '情绪基调',
                '整篇的底色，不是每句话都要体现。',
                Icons.color_lens_outlined,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _chips<EmotionTone>(
                      values: EmotionTone.values,
                      current: _s.emotionTone,
                      label: (EmotionTone v) => kEmotionLabels[v]!,
                      onChanged: (EmotionTone v) => _apply(_s.copyWith(emotionTone: v)),
                    ),
                    const SizedBox(height: 8),
                    _slider(
                      label: '基调强度',
                      value: _s.emotionIntensity.toDouble(),
                      max: 5,
                      divisions: 5,
                      onChanged: (double v) => _apply(_s.copyWith(emotionIntensity: v.round())),
                      hint: '5 才会句句带底色。',
                    ),
                  ],
                ),
              ),
              _card(
                '张力曲线',
                '同样是「有张力」，形状不一样感觉差很多。',
                Icons.show_chart,
                _chips<TensionCurve>(
                  values: TensionCurve.values,
                  current: _s.tensionCurve,
                  label: (TensionCurve v) => kTensionLabels[v]!,
                  onChanged: (TensionCurve v) => _apply(_s.copyWith(tensionCurve: v)),
                ),
              ),
              _card(
                '关系闸门',
                '关系阶段 + 每几轮升一级，防止一上来就黏糊。',
                Icons.favorite_border,
                Column(
                  children: <Widget>[
                    _slider(
                      label: '当前阶段',
                      value: _s.relationshipStage.toDouble(),
                      max: 4,
                      divisions: 4,
                      fmt: (double v) => kRelationshipStages[v.round()],
                      onChanged: (double v) =>
                          _apply(_s.copyWith(relationshipStage: v.round())),
                    ),
                    _slider(
                      label: '推进间隔（轮）',
                      value: _s.relationshipStepEvery.toDouble(),
                      max: 20,
                      divisions: 19,
                      fmt: (double v) => '${v.round()} 轮',
                      onChanged: (double v) =>
                          _apply(_s.copyWith(relationshipStepEvery: v.round())),
                    ),
                    _switchRow(
                      '锁定当前阶段',
                      '打开后无论剧情怎么走都不升温。',
                      _s.relationshipLocked,
                      (bool v) => _apply(_s.copyWith(relationshipLocked: v)),
                    ),
                  ],
                ),
              ),
              _card(
                '称呼系统',
                '中文语境里最强的关系信号。',
                Icons.record_voice_over_outlined,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _chips<AddressMode>(
                      values: AddressMode.values,
                      current: _s.addressMode,
                      label: (AddressMode v) => kAddressLabels[v]!,
                      onChanged: (AddressMode v) => _apply(_s.copyWith(addressMode: v)),
                    ),
                    _textRow('称呼（固定/自定义时生效）', _addressCtrl, '如：指挥官',
                        (String v) => _apply(_s.copyWith(addressValue: v))),
                  ],
                ),
              ),
              _card(
                '硬约束',
                '这一组是「不 OOC」性价比最高的，关键词用逗号分隔。',
                Icons.block_outlined,
                Column(
                  children: <Widget>[
                    _textRow('禁用词（逗号分隔）', _bannedCtrl, '如：宝贝，傻瓜',
                        (String v) => _apply(_s.copyWith(
                              bannedWords: v
                                  .split(RegExp('[,，、\\s]+'))
                                  .where((String x) => x.trim().isNotEmpty)
                                  .toList(),
                            ))),
                    _textRow('口癖白名单（最多 3 个）', _catchCtrl, '如：啧，呵',
                        (String v) => _apply(_s.copyWith(
                              catchphrases: v
                                  .split(RegExp('[,，、\\s]+'))
                                  .where((String x) => x.trim().isNotEmpty)
                                  .toList(),
                            ))),
                    _switchRow(
                      '不得替用户行动',
                      '不写用户的台词、决定与心理（建议一直开）。',
                      _s.noUserAgency,
                      (bool v) => _apply(_s.copyWith(noUserAgency: v)),
                    ),
                  ],
                ),
              ),
              _card(
                '感官通道权重',
                '总和别超过 10，否则又乱又腻。',
                Icons.hearing_outlined,
                Column(
                  children: <Widget>[
                    _slider(
                      label: '视觉',
                      value: _s.senseVisual.toDouble(),
                      max: 3,
                      divisions: 3,
                      onChanged: (double v) => _apply(_s.copyWith(senseVisual: v.round())),
                    ),
                    _slider(
                      label: '听觉',
                      value: _s.senseAudio.toDouble(),
                      max: 3,
                      divisions: 3,
                      onChanged: (double v) => _apply(_s.copyWith(senseAudio: v.round())),
                    ),
                    _slider(
                      label: '触觉',
                      value: _s.senseTouch.toDouble(),
                      max: 3,
                      divisions: 3,
                      onChanged: (double v) => _apply(_s.copyWith(senseTouch: v.round())),
                    ),
                    _slider(
                      label: '嗅觉 / 味觉',
                      value: _s.senseSmell.toDouble(),
                      max: 3,
                      divisions: 3,
                      onChanged: (double v) => _apply(_s.copyWith(senseSmell: v.round())),
                    ),
                    _slider(
                      label: '内感受（心跳、呼吸）',
                      value: _s.senseInteroception.toDouble(),
                      max: 3,
                      divisions: 3,
                      onChanged: (double v) =>
                          _apply(_s.copyWith(senseInteroception: v.round())),
                    ),
                    _slider(
                      label: '环境音',
                      value: _s.senseAmbient.toDouble(),
                      max: 3,
                      divisions: 3,
                      onChanged: (double v) => _apply(_s.copyWith(senseAmbient: v.round())),
                      hint: '当前总和：${_s.senseTotal}',
                    ),
                  ],
                ),
              ),
              _card(
                '场景与时序',
                '防止两个人永远坐在原地聊天。',
                Icons.movie_filter_outlined,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _chips<PacingStrategy>(
                      values: PacingStrategy.values,
                      current: _s.pacing,
                      label: (PacingStrategy v) => kPacingLabels[v]!,
                      onChanged: (PacingStrategy v) => _apply(_s.copyWith(pacing: v)),
                    ),
                    const SizedBox(height: 8),
                    _switchRow(
                      '固定环境锚点',
                      '给死时间与天气，环境描写立刻落地。',
                      _s.ambientEnabled,
                      (bool v) => _apply(_s.copyWith(ambientEnabled: v)),
                    ),
                    if (_s.ambientEnabled) ...<Widget>[
                      _textRow('时间（如：深夜 23:40）', _timeCtrl, '深夜',
                          (String v) => _apply(_s.copyWith(ambientTime: v))),
                      _textRow('天气（如：下雨）', _weatherCtrl, '下雨',
                          (String v) => _apply(_s.copyWith(ambientWeather: v))),
                    ],
                  ],
                ),
              ),
              _card(
                '信息揭示',
                '悬疑、身份隐瞒类最吃这一组。',
                Icons.travel_explore,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _chips<RevealStrategy>(
                      values: RevealStrategy.values,
                      current: _s.reveal,
                      label: (RevealStrategy v) => kRevealLabels[v]!,
                      onChanged: (RevealStrategy v) => _apply(_s.copyWith(reveal: v)),
                    ),
                    const SizedBox(height: 8),
                    _slider(
                      label: '每轮最多揭示几条',
                      value: _s.revealMaxPerTurn.toDouble(),
                      max: 3,
                      divisions: 3,
                      onChanged: (double v) =>
                          _apply(_s.copyWith(revealMaxPerTurn: v.round())),
                    ),
                  ],
                ),
              ),
              _card(
                '主动性',
                '谁握方向盘。',
                Icons.swap_horiz,
                _chips<AgencyStrategy>(
                  values: AgencyStrategy.values,
                  current: _s.agency,
                  label: (AgencyStrategy v) => kAgencyLabels[v]!,
                  onChanged: (AgencyStrategy v) => _apply(_s.copyWith(agency: v)),
                ),
              ),
              _card(
                '角色一致性锚点',
                '语言指纹比性格描述有效十倍——给一句他说过的话。',
                Icons.fingerprint,
                Column(
                  children: <Widget>[
                    _textRow('语言指纹样本', _voiceCtrl, '“殿下，这话我只说一遍。”',
                        (String v) => _apply(_s.copyWith(anchorVoiceSample: v))),
                    _switchRow(
                      '每轮收尾自检',
                      '写完后自查有没有跳人设（长篇才建议开）。',
                      _s.anchorSelfCheck,
                      (bool v) => _apply(_s.copyWith(anchorSelfCheck: v)),
                    ),
                  ],
                ),
              ),
              _card(
                '输出排版',
                '动作还要不要斜体、台词要不要引号。',
                Icons.format_align_left,
                Column(
                  children: <Widget>[
                    _switchRow(
                      '动作用 *斜体*',
                      '旁白与动作加星号。',
                      _s.formatActionItalic,
                      (bool v) => _apply(_s.copyWith(formatActionItalic: v)),
                    ),
                    _switchRow(
                      '对白加「」',
                      '台词用中文引号包起来。',
                      _s.formatQuoteDialogue,
                      (bool v) => _apply(_s.copyWith(formatQuoteDialogue: v)),
                    ),
                    _switchRow(
                      '允许 Markdown',
                      '关掉更接近小说排版。',
                      _s.formatMarkdown,
                      (bool v) => _apply(_s.copyWith(formatMarkdown: v)),
                    ),
                    _slider(
                      label: '单轮段落上限',
                      value: _s.formatMaxParagraphs.toDouble(),
                      max: 8,
                      divisions: 8,
                      onChanged: (double v) =>
                          _apply(_s.copyWith(formatMaxParagraphs: v.round())),
                    ),
                  ],
                ),
              ),
              _card(
                '内容强度（分项）',
                '超限时一律转场或留白处理。',
                Icons.local_fire_department_outlined,
                Column(
                  children: <Widget>[
                    _slider(
                      label: '冲突烈度',
                      value: _s.intensityConflict.toDouble(),
                      max: 5,
                      divisions: 5,
                      onChanged: (double v) => _apply(_s.copyWith(intensityConflict: v.round())),
                    ),
                    _slider(
                      label: '暴力',
                      value: _s.intensityViolence.toDouble(),
                      max: 5,
                      divisions: 5,
                      onChanged: (double v) => _apply(_s.copyWith(intensityViolence: v.round())),
                    ),
                    _slider(
                      label: '恐怖',
                      value: _s.intensityHorror.toDouble(),
                      max: 5,
                      divisions: 5,
                      onChanged: (double v) => _apply(_s.copyWith(intensityHorror: v.round())),
                    ),
                    _slider(
                      label: '亲密',
                      value: _s.intensityIntimacy.toDouble(),
                      max: 5,
                      divisions: 5,
                      onChanged: (double v) => _apply(_s.copyWith(intensityIntimacy: v.round())),
                    ),
                  ],
                ),
              ),
              _card(
                '叙事结构',
                '长篇不散的骨架：当前在第几幕、这一幕要干什么。',
                Icons.menu_book_outlined,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _chips<NarrativeStructure>(
                      values: NarrativeStructure.values,
                      current: _s.structure,
                      label: (NarrativeStructure v) => kNarrativeLabels[v]!,
                      onChanged: (NarrativeStructure v) => _apply(_s.copyWith(structure: v)),
                    ),
                    const SizedBox(height: 8),
                    _slider(
                      label: '当前第几幕',
                      value: _s.structureAct.toDouble().clamp(1, 9),
                      max: 9,
                      divisions: 8,
                      onChanged: (double v) => _apply(_s.copyWith(structureAct: v.round().clamp(1, 9))),
                    ),
                    _textRow('本幕目标', _goalCtrl, '如：让对手说出半个真相',
                        (String v) => _apply(_s.copyWith(structureGoal: v))),
                  ],
                ),
              ),
              _card(
                '冲突来源',
                '「有冲突」不够，得知道冲突从哪来。',
                Icons.flash_on_outlined,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FitText('主要', style: t.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    _chips<ConflictType>(
                      values: ConflictType.values,
                      current: _s.conflictPrimary,
                      label: (ConflictType v) => kConflictLabels[v]!,
                      onChanged: (ConflictType v) => _apply(_s.copyWith(conflictPrimary: v)),
                    ),
                    const SizedBox(height: 12),
                    FitText('次要', style: t.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    _chips<ConflictType>(
                      values: ConflictType.values,
                      current: _s.conflictSecondary,
                      label: (ConflictType v) => kConflictLabels[v]!,
                      onChanged: (ConflictType v) => _apply(_s.copyWith(conflictSecondary: v)),
                    ),
                  ],
                ),
              ),
              _card(
                '语言密度与语境',
                '决定读起来像谁写的。',
                Icons.text_fields,
                Column(
                  children: <Widget>[
                    _slider(
                      label: '平均句长',
                      value: _s.sentenceLength.toDouble(),
                      max: 40,
                      divisions: 8,
                      fmt: (double v) => '${v.round()} 字',
                      onChanged: (double v) => _apply(_s.copyWith(sentenceLength: v.round())),
                    ),
                    _slider(
                      label: '每段比喻上限',
                      value: _s.metaphorPerParagraph.toDouble(),
                      max: 3,
                      divisions: 3,
                      onChanged: (double v) =>
                          _apply(_s.copyWith(metaphorPerParagraph: v.round())),
                    ),
                    _slider(
                      label: '幽默度',
                      value: _s.humorLevel.toDouble(),
                      max: 5,
                      divisions: 5,
                      onChanged: (double v) => _apply(_s.copyWith(humorLevel: v.round())),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _chips<EraSetting>(
                        values: EraSetting.values,
                        current: _s.era,
                        label: (EraSetting v) => kEraLabels[v]!,
                        onChanged: (EraSetting v) => _apply(_s.copyWith(era: v)),
                      ),
                    ),
                  ],
                ),
              ),
              _card(
                '物件焦点（麦高芬）',
                '长篇需要一个「能回来」的东西。',
                Icons.diamond_outlined,
                Column(
                  children: <Widget>[
                    _textRow('物件名（留空=不用）', _motifCtrl, '如：那枚旧怀表',
                        (String v) => _apply(_s.copyWith(motifName: v))),
                    _slider(
                      label: '每几场出现一次',
                      value: _s.motifEveryN.toDouble(),
                      max: 9,
                      divisions: 8,
                      onChanged: (double v) => _apply(_s.copyWith(motifEveryN: v.round().clamp(1, 9))),
                    ),
                  ],
                ),
              ),
              _card(
                '用户输入扩写',
                '把「我推门进去」先扩成画面，再续对方反应。',
                Icons.open_in_full,
                _chips<int>(
                  values: const <int>[0, 1, 2, 3],
                  current: _s.userExpandLevel,
                  label: (int v) => const <String>['关', '轻度·补动作', '中度·补场景', '强·改成叙述'][v],
                  onChanged: (int v) => _apply(_s.copyWith(userExpandLevel: v)),
                ),
              ),
              _card(
                '收束与钩子',
                '章末留钩子、每几轮小结、结局怎么收。',
                Icons.bookmark_border,
                Column(
                  children: <Widget>[
                    _switchRow(
                      '章末留钩子',
                      '结尾挂一个未解决的小问题。',
                      _s.closureHook,
                      (bool v) => _apply(_s.copyWith(closureHook: v)),
                    ),
                    _slider(
                      label: '每几轮小结一次（0=不用）',
                      value: _s.closureDigestEvery.toDouble(),
                      max: 10,
                      divisions: 10,
                      onChanged: (double v) =>
                          _apply(_s.copyWith(closureDigestEvery: v.round())),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _chips<EndingStyle>(
                        values: EndingStyle.values,
                        current: _s.endingStyle,
                        label: (EndingStyle v) => kEndingLabels[v]!,
                        onChanged: (EndingStyle v) => _apply(_s.copyWith(endingStyle: v)),
                      ),
                    ),
                  ],
                ),
              ),
              _card(
                '群像 / NPC',
                '群聊里最多几个 NPC、要不要代演。',
                Icons.groups_outlined,
                Column(
                  children: <Widget>[
                    _slider(
                      label: 'NPC 数量上限',
                      value: _s.npcMax.toDouble(),
                      max: 8,
                      divisions: 7,
                      onChanged: (double v) => _apply(_s.copyWith(npcMax: v.round().clamp(1, 8))),
                    ),
                    _switchRow(
                      'AI 代演 NPC',
                      '关掉后只演当前角色。',
                      _s.aiPlaysNpc,
                      (bool v) => _apply(_s.copyWith(aiPlaysNpc: v)),
                    ),
                  ],
                ),
              ),
              _card(
                '自定义字数',
                '只有字数选「自定义」时才生效。',
                Icons.straighten,
                Column(
                  children: <Widget>[
                    _chips<LengthStrategy>(
                      values: LengthStrategy.values,
                      current: _s.length,
                      label: _lengthLabel,
                      onChanged: (LengthStrategy v) => _apply(_s.copyWith(length: v)),
                    ),
                    if (_s.length == LengthStrategy.custom) ...<Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: _minCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '最少字数',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (String v) =>
                                  _apply(_s.copyWith(customMinChars: int.tryParse(v))),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: FitText('至'),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _maxCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '最多字数',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (String v) =>
                                  _apply(_s.copyWith(customMaxChars: int.tryParse(v))),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.lightbulb_outline, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: FitText(_nextTurnTip,
                    style: t.textTheme.bodySmall?.copyWith(height: 1.4)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
