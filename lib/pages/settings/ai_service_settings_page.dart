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
import 'ai_service/quick_switch_sheet.dart';
import 'ai_service/simple_view.dart';
import 'sampler_settings_page.dart';

/// 设置 → AI 服务主页。
///
/// 支持「新手简易模式」（单页直接操作默认项）与「完整模式」
/// （分层的服务商 / 模型预设管理路由）。
///
/// ## 本文件只做装配
///
/// 页面状态（两个输入框控制器、连接检测、模型列表）与全部业务逻辑
/// 都留在这里；两个分支的**视图**分别委托给:
///
/// * `ai_service/simple_view.dart` —— 精简模式(服务商 / 连接 / 模型 / 思考);
/// * `ai_service/advanced_view.dart` —— 完整模式的三个入口;
/// * `ai_service/quick_switch_sheet.dart` —— 快速切换模型弹窗;
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
        onShowQuickSwitch: () =>
            showQuickSwitchModelSheet(context, widget.controller),
        onResetValues: _initValues,
      );

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('AI 服务')),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (BuildContext context, Widget? _) {
          final bool isSimple = widget.controller.settings.simpleModelMode;

          return ListView(
            padding: AppInsets.page,
            children: <Widget>[
              // ===== 模式切换 =====
              _modeSwitch(cs, isSimple),

              // ===== 分支 A：新手简易模式 =====
              // ===== 分支 B：完整模式 =====
              if (isSimple)
                AiServiceSimpleView(contract: _contract)
              else
                AiServiceAdvancedView(contract: _contract),

              // ===== 采样参数入口 =====
              //
              // 两种模式都显示(仅标题随模式变化),所以它**不属于任何一个分支**,
              // 由主页统一渲染 —— 原实现即如此,拆分时不要把它挪进某个分支。
              AppSpacing.hMd,
              _samplerEntry(cs, isSimple),
            ],
          );
        },
      ),
    );
  }

  /// 「采样参数」入口。两种模式都显示,仅标题不同。
  Widget _samplerEntry(ColorScheme cs, bool isSimple) {
    return Card(
      elevation: AppElevation.flat,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: AppInsets.tile,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.6),
            borderRadius: AppRadius.smAll,
          ),
          child: Icon(Icons.tune, color: cs.primary),
        ),
        title: FitText(isSimple ? '采样参数微调' : '全局默认采样参数'),
        subtitle: const FitText('含场景预设与采样、防复读等高级参数'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                SamplerSettingsPage(controller: widget.controller),
          ),
        ),
      ),
    );
  }

  /// 顶部「新手简易模式」开关。
  Widget _modeSwitch(ColorScheme cs, bool isSimple) {
    return Card(
      elevation: AppElevation.flat,
      color: cs.secondaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      margin: EdgeInsets.only(bottom: AppSpacing.lg),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: const FitText('新手简易模式'),
        subtitle: Text(
          isSimple
              ? '已开启：仅操作默认模型与服务商，界面清爽聚焦'
              : '已关闭：开启多服务商与多模型预设列表管理',
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: cs.onSurfaceVariant,
          ),
        ),
        value: isSimple,
        onChanged: (bool value) async {
          await widget.controller.toggleSimpleModelMode(value);
          if (!mounted) return;
          if (value) {
            setState(_initValues);
          }
        },
      ),
    );
  }
}
