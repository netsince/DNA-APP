import 'package:flutter/material.dart';

import '../models/prompt_strategy.dart';
import '../models/service_results.dart';
import '../services/auth_service.dart';
import '../state/app_controller.dart';
import '../utils/dialogs.dart';
import '../utils/ui_feedback.dart';
import '../widgets/app_drawer.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _summaryTurnController;
  late final TextEditingController _commandController;

  bool _checkingApi = false;
  bool _loadingModels = false;
  String? _apiMessage;
  String? _modelsError;
  List<String> _models = <String>[];
  String? _selectedModel;
  bool _autoSummaryPrompt = true;
  bool _retrySequential = false;
  bool _inspirationIncludeSummary = false;
  bool _requireAuthForArchive = false;
  bool _requireAuthForApp = false;
  bool _showSplashAnimation = true;
  bool _authAvailable = false;
  late PromptStrategy _promptStrategy;
  static const String _clearCommand =
      'CLEAR ALL DATAS YES I DO THIS PLEASE DEL MY DATAS THANK YOU 114514';

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _baseUrlController = TextEditingController(text: settings.baseUrl);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _selectedModel = settings.selectedModel.isEmpty ? null : settings.selectedModel;
    _autoSummaryPrompt = settings.autoSummaryPrompt;
    _summaryTurnController = TextEditingController(
      text: settings.summaryTurnInterval.toString(),
    );
    _retrySequential = settings.retrySequential;
    _inspirationIncludeSummary = settings.inspirationIncludeSummary;
    _promptStrategy = settings.promptStrategy;
    _requireAuthForArchive = settings.requireAuthForArchive;
    _requireAuthForApp = settings.requireAuthForApp;
    _showSplashAnimation = settings.showSplashAnimation;
    _commandController = TextEditingController();
    _checkAuthAvailability();
  }

  Future<void> _checkAuthAvailability() async {
    final bool available = await AuthService.canCheckBiometrics();
    setState(() => _authAvailable = available);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _summaryTurnController.dispose();
    _commandController.dispose();
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
    showSnack(context, 'API 配置已保存并生效。');
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
    showSnack(context, '模型设置已生效。');
  }

  Future<void> _addCustomModel() async {
    final String? value = await showTextInputDialog(
      context: context,
      title: '输入自定义模型',
      hintText: '例如 gpt-4.1-mini',
      confirmText: '确定',
    );

    if (!mounted || value == null || value.isEmpty) {
      return;
    }
    setState(() {
      _selectedModel = value;
      if (!_models.contains(value)) {
        _models = <String>[value, ..._models];
      }
    });
    await _saveModel();
  }

  Future<void> _restartOobe() async {
    await widget.controller.restartOobe();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _saveSummarySettings() async {
    final int? turns = int.tryParse(_summaryTurnController.text.trim());
    final int normalized = (turns ?? 200).clamp(10, 1000);
    _summaryTurnController.text = normalized.toString();
    await widget.controller.saveSummarySettings(
      autoSummaryPrompt: _autoSummaryPrompt,
      summaryTurnInterval: normalized,
    );
    if (!mounted) {
      return;
    }
    showSnack(context, '摘要设置已保存。');
  }

  Future<void> _saveRetryStrategy() async {
    await widget.controller.saveRetryStrategy(retrySequential: _retrySequential);
    if (!mounted) {
      return;
    }
    showSnack(context, '重说策略已保存。');
  }

  Future<void> _saveInspirationSettings() async {
    await widget.controller.saveInspirationSettings(
      includeSummary: _inspirationIncludeSummary,
    );
    if (!mounted) {
      return;
    }
    showSnack(context, '灵感设置已保存。');
  }

  Future<void> _savePromptStrategySettings() async {
    await widget.controller.savePromptStrategy(_promptStrategy);
    if (!mounted) {
      return;
    }
    showSnack(context, '提示词策略已保存。');
  }

  Future<void> _saveAuthSettings() async {
    await widget.controller.saveAuthSettings(
      requireAuthForArchive: _requireAuthForArchive,
      requireAuthForApp: _requireAuthForApp,
    );
    if (!mounted) {
      return;
    }
    showSnack(context, '安全设置已保存。');
  }

  Future<void> _saveSplashSettings() async {
    await widget.controller.saveSplashAnimation(
      showSplashAnimation: _showSplashAnimation,
    );
    if (!mounted) {
      return;
    }
    showSnack(context, '开场动画设置已保存。');
  }

  Future<void> _runCommand() async {
    final String cmd = _commandController.text;
    if (cmd == _clearCommand) {
      await widget.controller.clearAllData();
      if (!mounted) {
        return;
      }
      _commandController.clear();
      showSnack(context, '数据已清除。');
      return;
    }
    showSnack(context, '未知指令或指令不匹配。');
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
                            onChanged: (_) => _saveApi(),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _apiKeyController,
                            obscureText: true,
                            decoration: const InputDecoration(labelText: 'API Key'),
                            onChanged: (_) => _saveApi(),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
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
                          Text('提示词策略', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 16),
                          Text('推进策略', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('强制推进'),
                                  selected: _promptStrategy.advance == AdvanceStrategy.forced,
                                  onSelected: (bool selected) {
                                    if (selected) {
                                      setState(() {
                                        _promptStrategy = _promptStrategy.copyWith(
                                          advance: AdvanceStrategy.forced,
                                        );
                                      });
                                      _savePromptStrategySettings();
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('自由发展'),
                                  selected: _promptStrategy.advance == AdvanceStrategy.free,
                                  onSelected: (bool selected) {
                                    if (selected) {
                                      setState(() {
                                        _promptStrategy = _promptStrategy.copyWith(
                                          advance: AdvanceStrategy.free,
                                        );
                                      });
                                      _savePromptStrategySettings();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text('沉浸策略', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('克制'),
                                  selected: _promptStrategy.immersion == ImmersionStrategy.restrained,
                                  onSelected: (bool selected) {
                                    if (selected) {
                                      setState(() {
                                        _promptStrategy = _promptStrategy.copyWith(
                                          immersion: ImmersionStrategy.restrained,
                                        );
                                      });
                                      _savePromptStrategySettings();
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('更强'),
                                  selected: _promptStrategy.immersion == ImmersionStrategy.strong,
                                  onSelected: (bool selected) {
                                    if (selected) {
                                      setState(() {
                                        _promptStrategy = _promptStrategy.copyWith(
                                          immersion: ImmersionStrategy.strong,
                                        );
                                      });
                                      _savePromptStrategySettings();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text('字数控制', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('严格 80-120 字'),
                                  selected: _promptStrategy.length == LengthStrategy.strict,
                                  onSelected: (bool selected) {
                                    if (selected) {
                                      setState(() {
                                        _promptStrategy = _promptStrategy.copyWith(
                                          length: LengthStrategy.strict,
                                        );
                                      });
                                      _savePromptStrategySettings();
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('无限制'),
                                  selected: _promptStrategy.length == LengthStrategy.unlimited,
                                  onSelected: (bool selected) {
                                    if (selected) {
                                      setState(() {
                                        _promptStrategy = _promptStrategy.copyWith(
                                          length: LengthStrategy.unlimited,
                                        );
                                      });
                                      _savePromptStrategySettings();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
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
                          Text('灵感', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('灵感附带最近摘要'),
                            subtitle: const Text('开启后会在生成灵感时附带最近摘要。默认关闭以节省 token。'),
                            value: _inspirationIncludeSummary,
                            onChanged: (bool value) {
                              setState(() => _inspirationIncludeSummary = value);
                              _saveInspirationSettings();
                            },
                          ),
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
                          Text('对话摘要', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('允许自动提示摘要'),
                            value: _autoSummaryPrompt,
                            onChanged: (bool value) {
                              setState(() => _autoSummaryPrompt = value);
                              _saveSummarySettings();
                            },
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _summaryTurnController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '触发轮数（按用户消息计）',
                              hintText: '默认 200，范围 10-1000',
                            ),
                            onChanged: (_) => _saveSummarySettings(),
                          ),
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
                          Text('多次发送策略', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('多个请求按顺序单次执行'),
                            subtitle: const Text('开启后重说会顺序发送三次请求。关闭则并发请求三次。'),
                            value: _retrySequential,
                            onChanged: (bool value) {
                              setState(() => _retrySequential = value);
                              _saveRetryStrategy();
                            },
                          ),
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
                                  ? '尚未加载模型，可先点击"刷新模型"。'
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
                                      onTap: () {
                                        setState(() => _selectedModel = model);
                                        _saveModel();
                                      },
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
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text('安全与隐私', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          if (!_authAvailable)
                            Text(
                              '当前设备不支持生物识别验证',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            )
                          else ...[
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('进入软件需验证'),
                              subtitle: const Text('开启后每次进入应用或从后台切回都需要验证身份。'),
                              value: _requireAuthForApp,
                              onChanged: (bool value) {
                                setState(() => _requireAuthForApp = value);
                                _saveAuthSettings();
                              },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('查看归档需验证'),
                              subtitle: const Text('开启后进入任意归档页面需要验证身份。'),
                              value: _requireAuthForArchive,
                              onChanged: (bool value) {
                                setState(() => _requireAuthForArchive = value);
                                _saveAuthSettings();
                              },
                            ),
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
                          Text('引导管理', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('开场动画'),
                            subtitle: const Text('关闭后将直接进入应用，不再播放启动动画。'),
                            value: _showSplashAnimation,
                            onChanged: (bool value) {
                              setState(() => _showSplashAnimation = value);
                              _saveSplashSettings();
                            },
                          ),
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
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text('命令系统', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          const Text('输入命令并执行。命令大小写敏感。'),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _commandController,
                            decoration: const InputDecoration(
                              labelText: '输入命令',
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: _runCommand,
                            child: const Text('执行命令'),
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
