// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/services/llm_provider.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/utils/api_guard.dart';
import 'package:dna/utils/dialogs.dart';
import 'package:dna/widgets/setting_section.dart';

import '../sampler_settings_page.dart';
import 'connection_section.dart';
import 'model_section.dart';
import 'thinking_section.dart';
import 'widgets.dart';

/// 设置 → AI 服务(精简模式)。
///
/// **本次重构**(见 `SETTINGS_AUDIT.md`):
/// * 全部手写 `Card > Padding > Column` 样板替换为 `SettingSection` 分组;
/// * 「模型名称」改为可折叠项,收起态只显示「模型名称 + 当前值」;
/// * `Base URL` / `API Key` 等术语改为「接口地址」「密钥」,并在 `AiGlossary` 里解释;
/// * 长提示压到 20 字以内,参考信息与安全提醒改走 `SettingHint` / 折叠说明区。
///
/// **行为与重构前完全一致**:服务商切换、地址恢复默认、密钥保存、连接检测、
/// 模型拉取与自定义、DeepSeek 思考模式、采样参数入口,全部沿用原调用。
class AiServiceSimplePage extends StatefulWidget {
  const AiServiceSimplePage({
    super.key,
    required this.controller,
    required this.baseUrlController,
    required this.apiKeyController,
    required this.onResetControllers,
  });

  final AppController controller;
  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;

  /// 重新从设置装载两个输入框(由主页在切换模式 / 初始化时调用)。
  final VoidCallback onResetControllers;

  @override
  State<AiServiceSimplePage> createState() => _AiServiceSimplePageState();
}

class _AiServiceSimplePageState extends State<AiServiceSimplePage> {
  late final TextEditingController _modelCtrl;

  bool _checkingApi = false;
  bool _apiSuccess = false;
  String? _apiMessage;

  bool _loadingModels = false;
  String? _modelsError;
  List<String> _models = <String>[];
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    final String model = widget.controller.settings.selectedModel;
    _selectedModel = model.isEmpty ? null : model;
    _modelCtrl = TextEditingController(text: model);
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveApi() => widget.controller.saveApiConfig(
        baseUrl: widget.baseUrlController.text,
        apiKey: widget.apiKeyController.text,
      );

  Future<void> _checkApi() async {
    setState(() {
      _checkingApi = true;
      _apiMessage = null;
    });
    await _saveApi();
    final r = await widget.controller.llmProvider.validateApi(
      baseUrl: widget.baseUrlController.text,
      apiKey: widget.apiKeyController.text,
    );
    if (!mounted) return;
    setState(() {
      _checkingApi = false;
      _apiSuccess = r.success;
      // 校验文案附加明文 HTTP 传输警示(成功/失败均展示,不阻断)。
      _apiMessage = withTransportWarning(widget.baseUrlController.text, r.message);
    });
  }

  Future<void> _fetchModels() async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    final r = await widget.controller.llmProvider.fetchModels(
      baseUrl: widget.baseUrlController.text,
      apiKey: widget.apiKeyController.text,
    );
    if (!mounted) return;
    setState(() {
      _loadingModels = false;
      _models = r.models;
      _modelsError = r.errorMessage;
      if ((_selectedModel ?? '').isEmpty && _models.isNotEmpty) {
        _selectedModel = _models.first;
        _modelCtrl.text = _selectedModel!;
        _saveModel();
      }
      if (_selectedModel != null &&
          _selectedModel!.isNotEmpty &&
          !_models.contains(_selectedModel)) {
        _models = <String>[_selectedModel!, ..._models];
      }
    });
  }

  Future<void> _saveModel() async {
    if ((_selectedModel ?? '').trim().isEmpty) return;
    await widget.controller.saveSelectedModel(_selectedModel!.trim());
  }

  void _onModelChanged(String value) {
    setState(() => _selectedModel = value.trim().isEmpty ? null : value);
    _saveModel();
  }

  Future<void> _addCustomModel() async {
    final v = await showTextInputDialog(
      context: context,
      title: '输入自定义模型',
      hintText: '例如 gpt-4.1-mini',
      confirmText: '确定',
    );
    if (!mounted || v == null || v.isEmpty) return;
    setState(() {
      _selectedModel = v;
      _modelCtrl.text = v;
      if (!_models.contains(v)) _models = <String>[v, ..._models];
    });
    await _saveModel();
  }

  Future<void> _selectProvider(LlmProvider provider) async {
    if (provider.id == widget.controller.settings.provider) return;
    await widget.controller.saveProvider(provider.id);
    setState(() {
      _apiMessage = null;
      _models = <String>[];
      _selectedModel = null;
    });
    if (provider.fixedBaseUrl) {
      widget.baseUrlController.text = provider.defaultBaseUrl;
    }
    await _saveApi();
  }

  @override
  Widget build(BuildContext context) {
    final List<LlmProvider> providers = widget.controller.llmProviders;
    final LlmProvider current = widget.controller.llmProvider;
    final bool isDeepSeek = current.id == 'deepseek';

    return ListView(
      padding: AppInsets.page,
      children: <Widget>[
        if ((_selectedModel ?? '').trim().isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.lg),
            child: AiMissingModelNotice(),
          ),

        // ===== 1. 连接设置 =====
        AiConnectionSection(
          providers: providers,
          selectedProviderId: widget.controller.settings.provider,
          fixedBaseUrl: current.fixedBaseUrl,
          defaultBaseUrl: current.defaultBaseUrl,
          baseUrlController: widget.baseUrlController,
          apiKeyController: widget.apiKeyController,
          requiresApiKey: current.requiresApiKey,
          checking: _checkingApi,
          statusMessage: _apiMessage,
          statusSuccess: _apiSuccess,
          onProviderSelected: _selectProvider,
          onRestoreBaseUrl: () {
            widget.baseUrlController.text = current.defaultBaseUrl;
            _saveApi();
          },
          onCheck: _checkApi,
        ),

        // ===== 2. 用哪个模型 =====
        AiModelSection(
          nameController: _modelCtrl,
          selectedModel: _selectedModel,
          models: _models,
          loading: _loadingModels,
          errorMessage: _modelsError,
          onNameChanged: _onModelChanged,
          onNameSubmitted: (_) => _saveModel(),
          onCreateModel: _addCustomModel,
          onFetchModels: _fetchModels,
          onPickModel: (String model) {
            setState(() {
              _selectedModel = model;
              _modelCtrl.text = model;
            });
            _saveModel();
          },
        ),

        // ===== 3. DeepSeek 深度思考 =====
        if (isDeepSeek)
          AiThinkingSection(
            enabled: widget.controller.settings.deepseekThinkingEnabled,
            effort: widget.controller.settings.deepseekThinkingEffort,
            onEnabledChanged: (bool v) async {
              await widget.controller.saveDeepseekThinking(
                enabled: v,
                effort: widget.controller.settings.deepseekThinkingEffort,
              );
              if (mounted) setState(() {});
            },
            onEffortChanged: (String effort) async {
              await widget.controller.saveDeepseekThinking(
                enabled: widget.controller.settings.deepseekThinkingEnabled,
                effort: effort,
              );
              if (mounted) setState(() {});
            },
          ),

        // ===== 4. 采样参数入口 =====
        SettingSection(
          icon: Icons.tune,
          title: '回复风格微调',
          description: '觉得回答太长或太重复时再来。',
          children: <Widget>[
            AiEntryCard(
              icon: Icons.equalizer_outlined,
              title: '采样参数',
              subtitle: '温度、随机性与防复读',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SamplerSettingsPage(
                    controller: widget.controller,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
