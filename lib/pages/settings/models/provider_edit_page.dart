// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:dna/models/llm_provider_config.dart';
import 'package:dna/services/llm_provider.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/utils/id_utils.dart';
import 'package:dna/widgets/fit_text.dart';

/// 服务商编辑全屏页面（添加 / 修改）。
class ProviderEditPage extends StatefulWidget {
  const ProviderEditPage({
    super.key,
    required this.controller,
    this.existingConfig,
  });

  final AppController controller;
  final LlmProviderConfig? existingConfig;

  @override
  State<ProviderEditPage> createState() => _ProviderEditPageState();
}

class _ProviderEditPageState extends State<ProviderEditPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _aliasCtrl;
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;

  late String _selectedType;
  bool _obscureApiKey = true;
  bool _testingApi = false;
  String? _testMessage;
  bool? _testSuccess;

  bool get _isEditing => widget.existingConfig != null;
  bool get _isDefault => widget.existingConfig?.isDefault ?? false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingConfig;
    _aliasCtrl = TextEditingController(
      text: existing?.alias ?? '',
    );
    _selectedType = existing?.providerType ?? 'openai';
    _baseUrlCtrl = TextEditingController(
      text: existing?.baseUrl ?? '',
    );
    _apiKeyCtrl = TextEditingController(
      text: existing?.apiKey ?? '',
    );
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  LlmProvider _findRegisteredProvider(String typeId) {
    return widget.controller.llmProviders.firstWhere(
      (p) => p.id == typeId,
      orElse: () => widget.controller.llmProviders.first,
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingApi = true;
      _testMessage = null;
      _testSuccess = null;
    });

    final reg = _findRegisteredProvider(_selectedType);
    final baseUrl = _baseUrlCtrl.text.trim().isEmpty
        ? reg.defaultBaseUrl
        : _baseUrlCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();

    final result = await reg.validateApi(
      baseUrl: baseUrl,
      apiKey: apiKey,
    );

    if (!mounted) return;
    setState(() {
      _testingApi = false;
      _testMessage = result.message;
      _testSuccess = result.message.contains('成功') || result.success;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final alias = _aliasCtrl.text.trim();
    final String id = widget.existingConfig?.id ??
        'provider_${newId().substring(0, 8)}';

    final updated = LlmProviderConfig(
      id: id,
      alias: _isDefault ? LlmProviderConfig.defaultAlias : alias,
      providerType: _selectedType,
      baseUrl: _baseUrlCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
    );

    await widget.controller.saveProviderConfig(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: FitText(_isEditing ? '服务商配置已更新' : '已添加新服务商'),
        duration: const Duration(milliseconds: 1500),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;
    final registered = _findRegisteredProvider(_selectedType);

    return Scaffold(
      appBar: AppBar(
        title: FitText(_isEditing ? '编辑服务商' : '添加服务商'),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: <Widget>[
            // ===== 基础配置卡片 =====
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FitText('服务商基本信息',
                        style: ts.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    // 别名
                    TextFormField(
                      controller: _aliasCtrl,
                      enabled: !_isDefault,
                      decoration: InputDecoration(
                        labelText: '服务商别名',
                        hintText: '例如 我的主力 OpenAI',
                        border: const OutlineInputBorder(),
                        helperText: _isDefault ? '默认服务商别名固定为“默认”，不可修改' : null,
                      ),
                      validator: (value) {
                        if (_isDefault) return null;
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return '请输入服务商别名';
                        final exists = widget.controller.settings.providers
                            .any((p) => p.alias == v && p.id != widget.existingConfig?.id);
                        if (exists) return '该别名已被使用，请换一个';
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // 协议类型
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: const InputDecoration(
                        labelText: '协议类型',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.controller.llmProviders.map((p) {
                        return DropdownMenuItem<String>(
                          value: p.id,
                          child: FitText(p.label),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() {
                          _selectedType = val;
                          final p = _findRegisteredProvider(val);
                          if (p.fixedBaseUrl) {
                            _baseUrlCtrl.text = p.defaultBaseUrl;
                          }
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    // Base URL
                    if (!registered.fixedBaseUrl) ...<Widget>[
                      TextFormField(
                        controller: _baseUrlCtrl,
                        decoration: InputDecoration(
                          labelText: 'API 地址 (Base URL)',
                          hintText: registered.defaultBaseUrl,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: '恢复默认地址',
                            icon: const Icon(Icons.restore),
                            onPressed: () {
                              _baseUrlCtrl.text = registered.defaultBaseUrl;
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // API Key
                    TextFormField(
                      controller: _apiKeyCtrl,
                      obscureText: _obscureApiKey,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        hintText: 'sk-...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscureApiKey ? '显示 API Key' : '隐藏 API Key',
                          icon: Icon(
                            _obscureApiKey
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() => _obscureApiKey = !_obscureApiKey);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ===== 连通性测试卡片 =====
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FitText('连接检测',
                        style: ts.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    FitText(
                      '测试当前填写的 Base URL 与 API Key 是否能成功连通服务商。',
                      style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _testingApi ? null : _testConnection,
                      icon: _testingApi
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check),
                      label: FitText(_testingApi ? '检测中...' : '开始连通性测试'),
                    ),
                    if (_testMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_testSuccess ?? false)
                              ? cs.primaryContainer.withValues(alpha: 0.4)
                              : cs.errorContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (_testSuccess ?? false)
                                ? cs.primary.withValues(alpha: 0.4)
                                : cs.error.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              (_testSuccess ?? false)
                                  ? Icons.check_circle_rounded
                                  : Icons.error_rounded,
                              color: (_testSuccess ?? false)
                                  ? cs.primary
                                  : cs.error,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FitText(
                                _testMessage!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: (_testSuccess ?? false)
                                      ? cs.onPrimaryContainer
                                      : cs.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: FitText(_isEditing ? '保存修改' : '确认添加'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
