/// 设置 → 采样参数（配置驱动版）。
///
/// 取代 `sampler_settings_page.dart` 的手写页面。8 个采样参数各自一条声明，
/// 场景预设与「恢复默认」用 [SettingAction]（一次动作要同时改多个 key，
/// 不是单个字段能表达的）。
library;

import 'package:material_ui/material_ui.dart';

import 'package:dna/widgets/fit_text.dart';
import 'package:dna/utils/ui_feedback.dart';

import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import 'spec/settings_spec.dart';

/// 8 个采样参数的默认值，与 AppSettings 的默认值一致。
const double _kTemperature = 0.7;
const double _kFrequencyPenalty = 0.0;
const double _kPresencePenalty = 0.0;
const double _kTopP = 1.0;
const double _kTopK = 0.0;
const double _kMinP = 0.0;
const double _kRepetitionPenalty = 1.0;
const double _kRepetitionPenaltySlope = 0.0;

/// 当前是否全为默认值（决定「恢复默认」按钮是否出现）。
bool _isDefault(SettingsRuntime runtime) {
  final s = runtime.settings;
  return s.temperature == _kTemperature &&
      s.frequencyPenalty == _kFrequencyPenalty &&
      s.presencePenalty == _kPresencePenalty &&
      s.topP == _kTopP &&
      s.topK == _kTopK &&
      s.minP == _kMinP &&
      s.repetitionPenalty == _kRepetitionPenalty &&
      s.repetitionPenaltySlope == _kRepetitionPenaltySlope;
}

/// 一次写 8 个参数。预设与恢复默认共用。
///
/// 保留旧页面的两个写入口（先基础三项、再进阶五项），因为
/// `saveSampling` / `saveAdvancedSampling` 各自还有模型侧的同步逻辑；
/// 拆成 8 次 `patchSettings` 会绕开它们。
Future<void> _writeAll(
  AppController controller, {
  required double temp,
  required double freq,
  required double pres,
  required double topP,
  required double topK,
  required double minP,
  required double rep,
  required double slope,
}) async {
  await controller.saveSampling(
    temperature: temp,
    frequencyPenalty: freq,
    presencePenalty: pres,
  );
  await controller.saveAdvancedSampling(
    topP: topP,
    topK: topK,
    minP: minP,
    repetitionPenalty: rep,
    repetitionPenaltySlope: slope,
  );
}

/// 场景预设：一行可点的胶囊。
class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.controller});

  final AppController controller;

  Widget _chip({
    required BuildContext context,
    required IconData icon,
    required String label,
    required double temp,
    required double freq,
    required double pres,
    required double topP,
    required double topK,
    required double minP,
    required double rep,
    required double slope,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: AppSize.iconInline),
      label: FitText(label),
      onPressed: () async {
        await _writeAll(
          controller,
          temp: temp,
          freq: freq,
          pres: pres,
          topP: topP,
          topK: topK,
          minP: minP,
          rep: rep,
          slope: slope,
        );
        // await 之后用 context：显式守卫，替代原来的「先抓 messenger」。
        if (!context.mounted) return;
        showSnack(
          context,
          '已应用预设参数',
          duration: const Duration(seconds: 1),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          _chip(
            context: context,
            icon: Icons.balance,
            label: '标准平衡',
            temp: _kTemperature,
            freq: _kFrequencyPenalty,
            pres: _kPresencePenalty,
            topP: _kTopP,
            topK: _kTopK,
            minP: _kMinP,
            rep: _kRepetitionPenalty,
            slope: _kRepetitionPenaltySlope,
          ),
          _chip(
            context: context,
            icon: Icons.psychology,
            label: '天马行空',
            temp: 1.05,
            freq: 0.2,
            pres: 0.2,
            topP: 0.95,
            topK: 40.0,
            minP: 0.05,
            rep: 1.05,
            slope: 0.0,
          ),
          _chip(
            context: context,
            icon: Icons.menu_book,
            label: '长篇叙事',
            temp: 0.85,
            freq: 0.1,
            pres: 0.15,
            topP: 0.9,
            topK: 0.0,
            minP: 0.0,
            rep: 1.05,
            slope: 0.0,
          ),
          _chip(
            context: context,
            icon: Icons.shield_outlined,
            label: '强力防复读',
            temp: 0.7,
            freq: 0.6,
            pres: 0.4,
            topP: 0.95,
            topK: 0.0,
            minP: 0.0,
            rep: 1.15,
            slope: 0.1,
          ),
        ],
      ),
    );
  }
}

