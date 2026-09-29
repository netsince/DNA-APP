// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import '../../services/llm_provider.dart';
import '../../state/app_controller.dart';
import '../../utils/api_guard.dart';
import '../../utils/dialogs.dart';
import 'ai_service/advanced_view.dart';
import 'ai_service/contract.dart';
import 'ai_service/simple_view.dart';
import 'ai_service_more_page.dart';

/// 设置 → AI 服务主页。
///
/// ## 页面分工
///
/// * **精简模式**主页:服务商选择、Base URL / API Key、连接检测、
///   模型列表 —— 只放「把模型接通并用起来」需要的东西;
/// * **完整模式**主页:**平铺的模型快速切换列表**(不再有卡片和弹窗);
/// * **右上角 `⋮`** → [AiServiceMorePage]:分栏页,精简模式只有「其他」,
///   完整模式有「模型 / 服务商 / 其他」。简易模式开关与全局采样参数
///   都收在「其他」栏里。
///
/// ## 本文件只做装配
///
/// 页面状态(两个输入框控制器、连接检测、模型列表)与全部业务逻辑
/// 都留在这里;两个分支的**视图**分别委托给:
///
/// * `ai_service/simple_view.dart` —— 精简模式视图;
/// * `ai_service/advanced_view.dart` —— 完整模式的平铺模型列表;
/// * `ai_service/contract.dart` —— 子组件接收的参数与回调契约。
///
/// ## 为什么用「契约对象」而不是散装参数
///
/// 本页**曾经被拆坏过一次**:旧拆分把 `baseUrlController` /
/// `apiKeyController` 作为参数传给子组件却从未使用,精简模式渲染出来
/// 一个输入框都没有,用户切过去只看到模式开关。代码能编译、
/// `flutter analyze` 干净、行数也正常 —— 静态手段查不出来。
///
/// 现在子组件统一接收 [AiServicePageContract],缺字段直接编译失败,
/// 不会静默丢失;另有 `test/ai_service_page_render_test.dart` 真正把
/// 页面渲染出来断言配置项存在,锁死这个回归。
class AiServiceSettingsPage extends StatefulWidget {
  const AiServiceSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AiServiceSettingsPage> createState() => _AiServiceSettingsPageState();
}

class _AiServiceSettingsPageState extends State<AiServiceSettingsPage> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;

  /// 两个控制器是否已创建(`late final` 只能赋值一次)。
  bool _controllersReady = false;

  bool _checkingApi = false;
  bool _loadingModels = false;
  String? _apiMessage;
  String? _modelsError;
  List<String> _models = <String>[];
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  /// 从设置装载输入框内容。
  ///
  /// **首次调用**才创建控制器(字段是 `late final`,只能赋值一次);
  /// 之后调用只刷新文本,不重建 —— 重建会丢弃用户正在输入的内容,
  /// 也会让已挂载的 `TextField` 指向被 dispose 的控制器。
  void _initValues() {
    final s = widget.controller.settings;
    final LlmProvider provider = widget.controller.llmProvider;
    final String baseUrl =
        provider.fixedBaseUrl ? provider.defaultBaseUrl : s.baseUrl;
    if (!_controllersReady) {
      _baseUrlCtrl = TextEditingController(text: baseUrl);
      _apiKeyCtrl = TextEditingController(text: s.apiKey);
      _controllersReady = true;
    } else {
      _baseUrlCtrl.text = baseUrl;
      _apiKeyCtrl.text = s.apiKey;
    }
    _selectedModel = s.selectedModel.isEmpty ? null : s.selectedModel;
    if (provider.fixedBaseUrl) {
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
      // 校验文案附加明文 HTTP 传输警示(成功/失败均展示,不阻断)。
      _apiMessage = withTransportWarning(_baseUrlCtrl.text, r.message);
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
      if (_selectedModel != null && !_models.contains(_selectedModel)) {
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

  void _pickModel(String model) {
    setState(() => _selectedModel = model);
  }

  /// 组装子组件所需的全部状态与回调。
  ///
  /// 集中构造而非分散传参 —— 新增字段时只需改这里,
  /// 子组件漏用会在渲染契约测试里暴露。
  AiServicePageContract get _contract => AiServicePageContract(
        controller: widget.controller,
        baseUrlController: _baseUrlCtrl,
        apiKeyController: _apiKeyCtrl,
        checkingApi: _checkingApi,
        loadingModels: _loadingModels,
        apiMessage: _apiMessage,
        modelsError: _modelsError,
        models: _models,
        selectedModel: _selectedModel,
        onSaveApi: _saveApi,
        onCheckApi: _checkApi,
        onFetchModels: _fetchModels,
        onPickModel: _pickModel,
        onSaveModel: _saveModel,
        onSelectProvider: _selectProvider,
        onAddCustomModel: _addCustomModel,
        onResetValues: _initValues,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FitText('AI 服务'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    AiServiceMorePage(controller: widget.controller),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (BuildContext context, Widget? _) {
          final bool isSimple = widget.controller.settings.simpleModelMode;

          // 精简模式:连接参数 + 模型选择(输入框需要滚动)。
          // 完整模式:平铺的模型快速切换列表(自身就是 ListView)。
          return isSimple
              ? ListView(
                  padding: AppInsets.page,
                  children: <Widget>[
                    AiServiceSimpleView(contract: _contract),
                  ],
                )
              : AiServiceAdvancedView(contract: _contract);
        },
      ),
    );
  }
}
