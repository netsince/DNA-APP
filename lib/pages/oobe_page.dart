import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/service_results.dart';
import '../services/llm_provider.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/api_guard.dart';
import '../utils/base_url_guard.dart';
import '../utils/dialogs.dart';
import '../widgets/fit_text.dart';
import 'oobe/community_edit_page.dart';
import 'oobe/oobe_steps.dart';
import 'package:dna/island_app/server_config.dart';

/// 首次启动引导（OOBE）。
///
/// ## 步骤顺序
///
/// 欢迎 → 社区 → API 配置 → 模型选择。社区排在第二位：它是唯一不需要 API Key
/// 就能看到真实内容的部分，而官方地址已经预填好。
///
/// ## 两个出口
///
/// * **先看看**（欢迎页）—— 直接进主界面，不弹劝阻框。这一步用户还没投入成本，
///   不该用「你确定要放弃吗」拦他。
/// * **跳过**（每一步右上角）—— 带二次确认，因为走到后面再跳过意味着前面白填了。
///
/// ## 布局
///
/// 窄屏：顶部横向步骤条 + 表单。宽屏（>= [_wideBreakpoint]）：左栏品牌 + 纵向
/// 步骤条，右栏表单 —— 宽屏下把表单收进一列，避免输入框横跨整屏。
class OobePage extends StatefulWidget {
  const OobePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<OobePage> createState() => _OobePageState();
}

class _OobePageState extends State<OobePage> with TickerProviderStateMixin {
  static const int _stepCount = kOobeStepCount;

  /// 宽到这个程度就换成左右分栏。
  static const double _wideBreakpoint = 1000;

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _communityUrlController = TextEditingController();

  late final PageController _pageController;

  int _stepIndex = 0;

  /// 已经到过的最远步骤：步骤条允许点回/点前跳到 <= 它的任意一步。
  int _maxReached = 0;

  bool _checkingApi = false;
  bool _apiValidated = false;
  String? _apiError;
  bool _ignoreApiIssue = false;

  /// 社区那一步的连通状态（在编辑页里检测，返回后展示在折叠摘要上）。
  CommunityStepStatus _communityStatus = CommunityStepStatus.unchecked;

  bool _loadingModels = false;
  String? _modelsError;
  List<String> _models = <String>[];
  String? _selectedModel;

  bool get _fixedBaseUrl => widget.controller.llmProvider.fixedBaseUrl;

  bool get _requiresApiKey => widget.controller.llmProvider.requiresApiKey;

  bool get _communityEnabled => widget.controller.settings.enableCommunity;

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
    // 社区地址：默认官方地址；已配过自定义地址的沿用旧值。
    _communityUrlController.text = ServerConfig.defaultBaseUrl;
    _loadCommunityUrl();
    _pageController = PageController();

