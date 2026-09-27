// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import '../../state/app_controller.dart';
import 'ai_service/advanced_view.dart';
import 'ai_service/simple_view.dart';
import 'ai_service/widgets.dart';

/// 设置 → AI 服务主页。
///
/// 支持「精简模式」（只留最常用的连接与模型设置）与「完整模式」
/// （分层进入服务商 / 模型预设管理）。
///
/// **本次重构**(见 `SETTINGS_AUDIT.md`):
/// 原文件 796 行、8 张手写卡片,现在拆分为:
/// * 本文件 —— 只负责模式切换与两个视图的装配(装配层);
/// * `ai_service/simple_view.dart` —— 精简模式的三张分组卡;
/// * `ai_service/advanced_view.dart` —— 完整模式的三张分组卡;
/// * `ai_service/connection_section.dart` / `model_section.dart` /
///   `thinking_section.dart` / `quick_switch_sheet.dart` —— 各设置项区块;
/// * `ai_service/widgets.dart` —— 共用展示型零件。
///
/// 拆分理由:原文件把「装配」「输入框状态」「网络校验状态」「模型列表状态」
/// 全塞在一个 `State` 里,任何一处改动都要在 800 行里翻找。拆分后每个文件
/// 都在 200 行上下,且**每一个设置项的行为都与重构前逐行对齐**——
/// 没有增删设置项,没有改动任何 `AppController` 调用。
class AiServiceSettingsPage extends StatefulWidget {
  const AiServiceSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AiServiceSettingsPage> createState() => _AiServiceSettingsPageState();
}

class _AiServiceSettingsPageState extends State<AiServiceSettingsPage> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;

  /// 重置子视图内部的本地状态(切换模式 / 重新装载输入框时使用)。
  int _viewEpoch = 0;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    final s = widget.controller.settings;
    final provider = widget.controller.llmProvider;
    _baseUrlCtrl = TextEditingController(
      text: provider.fixedBaseUrl ? provider.defaultBaseUrl : s.baseUrl,
    );
    _apiKeyCtrl = TextEditingController(text: s.apiKey);
    if (provider.fixedBaseUrl) {
      _saveApi();
    }
  }

  /// 重新从设置装载两个输入框,并让子视图重建。
  void _resetValues() {
    _initValues();
    setState(() => _viewEpoch++);
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

  @override
  Widget build(BuildContext context) {
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
              AiModeSection(
                simpleMode: isSimple,
                onChanged: (bool value) async {
                  await widget.controller.toggleSimpleModelMode(value);
                  if (!mounted) return;
                  if (value) {
                    _resetValues();
                  }
                },
              ),

              // ===== 分支 A：精简模式 =====
              if (isSimple)
                AiServiceSimplePage(
                  key: ValueKey<int>(_viewEpoch),
                  controller: widget.controller,
                  baseUrlController: _baseUrlCtrl,
                  apiKeyController: _apiKeyCtrl,
                  onResetControllers: _resetValues,
                )
              // ===== 分支 B：完整模式 =====
              else
                AiServiceAdvancedView(
                  controller: widget.controller,
                  activeModel: widget.controller.activeModel,
                  activeProvider: widget.controller.activeProviderConfig,
                ),
            ],
          );
        },
      ),
    );
  }
}
