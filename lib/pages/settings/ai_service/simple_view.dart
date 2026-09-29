import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

import '../../../services/llm_provider.dart';
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
        _providerSection(context, cs, ts),
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
  Widget _providerSection(BuildContext context, ColorScheme cs, TextTheme ts) {
    return SettingSection(
      icon: Icons.dns_outlined,
      title: '服务商选择',
      children: <Widget>[
        AppSpacing.hSm,
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: contract.controller.llmProviders
              .map((LlmProvider p) => ChoiceChip(
                    label: FitText(p.label),
                    selected: p.id == contract.controller.settings.provider,
                    onSelected: (_) => contract.onSelectProvider(p),
                  ))
              .toList(),
        ),
        AppSpacing.hLg,

        // Base URL:服务商锁定地址时不显示。
        if (!contract.fixedBaseUrl) ...<Widget>[
          TextField(
            controller: contract.baseUrlController,
            decoration: InputDecoration(
              labelText: 'Base URL',
              hintText: contract.defaultBaseUrl,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '恢复默认地址',
                icon: const Icon(Icons.restore),
                onPressed: () {
                  contract.baseUrlController.text = contract.defaultBaseUrl;
                  contract.onSaveApi();
                },
              ),
            ),
            onChanged: (_) => contract.onSaveApi(),
          ),
          AppSpacing.hMd,
        ],

        // API Key。
        TextField(
          controller: contract.apiKeyController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'API Key',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => contract.onSaveApi(),
        ),
        AppSpacing.hMd,

        OutlinedButton.icon(
          onPressed: contract.checkingApi ? null : contract.onCheckApi,
          icon: contract.checkingApi
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_check),
          label: FitText(contract.checkingApi ? '检测中...' : '检测连接'),
        ),

        if (contract.apiMessage != null) ...<Widget>[
          AppSpacing.hSm,
          _connectionResult(cs),
        ],
      ],
    );
  }

  /// 连接检测结果行。
  Widget _connectionResult(ColorScheme cs) {
    final bool ok = contract.apiMessage!.contains('成功');
    final Color color = ok ? cs.primary : cs.error;
    return Row(
      children: <Widget>[
        Icon(ok ? Icons.check_circle : Icons.error, size: 16, color: color),
        AppSpacing.wXs,
        Expanded(
          child: FitText(contract.apiMessage!,
              style: TextStyle(color: color)),
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
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: contract.loadingModels ? null : contract.onFetchModels,
              icon: contract.loadingModels
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: FitText(contract.loadingModels ? '加载中...' : '刷新模型列表'),
            ),
            OutlinedButton.icon(
              onPressed: contract.onAddCustomModel,
              icon: const Icon(Icons.edit_outlined),
              label: const FitText('自定义模型'),
            ),
          ],
        ),
        if (contract.modelsError != null) ...<Widget>[
          AppSpacing.hSm,
          FitText(contract.modelsError!, style: TextStyle(color: cs.error)),
        ],
        AppSpacing.hMd,
        _modelList(context, cs, ts),
      ],
    );
  }

  /// 模型列表(空态提示 / 可选列表)。
  Widget _modelList(BuildContext context, ColorScheme cs, TextTheme ts) {
    if (contract.models.isEmpty) {
      return Container(
        width: double.infinity,
        padding: AppInsets.tile,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: AppRadius.xsAll,
        ),
        child: FitText(
          contract.selectedModel == null
              ? '尚未加载模型列表。可点击【刷新模型列表】自动拉取，或点击【自定义模型】手动填写。'
              : '已选定当前模型：${contract.selectedModel}',
          style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FitText('可选模型列表（点击切换）：',
            style: ts.bodySmall?.copyWith(color: cs.outline)),
        AppSpacing.hXs,
        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
            borderRadius: AppRadius.xsAll,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: contract.models.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final String model = contract.models[index];
              final bool sel = model == contract.selectedModel;
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  sel
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: sel ? cs.primary : cs.outline,
                  size: AppSize.iconInline,
                ),
                title: FitText(
                  model,
                  style: TextStyle(
                    fontWeight: sel ? AppWeight.medium : AppWeight.regular,
                    color: sel ? cs.primary : null,
                  ),
                ),
                onTap: () {
                  contract.onPickModel(model);
                  contract.onSaveModel();
                },
              );
            },
          ),
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
