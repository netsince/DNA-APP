import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/model_picker.dart';
import 'package:dna/widgets/provider_config_form.dart';
import 'package:dna/widgets/setting_section.dart';

import 'contract.dart';

/// 分支 A:**新手简易模式** —— 单页经典配置器。
///
/// ## 控件清单(不可丢失)
///
/// 本页是上一次拆分的**事故现场**:旧实现收下了 `baseUrlController` /
/// `apiKeyController` 却从不使用,渲染出来一个输入框都没有。
/// 下列控件任何一个消失,`test/ai_service_page_render_test.dart` 都会失败:
///
/// * 服务商选择 `ChoiceChip` 组
/// * **Base URL `TextField`**(服务商锁定地址时隐藏)
/// * **API Key `TextField`**
/// * 「检测连接」按钮 + 结果提示
/// * 「刷新模型列表」/「自定义模型」按钮
/// * 已拉取模型的可选列表
/// * DeepSeek 思考模式卡(仅 DeepSeek 服务商)
class AiServiceSimpleView extends StatelessWidget {
  const AiServiceSimpleView({super.key, required this.contract});

  final AiServicePageContract contract;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextTheme ts = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (contract.isModelMissing) _missingModelBanner(cs, ts),
        _providerSection(),
        AppSpacing.hLg,
        _modelSection(context, cs, ts),
        if (contract.controller.llmProvider.id == 'deepseek') ...<Widget>[
          AppSpacing.hLg,
          _deepseekSection(cs, ts),
        ],
      ],
    );
  }

  /// 未选定模型时的告警条。
  Widget _missingModelBanner(ColorScheme cs, TextTheme ts) {
    return Container(
      margin: EdgeInsets.only(bottom: AppSpacing.lg),
      padding: AppInsets.card,
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.smAll,
        border: Border.all(color: cs.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded,
              color: cs.error, size: AppSize.iconCard),
          AppSpacing.wSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FitText('未选定模型',
                    style: ts.labelLarge
                        ?.copyWith(color: cs.error, fontWeight: AppWeight.medium)),
                const SizedBox(height: 2),
                FitText(
                  '当前服务商下尚未选定模型，聊天将无法发起请求。请在下方点击【刷新模型列表】或【自定义模型】进行指定。',
                  style: ts.bodySmall?.copyWith(color: cs.onErrorContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 服务商与 API 连接卡。
  ///
  /// 表单本体是 ProviderConfigForm —— 与 OOBE 的「API 配置」步骤同一个组件,
  /// 两边不再各写一份(此前连「恢复默认地址」按钮与检测结果的呈现都不一样)。
  Widget _providerSection() {
    return SettingSection(
      icon: Icons.dns_outlined,
      title: '服务商选择',
      children: <Widget>[
        AppSpacing.hMd,
        ProviderConfigForm(
          providers: contract.controller.llmProviders,
          selectedProviderId: contract.controller.settings.provider,
          baseUrlController: contract.baseUrlController,
          apiKeyController: contract.apiKeyController,
          defaultBaseUrl: contract.defaultBaseUrl,
          hideBaseUrl: contract.fixedBaseUrl,
          requiresApiKey: contract.controller.llmProvider.requiresApiKey,
          onProviderChanged: contract.onSelectProvider,
          onInputChanged: contract.onSaveApi,
          onRestoreDefault: () {
            contract.baseUrlController.text = contract.defaultBaseUrl;
            contract.onSaveApi();
          },
          checking: contract.checkingApi,
          checkLabel: '检测连接',
          checkIcon: Icons.network_check,
          onCheck: contract.onCheckApi,
          onSubmitApiKey: contract.onCheckApi,
          validated: contract.apiValidated,
          validatedMessage: contract.apiMessage ?? '连接成功。',
          error: contract.apiValidated ? null : contract.apiMessage,
        ),
      ],
    );
  }

  /// 当前生效模型 + 模型列表。
  Widget _modelSection(BuildContext context, ColorScheme cs, TextTheme ts) {
    return SettingSection(
      icon: Icons.memory_outlined,
      title: '当前生效模型',
      trailing: contract.isModelMissing
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: AppRadius.xsAll,
              ),
              child: FitText(
                contract.selectedModel!,
                style: ts.labelSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: AppWeight.medium,
                ),
              ),
            ),
      children: <Widget>[
        AppSpacing.hMd,
        ModelPicker(
          models: contract.models,
          selectedModel: contract.selectedModel,
          loading: contract.loadingModels,
          error: contract.modelsError,
          onReload: contract.onFetchModels,
          onSelect: (String model) {
            contract.onPickModel(model);
            contract.onSaveModel();
          },
          onCustom: contract.onAddCustomModel,
        ),
      ],
    );
  }

  /// DeepSeek 思考模式卡。
  Widget _deepseekSection(ColorScheme cs, TextTheme ts) {
    final s = contract.controller.settings;
    return SettingSection(
      icon: Icons.psychology_outlined,
      title: 'DeepSeek 深度思考模式',
      children: <Widget>[
        AppSpacing.hSm,
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const FitText('启用思考模式（Reasoning）'),
          subtitle: const FitText('开启后模型会在作答前展开深度思考过程'),
          value: s.deepseekThinkingEnabled,
          onChanged: (bool v) async {
            await contract.controller
                .saveDeepseekThinking(enabled: v, effort: s.deepseekThinkingEffort);
            contract.onResetValues;
          },
        ),
        AppSpacing.hSm,
        FitText('思考强度',
            style: ts.bodyMedium?.copyWith(fontWeight: AppWeight.medium)),
        AppSpacing.hXs,
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final String effort in const <String>['low', 'high', 'max'])
              ChoiceChip(
                label: FitText(switch (effort) {
                  'low' => '低',
                  'high' => '高',
                  _ => '最高',
                }),
                selected: s.deepseekThinkingEffort == effort,
                onSelected: (_) async {
                  await contract.controller.saveDeepseekThinking(
                    enabled: s.deepseekThinkingEnabled,
                    effort: effort,
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}
