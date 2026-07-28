import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/service_results.dart';
import '../services/llm_provider.dart';
import '../state/app_controller.dart';
import '../utils/dialogs.dart';
import 'oobe/oobe_steps.dart';

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

  bool get _fixedBaseUrl => widget.controller.llmProvider.fixedBaseUrl;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    final LlmProvider provider = widget.controller.llmProvider;
    _baseUrlController.text =
        provider.fixedBaseUrl ? provider.defaultBaseUrl : settings.baseUrl;
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
        final bool baseOk =
            _fixedBaseUrl || _baseUrlController.text.trim().isNotEmpty;
        return baseOk &&
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

    final ApiCheckResult result = await widget.controller.llmProvider.validateApi(
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

    final ModelFetchResult result = await widget.controller.llmProvider.fetchModels(
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
        const SingleActivator(LogicalKeyboardKey.arrowRight): const NextIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const NextIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): const BackIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const BackIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          NextIntent: CallbackAction<NextIntent>(onInvoke: (_) => _next()),
          BackIntent: CallbackAction<BackIntent>(onInvoke: (_) => _back()),
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
                            StepTracker(stepIndex: _stepIndex),
                            const SizedBox(height: 12),
                            Expanded(
                              child: PageView(
                                controller: _pageController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: <Widget>[
                                  WelcomeStep(),
                                  ApiStep(
                                    baseUrlController: _baseUrlController,
                                    apiKeyController: _apiKeyController,
                                    hideBaseUrl: _fixedBaseUrl,
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
                                  ModelStep(
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
                            OobeFooter(
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


