import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import '../../../models/llm_model_config.dart';
import '../../../models/llm_provider_config.dart';
import 'contract.dart';

/// 分支 B:**完整模式** —— 平铺的模型快速切换列表。
///
/// 不再有「当前生效模型」卡片与「快速切换」按钮:模型全部平铺在页面上,
/// 每一项自带选中态与「当前生效」标记,卡片就成了冗余信息。
///
/// 服务商 / 模型预设管理、简易模式开关、全局采样参数都已移到
/// `⋮` 页(`AiServiceMorePage`)。
///
/// 控件清单由 `test/ai_service_page_render_test.dart` 锁定。
class AiServiceAdvancedView extends StatelessWidget {
  const AiServiceAdvancedView({super.key, required this.contract});

  final AiServicePageContract contract;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextTheme ts = theme.textTheme;

    return AnimatedBuilder(
      animation: contract.controller,
      builder: (BuildContext context, Widget? _) {
        final List<LlmModelConfig> models = contract.controller.settings.models;
        final String activeId = contract.controller.settings.activeModelId;

        if (models.isEmpty) {
          return Center(
            child: Padding(
              padding: AppInsets.page,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.bolt_rounded,
                      size: AppSize.iconEmpty, color: cs.outline),
                  AppSpacing.hMd,
                  FitText('暂无模型预设', style: ts.titleMedium),
                  AppSpacing.hXs,
                  FitText('前往「⋮ → 模型」添加模型预设',
                      textAlign: TextAlign.center,
                      style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: AppInsets.page,
          itemCount: models.length,
          separatorBuilder: (_, _) => AppSpacing.hSm,
          itemBuilder: (BuildContext context, int index) {
            final LlmModelConfig m = models[index];
            final bool isActive = m.id == activeId;
            final LlmProviderConfig provider =
                contract.controller.settings.providers.firstWhere(
              (LlmProviderConfig p) => p.id == m.providerId,
              orElse: () => LlmProviderConfig.defaultConfig(),
            );

            return Card(
              elevation: AppElevation.flat,
              color: isActive
                  ? cs.primaryContainer.withValues(alpha: 0.35)
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.mdAll,
                side: BorderSide(
                  color: isActive
                      ? cs.primary
                      : cs.outlineVariant.withValues(alpha: 0.5),
                  width: isActive ? 1.5 : 1.0,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                leading: Icon(
                  isActive
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isActive ? cs.primary : cs.outline,
                ),
                title: FitText(
                  m.alias,
                  style: ts.titleSmall?.copyWith(
                    fontWeight:
                        isActive ? AppWeight.medium : AppWeight.regular,
                    color: isActive ? cs.primary : null,
                  ),
                ),
                subtitle: FitText(
                  '${provider.alias} • '
                  '${m.modelName.isEmpty ? "未指定模型" : m.modelName}',
                  style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: isActive
                    ? Icon(Icons.check_circle, color: cs.primary, size: 20)
                    : null,
                onTap: () => contract.controller.setActiveModel(m.id),
              ),
            );
          },
        );
      },
    );
  }
}
