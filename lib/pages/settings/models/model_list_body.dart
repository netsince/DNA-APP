// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/models/llm_model_config.dart';
import 'package:dna/models/llm_provider_config.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import 'model_edit_page.dart';

/// 模型预设的**列表主体**(不含 Scaffold / AppBar)。
///
/// 从 [ModelListPage] 抽出,供两处复用:
/// * `ModelListPage` —— 独立路由(仍可从别处进入);
/// * AI 服务 `⋮` 页面的「模型」tab。
///
/// 抽出的只是外层壳,列表项渲染与交互逐行照搬,没有任何行为改动。
class ModelListBody extends StatelessWidget {
  const ModelListBody({super.key, required this.controller});

  final AppController controller;

  Future<void> _confirmDelete(
    BuildContext context,
    LlmModelConfig model,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const FitText('删除模型预设'),
          content: FitText('确定要删除模型预设【${model.alias}】吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const FitText('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const FitText('确认删除'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await controller.deleteModelConfig(model.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: FitText('已删除模型预设【${model.alias}】'),
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final TextTheme ts = theme.textTheme;

    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final List<LlmModelConfig> models = controller.settings.models;
        final String activeId = controller.settings.activeModelId;

        if (models.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.psychology_outlined,
                    size: AppSize.iconEmpty, color: cs.outline),
                AppSpacing.hMd,
                FitText('暂无模型预设', style: ts.titleMedium),
                AppSpacing.hXs,
                FitText('点击下方「添加模型预设」新建一个',
                    style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: AppInsets.page,
          itemCount: models.length,
          separatorBuilder: (_, _) => AppSpacing.hMd,
          itemBuilder: (BuildContext context, int index) {
            final LlmModelConfig m = models[index];
            final bool isActive = m.id == activeId;
            final bool isDefault = m.isDefault;

            final LlmProviderConfig provider =
                controller.settings.providers.firstWhere(
              (LlmProviderConfig p) => p.id == m.providerId,
              orElse: () => LlmProviderConfig.defaultConfig(),
            );

            return Card(
              elevation: AppElevation.flat,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.mdAll,
                side: BorderSide(
                  color: isActive
                      ? cs.primary
                      : cs.outlineVariant.withValues(alpha: 0.5),
                  width: isActive ? 1.5 : 1.0,
                ),
              ),
              color: isActive
                  ? cs.primaryContainer.withValues(alpha: 0.2)
                  : null,
              child: Padding(
                padding: AppInsets.card,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Radio<String>(
                          value: m.id,
                          groupValue: activeId,
                          onChanged: (String? val) {
                            if (val != null) {
                              controller.setActiveModel(val);
                            }
                          },
                        ),
                        AppSpacing.wXs,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Flexible(
                                    child: Text(
                                      m.alias,
                                      style: ts.titleSmall?.copyWith(
                                        fontWeight: AppWeight.medium,
                                        color: isActive ? cs.primary : null,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isDefault) ...<Widget>[
                                    AppSpacing.wXs,
                                    _tag('默认项', cs.secondaryContainer,
                                        cs.onSecondaryContainer),
                                  ],
                                  if (isActive) ...<Widget>[
                                    AppSpacing.wXs,
                                    _tag('当前生效', cs.primary, cs.onPrimary),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '服务商: ${provider.alias} • '
                                '${m.modelName.isEmpty ? "未指定模型" : m.modelName}',
                                style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              size: AppSize.iconCard),
                          tooltip: '编辑模型预设',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ModelEditPage(
                                  controller: controller,
                                  existingConfig: m,
                                ),
                              ),
                            );
                          },
                        ),
                        if (!isDefault)
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: AppSize.iconCard, color: cs.error),
                            tooltip: '删除模型预设',
                            onPressed: () => _confirmDelete(context, m),
                          ),
                      ],
                    ),
                    if (m.customSamplingEnabled) ...<Widget>[
                      AppSpacing.hSm,
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer.withValues(alpha: 0.4),
                          borderRadius: AppRadius.xsAll,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.tune,
                                size: 14, color: cs.onTertiaryContainer),
                            AppSpacing.wXs,
                            Text(
                              '专属采样参数已启用 '
                              '(温度: ${(m.temperature ?? 0.7).toStringAsFixed(2)})',
                              style: TextStyle(
                                fontSize: AppFontSize.tiny,
                                color: cs.onTertiaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 小标签(默认项 / 当前生效)。
  Widget _tag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.xsAll),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppFontSize.tiny,
          fontWeight: AppWeight.medium,
          color: fg,
        ),
      ),
    );
  }
}

/// 「添加模型预设」浮动按钮(页面与 tab 共用)。
class AddModelFab extends StatelessWidget {
  const AddModelFab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ModelEditPage(controller: controller),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const FitText('添加模型预设'),
    );
  }
}
