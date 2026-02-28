import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/service_results.dart';
import '../state/app_controller.dart';
import '../utils/dialogs.dart';
import '../utils/ui_feedback.dart';

class OobePage extends StatefulWidget {
  const OobePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<OobePage> createState() => _OobePageState();
}

class _OobePageState extends State<OobePage> with TickerProviderStateMixin {
  static const int _stepCount = 3;

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  late final PageController _pageController;

  int _stepIndex = 0;
  bool _checkingApi = false;
  bool _apiValidated = false;
  String? _apiError;
  bool _ignoreApiIssue = false;

  bool _loadingModels = false;
  String? _modelsError;
  List<String> _models = <String>[];
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _baseUrlController.text = settings.baseUrl;
    _apiKeyController.text = settings.apiKey;
    if (settings.selectedModel.isNotEmpty) {
      _selectedModel = settings.selectedModel;
    }
    _pageController = PageController();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool get _canGoNext {
    switch (_stepIndex) {
      case 0:
        return true;
      case 1:
        return _baseUrlController.text.trim().isNotEmpty &&
            _apiKeyController.text.trim().isNotEmpty &&
            (_apiValidated || (_apiError != null && _ignoreApiIssue));
      case 2:
        return (_selectedModel ?? '').trim().isNotEmpty;
      default:
        return false;
    }
  }

  Future<void> _checkApi() async {
    setState(() {
      _checkingApi = true;
      _apiValidated = false;
      _apiError = null;
      _ignoreApiIssue = false;
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
      _apiValidated = result.success;
      _apiError = result.success ? null : result.message;
    });
  }

