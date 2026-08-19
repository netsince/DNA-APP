// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../services/llm_provider.dart';
import '../../state/app_controller.dart';
import '../../utils/dialogs.dart';
import 'package:dna/widgets/fit_text.dart';
import 'sampler_settings_page.dart';

/// 设置 → AI 服务。
///
/// 配置服务商、API 地址与密钥、模型选择以及高级采样。
class AiServiceSettingsPage extends StatefulWidget {
  const AiServiceSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AiServiceSettingsPage> createState() => _AiServiceSettingsPageState();
}

class _AiServiceSettingsPageState extends State<AiServiceSettingsPage> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;

  bool _checkingApi = false;
  bool _loadingModels = false;
  String? _apiMessage;
  String? _modelsError;
  List<String> _models = <String>[];
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    final LlmProvider provider = widget.controller.llmProvider;
    _baseUrlCtrl = TextEditingController(
      text: provider.fixedBaseUrl ? provider.defaultBaseUrl : s.baseUrl,
    );
    _apiKeyCtrl = TextEditingController(text: s.apiKey);
    _selectedModel = s.selectedModel.isEmpty ? null : s.selectedModel;
    if (provider.fixedBaseUrl) {
      // 固定地址的厂商（如智谱）无需用户填写，直接持久化默认地址。
      _saveApi();
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveApi() => widget.controller.saveApiConfig(
        baseUrl: _baseUrlCtrl.text,
        apiKey: _apiKeyCtrl.text,
      );

  Future<void> _checkApi() async {
    setState(() {
      _checkingApi = true;
      _apiMessage = null;
    });
    await _saveApi();
    final r = await widget.controller.llmProvider.validateApi(
      baseUrl: _baseUrlCtrl.text,
      apiKey: _apiKeyCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _checkingApi = false;
      _apiMessage = r.message;
    });
  }

  Future<void> _fetchModels() async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    final r = await widget.controller.llmProvider.fetchModels(
      baseUrl: _baseUrlCtrl.text,
      apiKey: _apiKeyCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _loadingModels = false;
      _models = r.models;
      _modelsError = r.errorMessage;
      if ((_selectedModel ?? '').isEmpty && _models.isNotEmpty) {
        _selectedModel = _models.first;
        _saveModel();
      }
      if (_selectedModel != null && _selectedModel!.isNotEmpty && !_models.contains(_selectedModel)) {
        _models = <String>[_selectedModel!, ..._models];
      }
    });
  }

  Future<void> _saveModel() async {
    if ((_selectedModel ?? '').trim().isEmpty) return;
    await widget.controller.saveSelectedModel(_selectedModel!.trim());
  }

  Future<void> _selectProvider(LlmProvider provider) async {
    if (provider.id == widget.controller.settings.provider) return;
    await widget.controller.saveProvider(provider.id);
    setState(() {
      _apiMessage = null;
      _models = <String>[];
      _selectedModel = null;
      if (provider.fixedBaseUrl) {
        _baseUrlCtrl.text = provider.defaultBaseUrl;
      }
    });
    await _saveApi();
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
      if (!_models.contains(v)) _models = <String>[v, ..._models];
    });
    await _saveModel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;
    final bool fixedBaseUrl = widget.controller.llmProvider.fixedBaseUrl;
    final bool isModelMissing = (_selectedModel ?? '').trim().isEmpty;

    return Scaffold(
      appBar: AppBar(title: const FitText('AI 服务')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 未选择模型警告提示条 =====
          if (isModelMissing)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.error.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded, color: cs.error, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        FitText(
                          '未选定模型',
                          style: ts.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.error,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FitText(
                          '当前服务商下尚未选定模型，聊天将无法发起请求。请在下方点击【刷新模型】或【自定义模型】进行指定。',
                          style: ts.bodySmall?.copyWith(color: cs.onErrorContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ===== 1. 服务商与 API 连接卡片 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('服务商选择', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.controller.llmProviders.map((LlmProvider p) {
                      final bool selected = p.id == widget.controller.settings.provider;
                      return ChoiceChip(
                        label: FitText(p.label),
                        selected: selected,
                        onSelected: (_) => _selectProvider(p),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  if (!fixedBaseUrl) ...<Widget>[
                    TextField(
                      controller: _baseUrlCtrl,
                      decoration: InputDecoration(
                        labelText: 'Base URL',
                        hintText: widget.controller.llmProvider.defaultBaseUrl,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: '恢复默认地址',
                          icon: const Icon(Icons.restore),
                          onPressed: () {
                            _baseUrlCtrl.text = widget.controller.llmProvider.defaultBaseUrl;
                            _saveApi();
                          },
                        ),
                      ),
                      onChanged: (_) => _saveApi(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _saveApi(),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _checkingApi ? null : _checkApi,
                    icon: _checkingApi
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_check),
                    label: FitText(_checkingApi ? '检测中...' : '检测连接'),
                  ),
                  if (_apiMessage != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Icon(
                          _apiMessage!.contains('成功') ? Icons.check_circle : Icons.error,
                          size: 16,
                          color: _apiMessage!.contains('成功') ? cs.primary : cs.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: FitText(
                            _apiMessage!,
                            style: TextStyle(color: _apiMessage!.contains('成功') ? cs.primary : cs.error),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 2. 模型选择卡片 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      FitText('当前生效模型', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      if (!isModelMissing)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: FitText(
                            _selectedModel!,
                            style: ts.labelSmall?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: _loadingModels ? null : _fetchModels,
                        icon: _loadingModels
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh),
                        label: FitText(_loadingModels ? '加载中...' : '刷新模型列表'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addCustomModel,
                        icon: const Icon(Icons.edit_outlined),
                        label: const FitText('自定义模型'),
                      ),
                    ],
                  ),
                  if (_modelsError != null) ...[
                    const SizedBox(height: 8),
                    FitText(_modelsError!, style: TextStyle(color: cs.error)),
                  ],
                  const SizedBox(height: 12),
                  if (_models.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: FitText(
                        _selectedModel == null
                            ? '尚未加载模型列表。可点击【刷新模型列表】自动拉取，或点击【自定义模型】手动填写。'
                            : '已选定当前模型：$_selectedModel',
                        style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  else ...<Widget>[
                    FitText('可选模型列表（点击切换）：', style: ts.bodySmall?.copyWith(color: cs.outline)),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 240),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _models.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final String model = _models[index];
                          final bool sel = model == _selectedModel;
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: Icon(
                              sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              color: sel ? cs.primary : cs.outline,
                              size: 18,
                            ),
                            title: FitText(
                              model,
                              style: TextStyle(
                                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                                color: sel ? cs.primary : null,
                              ),
                            ),
                            onTap: () {
                              setState(() => _selectedModel = model);
                              _saveModel();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 3. DeepSeek 思考模式 =====
          if (widget.controller.llmProvider.id == 'deepseek') ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FitText('DeepSeek 深度思考模式', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const FitText('启用思考模式（Reasoning）'),
                      subtitle: const FitText('开启后模型会在作答前展开深度思考过程'),
                      value: widget.controller.settings.deepseekThinkingEnabled,
                      onChanged: (bool v) async {
                        await widget.controller.saveDeepseekThinking(
                          enabled: v,
                          effort: widget.controller.settings.deepseekThinkingEffort,
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    FitText('思考强度', style: ts.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final String effort in const <String>['low', 'high', 'max'])
                          ChoiceChip(
                            label: FitText(switch (effort) {
                              'low' => '低',
                              'high' => '高',
                              _ => '最高',
                            }),
                            selected: widget.controller.settings.deepseekThinkingEffort == effort,
                            onSelected: (_) async {
                              await widget.controller.saveDeepseekThinking(
                                enabled: widget.controller.settings.deepseekThinkingEnabled,
                                effort: effort,
                              );
                              if (mounted) setState(() {});
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ===== 4. 采样参数入口 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Icon(Icons.tune, color: cs.primary),
              title: const FitText('采样参数微调'),
              subtitle: const FitText('包含场景预设与温度、核采样、防复读等高级参数调节'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SamplerSettingsPage(controller: widget.controller),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
