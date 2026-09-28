import 'package:flutter/material.dart';

import '../../../services/llm_provider.dart';
import '../../../state/app_controller.dart';

/// 「AI 服务」页拆分为多文件时的**回调契约**。
///
/// ## 为什么要有这个类
///
/// 上一次拆分该页时,子组件把 `baseUrlController` / `apiKeyController`
/// 作为参数收下却从不使用,结果精简模式渲染出来**一个输入框都没有**
/// (TextField=0),用户切过去只看到模式开关,所有配置项消失。
/// 代码能编译、`flutter analyze` 干净、行数也正常 —— 静态手段查不出来。
///
/// 因此这次拆分改用**显式契约**:子组件不再各自收一堆零散参数,
/// 而是统一接收这个对象。凡是页面用到的控制器、状态与回调都在这里,
/// 缺一个就编译不过,不会静默丢失。
///
/// 契约只做数据与回调的搬运,**不含任何业务逻辑** —— 逻辑仍全部留在
/// `_AiServiceSettingsPageState` 里,保证拆分前后行为逐行一致。
class AiServicePageContract {
  const AiServicePageContract({
    required this.controller,
    required this.baseUrlController,
    required this.apiKeyController,
    required this.checkingApi,
    required this.loadingModels,
    required this.apiMessage,
    required this.modelsError,
    required this.models,
    required this.selectedModel,
    required this.onSaveApi,
    required this.onCheckApi,
    required this.onFetchModels,
    required this.onPickModel,
    required this.onSaveModel,
    required this.onSelectProvider,
    required this.onAddCustomModel,
    required this.onResetValues,
  });

  /// 全局控制器(读写设置、服务商、模型)。
  final AppController controller;

  /// Base URL 输入框控制器。**精简模式必须用它渲染输入框**。
  final TextEditingController baseUrlController;

  /// API Key 输入框控制器。**精简模式必须用它渲染输入框**。
  final TextEditingController apiKeyController;

  /// 连接检测进行中。
  final bool checkingApi;

  /// 模型列表拉取中。
  final bool loadingModels;

  /// 连接检测结果文案(已附加明文 HTTP 警示)。
  final String? apiMessage;

  /// 模型列表拉取错误。
  final String? modelsError;

  /// 已拉取到的模型列表。
  final List<String> models;

  /// 当前选中的模型 ID。
  final String? selectedModel;

  // ===== 回调 =====
  final Future<void> Function() onSaveApi;
  final Future<void> Function() onCheckApi;
  final Future<void> Function() onFetchModels;

  /// 在列表里点选某个模型(由页面 setState 记录并保存)。
  final void Function(String model) onPickModel;

  final Future<void> Function() onSaveModel;
  final Future<void> Function(LlmProvider provider) onSelectProvider;
  final Future<void> Function() onAddCustomModel;

  /// 重新从设置装载两个输入框(切换模式时调用)。
  final VoidCallback onResetValues;

  /// 当前服务商是否锁定了 Base URL(锁定时不显示该输入框)。
  bool get fixedBaseUrl => controller.llmProvider.fixedBaseUrl;

  /// 是否尚未选定任何模型。
  bool get isModelMissing => (selectedModel ?? '').trim().isEmpty;

  /// 当前服务商默认 Base URL(输入框 hint)。
  String get defaultBaseUrl => controller.llmProvider.defaultBaseUrl;
}
