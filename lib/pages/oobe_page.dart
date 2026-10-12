import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/service_results.dart';
import '../services/llm_provider.dart';
import '../state/app_controller.dart';
import '../utils/api_guard.dart';
import '../utils/dialogs.dart';
import 'oobe/oobe_steps.dart';
import 'package:dna/island_app/api/client.dart' show ApiClient;
import 'package:dna/island_app/server_config.dart';
import 'package:dna/widgets/fit_text.dart';

class OobePage extends StatefulWidget {
  const OobePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<OobePage> createState() => _OobePageState();
}

class _OobePageState extends State<OobePage> with TickerProviderStateMixin {
  static const int _stepCount = kOobeStepCount;

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _communityUrlController = TextEditingController();

  late final PageController _pageController;

  int _stepIndex = 0;
  bool _checkingApi = false;
  bool _apiValidated = false;
  String? _apiError;
  bool _ignoreApiIssue = false;

  /// 社区（DNAISLAND 服务器地址）那一步的状态：与社区内部的「服务器地址」设置同一套
  /// 校验与默认值，连不上可以勾「忽略此问题」继续。
  bool _checkingCommunity = false;
  bool _communityValidated = false;
  String? _communityError;
  bool _ignoreCommunityIssue = false;

  bool _loadingModels = false;
  String? _modelsError;
  List<String> _models = <String>[];
  String? _selectedModel;

  bool get _fixedBaseUrl => widget.controller.llmProvider.fixedBaseUrl;

  Future<void> _selectProvider(String id) async {
    if (id == widget.controller.settings.provider) {
      return;
    }
    final LlmProvider oldProvider = widget.controller.llmProvider;
    final String oldDefault = oldProvider.defaultBaseUrl;
    await widget.controller.saveProvider(id);
    final LlmProvider newProvider = widget.controller.llmProvider;
    setState(() {
      _apiValidated = false;
      _apiError = null;
      _ignoreApiIssue = false;
      _selectedModel = null;
      if (newProvider.fixedBaseUrl) {
        _baseUrlController.text = newProvider.defaultBaseUrl;
      } else if (_baseUrlController.text.trim().isEmpty ||
          _baseUrlController.text.trim() == oldDefault) {
        // 之前是自动填充的默认值（或为空），替换为新厂商默认值，避免旧地址泄漏。
        _baseUrlController.text = newProvider.defaultBaseUrl;
      }
    });
  }

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
    // 社区地址：默认官方地址（与社区内部 OOBE 一致）；已配过自定义地址的沿用旧值。
    _communityUrlController.text = ServerConfig.defaultBaseUrl;
    _loadCommunityUrl();
    _pageController = PageController();
  }

  /// 读取已保存的社区地址；没有（或为空）就保持官方默认值。
  Future<void> _loadCommunityUrl() async {
    final String saved = await ServerConfig.getBaseUrl();
    if (!mounted) {
      return;
    }
    setState(() {
      _communityUrlController.text =
          saved.trim().isEmpty ? ServerConfig.defaultBaseUrl : saved;
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _communityUrlController.dispose();
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
      case 3:
        // 社区：填了地址，且（检测通过 或 检测失败但勾了忽略）—— 与 API 那步同规则。
        return _communityUrlController.text.trim().isNotEmpty &&
            (_communityValidated ||
                (_communityError != null && _ignoreCommunityIssue));
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
      // 失败文案附加明文 HTTP 警示(成功态由 _apiValidated 绿标表达,不混入错误区)。
      _apiError = result.success
          ? null
          : withTransportWarning(_baseUrlController.text, result.message);
    });
  }

  /// 保存并检测社区服务器地址。
  ///
  /// 与社区内部的「服务器地址」用同一个校验器（[ApiClient.validateServer]），
  /// 所以这里通过的东西进社区后一定能用；失败时允许勾「忽略此问题」继续。
  Future<void> _checkCommunity() async {
    final String base = ServerConfig.normalize(_communityUrlController.text);
    if (base.isEmpty) {
      setState(() {
        _communityValidated = false;
        _communityError = '请输入社区服务器地址';
        _ignoreCommunityIssue = false;
      });
      return;
    }
    setState(() {
      _checkingCommunity = true;
      _communityValidated = false;
      _communityError = null;
      _ignoreCommunityIssue = false;
    });

    // 与 API 那步一致：先落盘再检测，检测失败也不会丢掉用户填的地址。
    await ServerConfig.setBaseUrl(base);
    if (!mounted) {
      return;
    }
    final String? error = await ApiClient.instance.validateServer(base);
    if (!mounted) {
      return;
    }
    setState(() {
      _checkingCommunity = false;
      _communityValidated = error == null;
      _communityError = error;
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
      await _goToStep(3);
      return;
    }
    if (_stepIndex == 3 && _canGoNext) {
      // 社区地址落盘：即使检测失败（用户勾了忽略）也存下来，之后可在社区设置里改。
      final String base = ServerConfig.normalize(_communityUrlController.text);
      if (base.isNotEmpty) {
        await ServerConfig.setBaseUrl(base);
      }
      if (!mounted) {
        return;
      }
      await widget.controller.completeOobe();
    }
  }

  Future<void> _skipOobe() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const FitText('跳过引导？'),
        content: const FitText(
          '如果你跳过了 OOBE，需要自行在「设置」中配置服务商、API Key 与模型等相关设置项，否则可能无法正常使用对话功能。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const FitText('继续设置'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const FitText('仍然跳过'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
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
                title: const FitText('首次启动引导'),
                actions: <Widget>[
                  if (_stepIndex == 0)
                    TextButton(
                      onPressed: _skipOobe,
                      child: const FitText('跳过'),
                    ),
                ],
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
                                    providers: widget.controller.llmProviders,
                                    selectedProviderId: widget.controller.settings.provider,
                                    baseUrlController: _baseUrlController,
                                    apiKeyController: _apiKeyController,
                                    baseUrlHint: widget.controller.llmProvider.defaultBaseUrl,
                                    hideBaseUrl: _fixedBaseUrl,
                                    checkingApi: _checkingApi,
                                    apiValidated: _apiValidated,
                                    apiError: _apiError,
                                    ignoreApiIssue: _ignoreApiIssue,
                                    onIgnoreChanged: (bool value) {
                                      setState(() => _ignoreApiIssue = value);
                                    },
                                    onProviderChanged: _selectProvider,
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
                                  CommunityStep(
                                    urlController: _communityUrlController,
                                    defaultUrl: ServerConfig.defaultBaseUrl,
                                    checking: _checkingCommunity,
                                    validated: _communityValidated,
                                    error: _communityError,
                                    ignoreIssue: _ignoreCommunityIssue,
                                    onIgnoreChanged: (bool value) {
                                      setState(
                                          () => _ignoreCommunityIssue = value);
                                    },
                                    onCheck: _checkCommunity,
                                    onUseDefault: () {
                                      setState(() {
                                        _communityUrlController.text =
                                            ServerConfig.defaultBaseUrl;
                                        _communityValidated = false;
                                        _communityError = null;
                                        _ignoreCommunityIssue = false;
                                      });
                                    },
                                    onInputChanged: () {
                                      setState(() {
                                        _communityValidated = false;
                                        _communityError = null;
                                        _ignoreCommunityIssue = false;
                                      });
                                    },
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
                              ignoreIssue: (_apiError != null &&
                                      _ignoreApiIssue) ||
                                  (_communityError != null &&
                                      _ignoreCommunityIssue),
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