/// 采样参数页的完整声明。
final FieldsEntry samplerEntry = FieldsEntry(
  id: 'sampler',
  groupId: SettingsGroupId.ai,
  icon: Icons.tune,
  title: '采样参数',
  subtitle: '回复的随机程度与防复读强度',
  sections: <SettingSectionSpec>[
    SettingSectionSpec(
      id: 'sampler.presets',
      icon: Icons.auto_awesome_outlined,
      title: '场景预设',
      description: '套用典型场景参数，下方会同步更新。',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'sampler.presetRow',
          title: '场景预设',
          searchable: false,
          builder: (BuildContext context, AppController c) =>
              _PresetRow(controller: c),
        ),
        SettingAction(
          id: 'sampler.reset',
          title: '恢复默认',
          searchable: false,
          visibleWhen: (SettingsRuntime r) => !_isDefault(r),
          builder: (BuildContext context, AppController c) => TextButton.icon(
            onPressed: () => _writeAll(
              c,
              temp: _kTemperature,
              freq: _kFrequencyPenalty,
              pres: _kPresencePenalty,
              topP: _kTopP,
              topK: _kTopK,
              minP: _kMinP,
              rep: _kRepetitionPenalty,
              slope: _kRepetitionPenaltySlope,
            ),
            icon: const Icon(Icons.refresh),
            label: const FitText('恢复默认'),
          ),
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'sampler.core',
      icon: Icons.thermostat_outlined,
      title: '核心采样参数',
      description: '决定回复的随机程度。',
      items: <SettingItemSpec>[
        SettingDouble(
          id: 'sampler.temperature',
          title: '温度 (Temperature)',
          hint: '越低越确定、严谨；越高越发散、富有想象力。默认 0.70。',
          key: 'temperature',
          defaultValue: _kTemperature,
          min: 0.0,
          max: 2.0,
          step: 0.05,
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingDouble(
          id: 'sampler.frequencyPenalty',
          title: '频率惩罚 (Frequency Penalty)',
          hint: '按词语出现的绝对次数施加惩罚，降低复读倾向。默认 0.00。',
          key: 'frequencyPenalty',
          defaultValue: _kFrequencyPenalty,
          min: 0.0,
          max: 2.0,
          step: 0.05,
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingDouble(
          id: 'sampler.presencePenalty',
          title: '存在惩罚 (Presence Penalty)',
          hint: '词语出现过就施加固定惩罚，鼓励引入新话题。默认 0.00。',
          key: 'presencePenalty',
          defaultValue: _kPresencePenalty,
          min: 0.0,
          max: 2.0,
          step: 0.05,
          saveMode: SettingsSaveMode.onRelease,
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'sampler.advanced',
      icon: Icons.filter_alt_outlined,
      title: '进阶核采样与惩罚',
      description: '多数模型无需调整。',
      items: <SettingItemSpec>[
        SettingDouble(
          id: 'sampler.topP',
          title: 'Top-P (核采样)',
          hint: '只从累积概率达到 P 的候选词里采样。1.00 表示不截断。默认 1.00。',
          key: 'topP',
          defaultValue: _kTopP,
          min: 0.0,
          max: 1.0,
          step: 0.05,
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingDouble(
          id: 'sampler.topK',
          title: 'Top-K',
          hint: '只从概率最高的前 K 个候选词里采样。默认 0。',
          key: 'topK',
          defaultValue: _kTopK,
          min: 0.0,
          max: 100.0,
          step: 1.0,
          zeroLabel: '不限制',
          decimals: 0,
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingDouble(
          id: 'sampler.minP',
          title: 'Min-P',
          hint: '过滤概率低于「最高概率 × Min-P」的候选词。默认 0.00。',
          key: 'minP',
          defaultValue: _kMinP,
          min: 0.0,
          max: 1.0,
          step: 0.05,
          zeroLabel: '不限制',
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingDouble(
          id: 'sampler.repetitionPenalty',
          title: '重复惩罚 (Repetition Penalty)',
          hint: '直接降低已出现词的生成概率。1.00 为无惩罚，常用 1.05~1.20。',
          key: 'repetitionPenalty',
          defaultValue: _kRepetitionPenalty,
          min: 1.0,
          max: 2.0,
          step: 0.05,
          saveMode: SettingsSaveMode.onRelease,
        ),
        SettingDouble(
          id: 'sampler.repetitionPenaltySlope',
          title: '重复惩罚斜率 (Slope)',
          hint: '距离越近的重复词惩罚越重。默认 0.0。',
          key: 'repetitionPenaltySlope',
          defaultValue: _kRepetitionPenaltySlope,
          min: 0.0,
          max: 1.0,
          step: 0.1,
          zeroLabel: '平权',
          decimals: 1,
          saveMode: SettingsSaveMode.onRelease,
        ),
      ],
    ),
  ],
);