    // 固定地址的服务商（DeepSeek / 智谱）地址不由用户填写。启动时就把默认地址
    // 落盘，否则用户直接「跳过」或「先看看」会让配置里的 baseUrl 空着，
    // 请求会拼出 /chat/completions 这种残缺 URL。设置页有同样的处理。
    if (provider.fixedBaseUrl) {
      _persistFixedBaseUrl();
    }
  }

  /// 把「固定地址服务商」的默认地址落盘。
  ///
  /// fire-and-forget：落盘失败不该挡住用户进入引导，下一次检测或保存会再写一遍。
  Future<void> _persistFixedBaseUrl() async {
    await widget.controller.saveApiConfig(
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
    );
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

  /// API 那一步是否已经可以继续。
  bool get _apiReady {
    final bool baseOk = _fixedBaseUrl ||
        (_baseUrlController.text.trim().isNotEmpty &&
            baseUrlFormatError(_baseUrlController.text) == null);
    final bool keyOk =
        !_requiresApiKey || _apiKeyController.text.trim().isNotEmpty;
    return baseOk &&
        keyOk &&
        (_apiValidated || (_apiError != null && _ignoreApiIssue));
  }

  bool get _canGoNext {
    switch (_stepIndex) {
      case 0:
      case 1:
        // 欢迎与社区都不拦人：社区有官方默认值，校验与忽略都在编辑页里。
        return true;
      case 2:
        return _apiReady;
      case 3:
        return (_selectedModel ?? '').trim().isNotEmpty;
      default:
        return false;
    }
  }

  /// 主按钮为什么还不能点。
  ///
  /// 禁用态只把按钮灰掉、不说明缺什么，是首次引导里最劝退的一种交互：用户会以为
  /// 自己填错了，却不知道错在哪。这里把「缺哪一项」翻译成一句话交给页脚显示。
  String? get _nextHint {
    if (_canGoNext) {
      return null;
    }
    switch (_stepIndex) {
      case 2:
        if (!_fixedBaseUrl) {
          if (_baseUrlController.text.trim().isEmpty) {
            return '请先填写 Base URL。';
          }
          final String? formatError =
              baseUrlFormatError(_baseUrlController.text);
          if (formatError != null) return formatError;
        }
        if (_requiresApiKey && _apiKeyController.text.trim().isEmpty) {
          return '请先填写 API Key。';
        }
        return '请点「保存并检测 API」完成检测，或勾选「忽略此问题」继续。';
      case 3:
        return '请从列表里选一个模型，或添加自定义模型。';
      default:
        return null;
    }
  }

  Future<void> _selectProvider(LlmProvider provider) async {
    if (provider.id == widget.controller.settings.provider) {
      return;
    }
    final LlmProvider oldProvider = widget.controller.llmProvider;
    final String oldDefault = oldProvider.defaultBaseUrl;
    await widget.controller.saveProvider(provider.id);
    final LlmProvider newProvider = widget.controller.llmProvider;
    setState(() {
      _apiValidated = false;
      _apiError = null;
      _ignoreApiIssue = false;
      // 模型列表属于上一个服务商，换家就作废。
      _models = <String>[];
      _modelsError = null;
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

    ApiCheckResult? result;
    try {
      result = await widget.controller.llmProvider.validateApi(
        baseUrl: _baseUrlController.text,
        apiKey: _apiKeyController.text,
      );
    } catch (_) {
      // 校验器约定不抛异常，但真抛了也不能把按钮永远留在转圈状态。
      result = const ApiCheckResult(success: false, message: '检测失败，请稍后重试。');
    }

    if (!mounted) {
      return;
    }
    final ApiCheckResult checked = result;
    setState(() {
      _checkingApi = false;
      _apiValidated = checked.success;
      // 失败文案附加明文 HTTP 警示(成功态由 _apiValidated 绿标表达,不混入错误区)。
      _apiError = checked.success
          ? null
          : withTransportWarning(_baseUrlController.text, checked.message);
    });

    // 检测通过就顺手把模型列表拉回来：用户走到下一步时列表已经就绪，
    // 不用再对着转圈等一次。
    if (checked.success && mounted) {
      await _loadModels();
    }
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });

    ModelFetchResult? result;
    try {
      result = await widget.controller.llmProvider.fetchModels(
        baseUrl: _baseUrlController.text,
        apiKey: _apiKeyController.text,
      );
    } catch (_) {
      result = const ModelFetchResult(
        models: <String>[],
        errorMessage: '拉取模型列表失败，请稍后重试。',
      );
    }

    if (!mounted) {
      return;
    }
    final ModelFetchResult fetched = result;
    setState(() {
      _loadingModels = false;
      _models = fetched.models;
      _modelsError = fetched.errorMessage;
      if (_selectedModel == null || _selectedModel!.isEmpty) {
        _selectedModel =
            fetched.models.isNotEmpty ? fetched.models.first : null;
      }
      if (_selectedModel != null &&
          _selectedModel!.isNotEmpty &&
          !fetched.models.contains(_selectedModel)) {
        _models = <String>[_selectedModel!, ...fetched.models];
      }
    });
  }

  /// 打开社区编辑页；返回后把结果反映到折叠摘要上。
  Future<void> _openCommunityEdit() async {
    final CommunityEditResult? result =
        await Navigator.of(context).push<CommunityEditResult>(
      MaterialPageRoute<CommunityEditResult>(
        builder: (BuildContext context) => CommunityEditPage(
          initialUrl: _communityUrlController.text,
          defaultUrl: ServerConfig.defaultBaseUrl,
          enableCommunity: _communityEnabled,
          onToggleCommunity: (bool value) =>
              widget.controller.saveEnableCommunity(value),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      if (result != null) {
        _communityUrlController.text = result.url;
        _communityStatus = result.status;
      }
    });
  }

  Future<void> _persistCommunity() async {
    if (!_communityEnabled) {
      return;
    }
    final String base = ServerConfig.normalize(_communityUrlController.text);
    if (base.isNotEmpty) {
      await ServerConfig.setBaseUrl(base);
    }
  }

  Future<void> _next() async {
    if (!mounted) {
      return;
    }
    switch (_stepIndex) {
      case 0:
        await _goToStep(1);
        return;
      case 1:
        await _persistCommunity();
        if (!mounted) {
          return;
        }
        await _goToStep(2);
        return;
      case 2:
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
        await _goToStep(3);
        // 检测成功时已经预取过；这里兜一次（例如用户改过地址但没重新检测）。
        if (mounted && _models.isEmpty && !_loadingModels) {
          await _loadModels();
        }
        return;
      case 3:
        if (!_canGoNext) {
          return;
        }
        await widget.controller.saveSelectedModel(_selectedModel!.trim());
        await widget.controller.completeOobe();
        return;
    }
  }

  /// 「先看看」：不弹劝阻框直接进主界面。
  Future<void> _lookAround() async {
    await widget.controller.completeOobe();
  }

  Future<void> _skipOobe() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const FitText('跳过引导？'),
        content: const FitText(
          '跳过后需要自行在「设置」里配置服务商、API Key 与模型，否则无法使用对话功能。'
          '社区用官方地址即可，不需要配置。',
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
    setState(() {
      _stepIndex = index;
      if (index > _maxReached) _maxReached = index;
    });
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

  /// 英雄位边长：随可用高度线性缩放，40 起步、96 封顶。
  ///
  /// 屏幕矮就画小一点，但**不隐藏** —— 完全消失会让每一步看起来一样平。
  /// 下限 40 是「再小就不像图形、只剩噪点」的界线（正好也是原来那个图标块的尺寸）。
  static double _heroSizeFor(double availableHeight) =>
      (availableHeight * 0.11).clamp(40.0, 96.0);

  /// 四个步骤的页面。
  Widget _buildPages(double heroSize) {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        WelcomeStep(onLookAround: _lookAround),
        CommunityStep(
          enabled: _communityEnabled,
          url: _communityUrlController.text,
          defaultUrl: ServerConfig.defaultBaseUrl,
          status: _communityStatus,
          heroSize: heroSize,
          onEdit: _openCommunityEdit,
        ),
        ApiStep(
          providers: widget.controller.llmProviders,
          selectedProviderId: widget.controller.settings.provider,
          baseUrlController: _baseUrlController,
          apiKeyController: _apiKeyController,
          baseUrlHint: widget.controller.llmProvider.defaultBaseUrl,
          hideBaseUrl: _fixedBaseUrl,
          requiresApiKey: _requiresApiKey,
          heroSize: heroSize,
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
          onSelect: (String model) {
            setState(() => _selectedModel = model);
          },
          onCustom: _showCustomModelDialog,
          heroSize: heroSize,
        ),
      ],
    );
  }

  /// 步骤卡片 + 页脚。窄屏与宽屏共用。
  Widget _buildFlow(double heroSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: _buildPages(heroSize)),
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.md),
        OobeFooter(
          stepIndex: _stepIndex,
          canGoNext: _canGoNext,
          onBack: _back,
          onNext: _next,
          hint: _nextHint,
          ignoreIssue:
              (_apiError != null && _ignoreApiIssue),
        ),
      ],
    );
  }

  Widget _buildTracker({Axis axis = Axis.horizontal}) {
    return StepTracker(
      stepIndex: _stepIndex,
      maxReached: _maxReached,
      onStepSelected: _goToStep,
      axis: axis,
    );
  }

  /// 宽屏左栏：标题 + 纵向步骤条。
  ///
  /// 这里**不再放品牌标**：右栏每一步的头部现在都有英雄位（欢迎页本身就是
  /// 那个大标），左栏再来一个就是同一个图形出现两次。左栏的职责是导航。
  Widget _buildRail() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FitText(
              kOobeSteps[0].title,
              style: AppTextStyles.headline(theme),
            ),
            AppSpacing.hXs,
            FitText(
              '首次启动引导',
              style: AppTextStyles.caption(
                theme,
              ).copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        AppSpacing.hXl,
        _buildTracker(axis: Axis.vertical),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 回车**不再**全局绑定为「下一步」：焦点在输入框里时，回车应该由输入框
    // 自己消费（API Key 框的 onSubmitted 会触发检测），全局快捷键会和它打架。
    // 方向键与 Esc 由各自的控件优先处理，冲突风险低，保留。
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowRight): const NextIntent(),
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
                  // 每一步都能跳过：走到后面卡住的人不该被迫退回第一步。
                  TextButton(
                    onPressed: _skipOobe,
                    child: const FitText('跳过'),
                  ),
                ],
              ),
              body: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide =
                      constraints.maxWidth >= _wideBreakpoint;
                  // 英雄位随可用高度缩放：矮屏画小，但不消失。
                  final double heroSize = _heroSizeFor(constraints.maxHeight);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              SizedBox(width: 260, child: _buildRail()),
                              const SizedBox(width: AppSpacing.xl),
                              Expanded(
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: AppSize.editorMaxWidth,
                                    ),
                                    child: _buildFlow(heroSize),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _buildTracker(),
                              const SizedBox(height: AppSpacing.md),
                              Expanded(
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: AppSize.editorMaxWidth,
                                    ),
                                    child: _buildFlow(heroSize),
                                  ),
                                ),
                              ),
                            ],
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
