import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _apiKeyController;
  late TextEditingController _baseUrlController;
  late TextEditingController _customModelController;
  
  String? _selectedModel;
  List<String> _availableModels = [];
  bool _isLoadingModels = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _baseUrlController = TextEditingController(text: settings.baseUrl);
    _customModelController = TextEditingController();
    _selectedModel = settings.selectedModel;
    _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() => _isLoadingModels = true);
    final settings = context.read<SettingsProvider>();
    final models = await settings.fetchAvailableModels();
    setState(() {
      _availableModels = models;
      _isLoadingModels = false;
      if (!models.contains(_selectedModel) && _selectedModel != null) {
        _availableModels.add(_selectedModel!);
      }
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final settings = context.read<SettingsProvider>();
    await settings.setApiKey(_apiKeyController.text.trim());
    await settings.setBaseUrl(_baseUrlController.text.trim());
    if (_selectedModel != null) {
      await settings.setSelectedModel(_selectedModel!);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'API 配置',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              border: OutlineInputBorder(),
              hintText: 'sk-...',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            '模型选择',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (_isLoadingModels)
            const Center(child: CircularProgressIndicator())
          else
            DropdownButtonFormField<String>(
              value: _selectedModel,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                ..._availableModels.map((m) => DropdownMenuItem(value: m, child: Text(m))),
                const DropdownMenuItem(value: 'custom', child: Text('自定义模型...')),
              ],
              onChanged: (val) {
                if (val == 'custom') {
                  _showCustomModelDialog();
                } else {
                  setState(() => _selectedModel = val);
                }
              },
            ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _saveSettings,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('保存所有设置'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          TextButton(
            onPressed: () async {
              final settings = context.read<SettingsProvider>();
              await settings.resetFirstRun();
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
              }
            },
            child: const Text('重置首次启动状态 (调试用)', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCustomModelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义模型'),
        content: TextField(
          controller: _customModelController,
          decoration: const InputDecoration(hintText: '输入模型 ID'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              if (_customModelController.text.isNotEmpty) {
                setState(() {
                  _selectedModel = _customModelController.text.trim();
                  if (!_availableModels.contains(_selectedModel)) {
                    _availableModels.add(_selectedModel!);
                  }
                });
              }
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
