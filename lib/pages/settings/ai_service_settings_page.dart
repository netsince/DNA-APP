import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../utils/dialogs.dart';

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
    _baseUrlCtrl = TextEditingController(text: s.baseUrl);
    _apiKeyCtrl = TextEditingController(text: s.apiKey);
    _selectedModel = s.selectedModel.isEmpty ? null : s.selectedModel;
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
    setState(() { _checkingApi = true; _apiMessage = null; });
    await _saveApi();
    final r = await widget.controller.llmProvider.validateApi(
      baseUrl: _baseUrlCtrl.text,
      apiKey: _apiKeyCtrl.text,
    );
    if (!mounted) return;
    setState(() { _checkingApi = false; _apiMessage = r.message; });
  }

  Future<void> _fetchModels() async {
    setState(() { _loadingModels = true; _modelsError = null; });
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

  Future<void> _addCustomModel() async {
    final v = await showTextInputDialog(
      context: context, title: '输入自定义模型', hintText: '例如 gpt-4.1-mini', confirmText: '确定',
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 服务')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _baseUrlCtrl,
            decoration: InputDecoration(
              labelText: 'Base URL',
              hintText: widget.controller.llmProvider.defaultBaseUrl,
            ),
            onChanged: (_) => _saveApi(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API Key'),
            onChanged: (_) => _saveApi(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _checkingApi ? null : _checkApi,
            icon: _checkingApi
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            label: Text(_checkingApi ? '检测中...' : '检测连接'),
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
                  child: Text(_apiMessage!,
                      style: TextStyle(color: _apiMessage!.contains('成功') ? cs.primary : cs.error)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text('模型选择', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _loadingModels ? null : _fetchModels,
                icon: _loadingModels
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: Text(_loadingModels ? '加载中...' : '刷新模型'),
              ),
              OutlinedButton.icon(
                onPressed: _addCustomModel,
                icon: const Icon(Icons.edit),
                label: const Text('自定义模型'),
              ),
            ],
          ),
          if (_modelsError != null) ...[
            const SizedBox(height: 8),
            Text(_modelsError!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 8),
          if (_models.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _selectedModel == null ? '尚未加载模型，可先点击"刷新模型"。' : '当前模型：$_selectedModel',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            Column(
              children: _models.map((String model) {
                final sel = model == _selectedModel;
                return ListTile(
                  dense: true, visualDensity: VisualDensity.compact,
                  leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: sel ? cs.primary : null),
                  title: Text(model),
                  onTap: () { setState(() => _selectedModel = model); _saveModel(); },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
