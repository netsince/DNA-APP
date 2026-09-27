// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/models/llm_model_config.dart';
import 'package:dna/models/llm_provider_config.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/utils/id_utils.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';
import 'model_sampler_settings_page.dart';

/// 模型预设编辑全屏页面（添加 / 修改）。
///
/// **关于「规矩 1」的说明**:本页是 **表单编辑页**(`Form` + 校验 + 保存回写),
/// 不是「设置项堆叠」—— 设置项之间靠 `TextFormField` 的 label 与校验反馈
/// 建立语义,强行拆成一个个可折叠项反而会破坏表单的填写节奏。
///
/// 因此这里只做两件事:
/// * 卡片外观统一收敛到 [SettingSection](消除手写 `Card > Padding > Column` 的
///   圆角/描边/内边距魔数);
/// * 两条 25 字长提示按**规矩 3** 压到 20 字以内。
class ModelEditPage extends StatefulWidget {
  const ModelEditPage({
    super.key,
    required this.controller,
    this.existingConfig,
  });

  final AppController controller;
  final LlmModelConfig? existingConfig;

  @override
  State<ModelEditPage> createState() => _ModelEditPageState();
}

class _ModelEditPageState extends State<ModelEditPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _aliasCtrl;
  late final TextEditingController _modelNameCtrl;

  late String _selectedProviderId;

  // 深度思考（仅 DeepSeek 生效）
  bool _deepseekThinkingEnabled = true;
  String _deepseekThinkingEffort = 'high';

  // 独立采样参数
  bool _customSamplingEnabled = false;
  double? _temperature;
  double? _frequencyPenalty;
  double? _presencePenalty;
  double? _topP;
  double? _topK;
  double? _minP;
  double? _repetitionPenalty;
  double? _repetitionPenaltySlope;
  int? _maxContextMessages;
  int? _maxContextTokens;

  bool _fetchingModels = false;

  bool get _isEditing => widget.existingConfig != null;
  bool get _isDefault => widget.existingConfig?.isDefault ?? false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingConfig;
    _aliasCtrl = TextEditingController(text: existing?.alias ?? '');
    _modelNameCtrl = TextEditingController(text: existing?.modelName ?? '');

    final providers = widget.controller.settings.providers;
    if (existing != null && providers.any((p) => p.id == existing.providerId)) {
      _selectedProviderId = existing.providerId;
    } else if (providers.isNotEmpty) {
      _selectedProviderId = providers.first.id;
    } else {
      _selectedProviderId = LlmProviderConfig.defaultId;
    }

    _deepseekThinkingEnabled =
        existing?.deepseekThinkingEnabled ?? widget.controller.settings.deepseekThinkingEnabled;
    _deepseekThinkingEffort =
        existing?.deepseekThinkingEffort ?? widget.controller.settings.deepseekThinkingEffort;

    _customSamplingEnabled = existing?.customSamplingEnabled ?? false;
    _temperature = existing?.temperature;
    _frequencyPenalty = existing?.frequencyPenalty;
    _presencePenalty = existing?.presencePenalty;
    _topP = existing?.topP;
    _topK = existing?.topK;
    _minP = existing?.minP;
    _repetitionPenalty = existing?.repetitionPenalty;
    _repetitionPenaltySlope = existing?.repetitionPenaltySlope;
    _maxContextMessages = existing?.maxContextMessages;
    _maxContextTokens = existing?.maxContextTokens;
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _modelNameCtrl.dispose();
    super.dispose();
  }

  LlmProviderConfig _findCurrentProvider() {
    return widget.controller.settings.providers.firstWhere(
      (p) => p.id == _selectedProviderId,
      orElse: () => widget.controller.settings.providers.isNotEmpty
          ? widget.controller.settings.providers.first
          : LlmProviderConfig.defaultConfig(),
    );
  }

  Future<void> _fetchOnlineModels() async {
    setState(() {
      _fetchingModels = true;
    });

    final providerConfig = _findCurrentProvider();
    final reg = widget.controller.llmProviders.firstWhere(
      (item) => item.id == providerConfig.providerType,
      orElse: () => widget.controller.llmProviders.first,
    );

    final baseUrl = providerConfig.baseUrl.isEmpty
        ? reg.defaultBaseUrl
        : providerConfig.baseUrl;
    final apiKey = providerConfig.apiKey;

    final result = await reg.fetchModels(baseUrl: baseUrl, apiKey: apiKey);

    if (!mounted) return;
    setState(() {
      _fetchingModels = false;
    });

    if (result.models.isNotEmpty) {
      final selected = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.list_alt_rounded),
                      const SizedBox(width: 8),
                      const FitText(
                        '选择模型',
                        style: TextStyle(
                            fontSize: AppFontSize.subtitle, fontWeight: AppWeight.medium),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const FitText('关闭'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: result.models.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final m = result.models[idx];
                      return ListTile(
                        title: FitText(m),
                        onTap: () => Navigator.of(ctx).pop(m),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );

      if (selected != null && mounted) {
        setState(() {
          _modelNameCtrl.text = selected;
        });
      }
    } else if (result.errorMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: FitText('拉取失败: ${result.errorMessage}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _openSamplerSettings() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (_) => ModelSamplerSettingsPage(
          initialTemperature: _temperature,
          initialFrequencyPenalty: _frequencyPenalty,
          initialPresencePenalty: _presencePenalty,
          initialTopP: _topP,
          initialTopK: _topK,
          initialMinP: _minP,
          initialRepetitionPenalty: _repetitionPenalty,
          initialRepetitionPenaltySlope: _repetitionPenaltySlope,
          initialMaxContextMessages: _maxContextMessages,
          initialMaxContextTokens: _maxContextTokens,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _temperature = result['temperature'] as double?;
        _frequencyPenalty = result['frequencyPenalty'] as double?;
        _presencePenalty = result['presencePenalty'] as double?;
        _topP = result['topP'] as double?;
        _topK = result['topK'] as double?;
        _minP = result['minP'] as double?;
        _repetitionPenalty = result['repetitionPenalty'] as double?;
        _repetitionPenaltySlope = result['repetitionPenaltySlope'] as double?;
        _maxContextMessages = result['maxContextMessages'] as int?;
        _maxContextTokens = result['maxContextTokens'] as int?;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final alias = _aliasCtrl.text.trim();
    final String id = widget.existingConfig?.id ??
        'model_${newId().substring(0, 8)}';

    final updated = LlmModelConfig(
      id: id,
      alias: _isDefault ? LlmModelConfig.defaultAlias : alias,
      providerId: _selectedProviderId,
      modelName: _modelNameCtrl.text.trim(),
      customSamplingEnabled: _customSamplingEnabled,
      temperature: _temperature,
      frequencyPenalty: _frequencyPenalty,
      presencePenalty: _presencePenalty,
      topP: _topP,
      topK: _topK,
      minP: _minP,
      repetitionPenalty: _repetitionPenalty,
      repetitionPenaltySlope: _repetitionPenaltySlope,
      maxContextMessages: _maxContextMessages,
      maxContextTokens: _maxContextTokens,
      deepseekThinkingEnabled: _deepseekThinkingEnabled,
      deepseekThinkingEffort: _deepseekThinkingEffort,
    );

    await widget.controller.saveModelConfig(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: FitText(_isEditing ? '模型预设已更新' : '已添加新模型预设'),
        duration: const Duration(milliseconds: 1500),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final providers = widget.controller.settings.providers;
    final currentProvider = _findCurrentProvider();
    final isDeepSeek = currentProvider.providerType == 'deepseek';

    return Scaffold(
      appBar: AppBar(
        title: FitText(_isEditing ? '编辑模型预设' : '添加模型预设'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存',
            onPressed: _save,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppInsets.page,
          children: <Widget>[
            // ===== 1. 模型基本信息 =====
            SettingSection(
              icon: Icons.badge_outlined,
              title: '模型预设信息',
              description: '这个预设怎么称呼、走哪家服务。',
              children: <Widget>[
                // 模型别名
                TextFormField(
                  controller: _aliasCtrl,
                  enabled: !_isDefault,
                  decoration: InputDecoration(
                    labelText: '模型别名',
                    hintText: '例如 GPT-4o 常用 / 思考模型',
                    border: const OutlineInputBorder(),
                    helperText: _isDefault ? '默认模型别名固定为“默认”，不可修改' : null,
                  ),
                  validator: (value) {
                    if (_isDefault) return null;
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return '请输入模型别名';
                    final exists = widget.controller.settings.models
                        .any((m) => m.alias == v && m.id != widget.existingConfig?.id);
                    if (exists) return '该别名已被使用，请换一个';
                    return null;
                  },
                ),

                AppSpacing.hLg,

                // 所属服务商
                DropdownButtonFormField<String>(
                  value: _selectedProviderId,
                  decoration: const InputDecoration(
                    labelText: '归属服务商',
                    border: OutlineInputBorder(),
                  ),
                  items: providers.map((p) {
                    return DropdownMenuItem<String>(
                      value: p.id,
                      child: FitText('${p.alias} (${p.providerType})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _selectedProviderId = val);
                  },
                ),

                AppSpacing.hLg,

                // Model Name
                TextFormField(
                  controller: _modelNameCtrl,
                  decoration: InputDecoration(
                    labelText: '模型名称 (Model ID)',
                    hintText: '例如 gpt-4o / deepseek-chat',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: '从服务商 API 获取模型列表',
                      icon: _fetchingModels
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      onPressed: _fetchingModels ? null : _fetchOnlineModels,
                    ),
                  ),
                  validator: (value) {
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return '请输入模型名称';
                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _fetchingModels ? null : _fetchOnlineModels,
                    icon: const Icon(Icons.download_rounded, size: AppSize.iconInline),
                    label: const FitText('从服务商拉取模型列表'),
                  ),
                ),
              ],
            ),

            // ===== 2. DeepSeek 深度思考（严格仅在服务商为 DeepSeek 时展示） =====
            if (isDeepSeek)
              SettingSection(
                icon: Icons.psychology_outlined,
                title: 'DeepSeek 深度思考模式',
                description: '开启后模型先推理再回答。',
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('启用思考模式 (Reasoning)'),
                    value: _deepseekThinkingEnabled,
                    onChanged: (v) {
                      setState(() => _deepseekThinkingEnabled = v);
                    },
                  ),
                  if (_deepseekThinkingEnabled) ...<Widget>[
                    AppSpacing.hSm,
                    FitText(
                      '思考强度',
                      style: AppTextStyles.body(theme)
                          .copyWith(fontWeight: AppWeight.medium),
                    ),
                    AppSpacing.hXs,
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        for (final String effort in const <String>['low', 'high', 'max'])
                          ChoiceChip(
                            label: FitText(switch (effort) {
                              'low' => '低',
                              'high' => '高',
                              _ => '最高',
                            }),
                            selected: _deepseekThinkingEffort == effort,
                            onSelected: (_) {
                              setState(() => _deepseekThinkingEffort = effort);
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),

            // ===== 3. 专属采样参数微调（完整复用） =====
            SettingSection(
              icon: Icons.tune_outlined,
              title: '专属采样参数',
              description: '只为这个模型单独调参。',
              children: <Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const FitText('为该模型启用专属采样配置'),
                  subtitle: FitText(
                    _customSamplingEnabled ? '已启用：覆盖全局设置' : '已关闭：继承全局设置',
                  ),
                  value: _customSamplingEnabled,
                  onChanged: (v) {
                    setState(() => _customSamplingEnabled = v);
                  },
                ),
                if (_customSamplingEnabled) ...<Widget>[
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.tune_rounded, color: cs.primary),
                    title: const FitText('微调模型采样参数'),
                    subtitle: FitText(
                      '温度 ${(_temperature ?? 0.7).toStringAsFixed(2)}'
                      ' • 核采样 ${(_topP ?? 1.0).toStringAsFixed(2)}',
                      style: AppTextStyles.caption(theme)
                          .copyWith(color: cs.onSurfaceVariant),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openSamplerSettings,
                  ),
                ],
              ],
            ),

            AppSpacing.hXl,

            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: FitText(_isEditing ? '保存修改' : '确认添加'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