  Future<void> _loadModels() async {
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
      if (_selectedModel == null || _selectedModel!.isEmpty) {
        _selectedModel = result.models.isNotEmpty ? result.models.first : null;
      }
      if (_selectedModel != null &&
          _selectedModel!.isNotEmpty &&
          !result.models.contains(_selectedModel)) {
        _models = <String>[_selectedModel!, ...result.models];
      }
    });
  }

  Future<void> _next() async {
    if (!mounted) {
      return;
    }
    if (_stepIndex == 0) {
      await _goToStep(1);
      return;
    }
    if (_stepIndex == 1) {
      if (!_canGoNext) {
        return;
      }
      await widget.controller.saveApiConfig(
        baseUrl: _baseUrlController.text,
        apiKey: _apiKeyController.text,
      );
      if (!mounted) {
        return;
      }
      await _goToStep(2);
      await _loadModels();
      return;
    }
    if (_stepIndex == 2 && _canGoNext) {
      await widget.controller.saveSelectedModel(_selectedModel!.trim());
      await widget.controller.completeOobe();
    }
  }

  Future<void> _back() async {
    if (!mounted) {
      return;
    }
    if (_stepIndex == 0) {
      return;
    }
    await _goToStep(_stepIndex - 1);
  }

  Future<void> _goToStep(int index) async {
    if (index < 0 || index >= _stepCount) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _stepIndex = index);
    if (!mounted) {
      return;
    }
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _showCustomModelDialog() async {
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
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowRight): const _NextIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const _NextIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): const _BackIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const _BackIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _NextIntent: CallbackAction<_NextIntent>(onInvoke: (_) => _next()),
          _BackIntent: CallbackAction<_BackIntent>(onInvoke: (_) => _back()),
        },
        child: Focus(
          autofocus: true,
          child: GestureDetector(
            onHorizontalDragEnd: (DragEndDetails details) {
              final double velocity = details.primaryVelocity ?? 0;
              if (velocity < -300) {
                _next();
              } else if (velocity > 300) {
                _back();
              }
            },
            child: Scaffold(
              appBar: AppBar(
                title: const Text('首次启动引导'),
              ),
              body: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double maxWidth = constraints.maxWidth > 900 ? 900 : constraints.maxWidth;
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _StepTracker(stepIndex: _stepIndex),
                            const SizedBox(height: 12),
                            Expanded(
                              child: PageView(
                                controller: _pageController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: <Widget>[
                                  _WelcomeStep(),
                                  _ApiStep(
                                    baseUrlController: _baseUrlController,
                                    apiKeyController: _apiKeyController,
                                    checkingApi: _checkingApi,
                                    apiValidated: _apiValidated,
                                    apiError: _apiError,
                                    ignoreApiIssue: _ignoreApiIssue,
                                    onIgnoreChanged: (bool value) {
                                      setState(() => _ignoreApiIssue = value);
                                    },
                                    onCheck: _checkApi,
                                    onInputChanged: () {
                                      setState(() {
                                        _apiValidated = false;
                                        _apiError = null;
                                        _ignoreApiIssue = false;
                                      });
                                    },
                                  ),
                                  _ModelStep(
                                    loadingModels: _loadingModels,
                                    models: _models,
                                    modelsError: _modelsError,
                                    selectedModel: _selectedModel,
                                    onReload: _loadModels,
                                    onSelect: (String? model) {
                                      setState(() => _selectedModel = model);
                                    },
                                    onCustom: _showCustomModelDialog,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _Footer(
                              stepIndex: _stepIndex,
                              canGoNext: _canGoNext,
                              onBack: _back,
                              onNext: _next,
                              ignoreApiIssue: _apiError != null && _ignoreApiIssue,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepTracker extends StatelessWidget {
  const _StepTracker({required this.stepIndex});

  final int stepIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(3, (int index) {
        final bool isActive = index <= stepIndex;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
        );
      }),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('与汝共奏', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('将通过 3 个步骤完成首次配置。', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            const _StepBullet(text: '配置 API Base URL 与 API Key，并完成连接检测'),
            const _StepBullet(text: '自动拉取模型或手动添加自定义模型'),
            const _StepBullet(text: '完成后即可进入主界面'),
            const Spacer(),
            Text(
              '提示：方向键或滑动手势可在步骤之间移动。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepBullet extends StatelessWidget {
  const _StepBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ApiStep extends StatelessWidget {
  const _ApiStep({
    required this.baseUrlController,
    required this.apiKeyController,
    required this.checkingApi,
    required this.apiValidated,
    required this.apiError,
    required this.ignoreApiIssue,
    required this.onIgnoreChanged,
    required this.onCheck,
    required this.onInputChanged,
  });

  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final bool checkingApi;
  final bool apiValidated;
  final String? apiError;
  final bool ignoreApiIssue;
  final ValueChanged<bool> onIgnoreChanged;
  final VoidCallback onCheck;
  final VoidCallback onInputChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: <Widget>[
            Text('步骤 1/3 · API 配置', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.openai.com/v1',
              ),
              onChanged: (_) => onInputChanged(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API Key'),
              onChanged: (_) => onInputChanged(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: checkingApi ? null : onCheck,
              icon: checkingApi
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(checkingApi ? '检测中...' : '保存并检测 API'),
            ),
            if (apiValidated) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                '连接验证成功。',
                style: TextStyle(color: Colors.green.shade700),
              ),
            ],
            if (apiError != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                apiError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              CheckboxListTile(
                value: ignoreApiIssue,
                title: const Text('忽略此问题'),
                subtitle: const Text('勾选后允许跳过本次检测并进入下一步。'),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (bool? value) => onIgnoreChanged(value ?? false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelStep extends StatelessWidget {
  const _ModelStep({
    required this.loadingModels,
    required this.models,
    required this.modelsError,
    required this.selectedModel,
    required this.onReload,
    required this.onSelect,
    required this.onCustom,
  });

  final bool loadingModels;
  final List<String> models;
  final String? modelsError;
  final String? selectedModel;
  final VoidCallback onReload;
  final ValueChanged<String?> onSelect;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('步骤 2/3 · 模型选择', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: loadingModels ? null : onReload,
                  icon: loadingModels
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(loadingModels ? '加载中...' : '刷新模型列表'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onCustom,
                  icon: const Icon(Icons.edit),
                  label: const Text('自定义模型'),
                ),
              ],
            ),
            if (modelsError != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                modelsError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: loadingModels
                    ? const Center(child: CircularProgressIndicator())
                    : models.isEmpty
                        ? const Center(child: Text('暂无可用模型，请先刷新或使用自定义模型。'))
                        : ListView.builder(
                            itemCount: models.length,
                            itemBuilder: (BuildContext context, int index) {
                              final String model = models[index];
                              final bool selected = model == selectedModel;
                              return ListTile(
                                leading: Icon(
                                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                ),
                                title: Text(model),
                                onTap: () => onSelect(model),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.stepIndex,
    required this.canGoNext,
    required this.onBack,
    required this.onNext,
    required this.ignoreApiIssue,
  });

  final int stepIndex;
  final bool canGoNext;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final bool ignoreApiIssue;

  @override
  Widget build(BuildContext context) {
    final String nextLabel;
    if (stepIndex == 0) {
      nextLabel = '开始';
    } else if (stepIndex == 1) {
      nextLabel = ignoreApiIssue ? '忽略并继续' : '下一步';
    } else {
      nextLabel = '完成';
    }

    return Row(
      children: <Widget>[
        OutlinedButton(
          onPressed: stepIndex == 0 ? null : onBack,
          child: const Text('上一步'),
        ),
        const Spacer(),
        FilledButton(
          onPressed: canGoNext ? onNext : null,
          child: Text(nextLabel),
        ),
      ],
    );
  }
}

class _NextIntent extends Intent {
  const _NextIntent();
}

class _BackIntent extends Intent {
  const _BackIntent();
}
