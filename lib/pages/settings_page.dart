import 'package:flutter/material.dart';

import '../models/service_results.dart';
import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';
import 'dialogue_style_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;

  bool _checkingApi = false;
  bool _loadingModels = false;
  String? _apiMessage;
  String? _modelsError;
  List<String> _models = <String>[];
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _baseUrlController = TextEditingController(text: settings.baseUrl);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _selectedModel = settings.selectedModel.isEmpty ? null : settings.selectedModel;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveApi() async {
    await widget.controller.saveApiConfig(
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API 配置已保存并生效。')),
    );
  }

  Future<void> _checkApi() async {
    setState(() {
      _checkingApi = true;
      _apiMessage = null;
    });

    await widget.controller.saveApiConfig(
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
    );

    final ApiCheckResult result = await widget.controller.openAiService.validateApi(
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _checkingApi = false;
      _apiMessage = result.message;
    });
  }

  Future<void> _fetchModels() async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });

    final ModelFetchResult result = await widget.controller.openAiService.fetchModels(
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _loadingModels = false;
      _models = result.models;
      _modelsError = result.errorMessage;
      if ((_selectedModel ?? '').isEmpty && _models.isNotEmpty) {
        _selectedModel = _models.first;
      }
      if (_selectedModel != null &&
          _selectedModel!.isNotEmpty &&
          !_models.contains(_selectedModel)) {
        _models = <String>[_selectedModel!, ..._models];
      }
    });
  }

  Future<void> _saveModel() async {
    if ((_selectedModel ?? '').trim().isEmpty) {
      return;
    }
    await widget.controller.saveSelectedModel(_selectedModel!.trim());
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('模型设置已生效。')),
    );
  }

  Future<void> _addCustomModel() async {
    final TextEditingController controller = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('输入自定义模型'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '例如 gpt-4.1-mini'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (!mounted || value == null || value.isEmpty) {
      return;
    }
    setState(() {
      _selectedModel = value;
      if (!_models.contains(value)) {
        _models = <String>[value, ..._models];
      }
    });
  }

  Future<void> _restartOobe() async {
    await widget.controller.restartOobe();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      drawer: AppDrawer(controller: widget.controller, current: AppSection.settings),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double maxWidth = constraints.maxWidth > 900 ? 900 : constraints.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text('API 配置', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _baseUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Base URL',
                              hintText: 'https://api.openai.com/v1',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _apiKeyController,
                            obscureText: true,
                            decoration: const InputDecoration(labelText: 'API Key'),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
                              FilledButton(
                                onPressed: _saveApi,
                                child: const Text('保存 API'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _checkingApi ? null : _checkApi,
                                icon: _checkingApi
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.network_check),
                                label: Text(_checkingApi ? '检测中...' : '检测连接'),
                              ),
                            ],
                          ),
                          if (_apiMessage != null) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(_apiMessage!),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text('模型选择', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
                              FilledButton.tonalIcon(
                                onPressed: _loadingModels ? null : _fetchModels,
                                icon: _loadingModels
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh),
                                label: Text(_loadingModels ? '加载中...' : '刷新模型'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _addCustomModel,
                                icon: const Icon(Icons.edit),
                                label: const Text('自定义模型'),
                              ),
                              FilledButton(
                                onPressed: (_selectedModel ?? '').isEmpty ? null : _saveModel,
                                child: const Text('保存模型'),
                              ),
                            ],
                          ),
                          if (_modelsError != null) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(
                              _modelsError!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (_models.isEmpty)
                            Text(
                              _selectedModel == null
                                  ? '尚未加载模型，可先点击“刷新模型”。'
                                  : '当前模型：$_selectedModel',
                            )
                          else
                            Column(
                              children: _models
                                  .map(
                                    (String model) => ListTile(
                                      leading: Icon(
                                        model == _selectedModel
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_unchecked,
                                      ),
                                      title: Text(model),
                                      onTap: () => setState(() => _selectedModel = model),
                                    ),
                                  )
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: const Text('对话风格'),
                      subtitle: const Text('编辑“我一句你一句”的对话风格。'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) => DialogueStylePage(controller: widget.controller),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text('引导管理', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          const Text('可重新进入首次启动引导流程。'),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _restartOobe,
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('重新进入 OOBE'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
