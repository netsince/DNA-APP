// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/models/llm_provider_config.dart';
import 'package:dna/services/llm_provider.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/app_container.dart';
import 'package:dna/widgets/fit_text.dart';

import 'provider_edit_page.dart';

/// 服务商的**列表主体**(不含 Scaffold / AppBar)。
///
/// 从 [ProviderListPage] 抽出,供两处复用:
/// * `ProviderListPage` —— 独立路由(仍可从别处进入);
/// * AI 服务 `⋮` 页面的「服务商」tab。
///
/// 抽出的只是外层壳,列表项渲染与交互逐行照搬。
class ProviderListBody extends StatelessWidget {
  const ProviderListBody({super.key, required this.controller});

  final AppController controller;

  Future<void> _confirmDelete(
    BuildContext context,
    LlmProviderConfig provider,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const FitText('删除服务商'),
          content: FitText('确定要删除服务商【${provider.alias}】吗？'),
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
      await controller.deleteProviderConfig(provider.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: FitText('已删除服务商【${provider.alias}】'),
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
        final List<LlmProviderConfig> providers = controller.settings.providers;

        if (providers.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.hub_outlined,
                  size: AppSize.iconEmpty,
                  color: cs.outline,
                ),
                AppSpacing.hMd,
                FitText('暂无服务商', style: ts.titleMedium),
                AppSpacing.hXs,
                FitText(
                  '点击下方「添加服务商」新建一个',
                  style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: AppInsets.page,
          itemCount: providers.length,
          separatorBuilder: (_, _) => AppSpacing.hMd,
          itemBuilder: (BuildContext context, int index) {
            final LlmProviderConfig p = providers[index];
            final LlmProvider registered = controller.llmProviders.firstWhere(
              (LlmProvider item) => item.id == p.providerType,
              orElse: () => controller.llmProviders.first,
            );
            final bool isDefault = p.isDefault;

            // 容器变换:整卡是源容器,点卡片任意处起飞。
            return AppContainer<bool>(
              closedBuilder: (BuildContext context, VoidCallback open) => Card(
                elevation: AppElevation.flat,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.mdAll,
                  side: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                margin: EdgeInsets.zero,
                child: InkWell(
                  onTap: open,
                  child: Padding(
                    padding: AppInsets.card,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Container(
                              padding: AppInsets.tile,
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withValues(
                                  alpha: 0.6,
                                ),
                                borderRadius: AppRadius.xsAll,
                              ),
                              child: Icon(
                                Icons.cloud_outlined,
                                color: cs.primary,
                                size: AppSize.iconCard,
                              ),
                            ),
                            AppSpacing.wMd,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Flexible(
                                        child: Text(
                                          p.alias,
                                          style: ts.titleSmall?.copyWith(
                                            fontWeight: AppWeight.medium,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isDefault) ...<Widget>[
                                        AppSpacing.wXs,
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cs.secondaryContainer,
                                            borderRadius: AppRadius.xsAll,
                                          ),
                                          child: Text(
                                            '默认项',
                                            style: TextStyle(
                                              fontSize: AppFontSize.tiny,
                                              fontWeight: AppWeight.medium,
                                              color: cs.onSecondaryContainer,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '协议: ${registered.label}',
                                    style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: AppSize.iconCard,
                              ),
                              tooltip: '编辑服务商',
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ProviderEditPage(
                                      controller: controller,
                                      existingConfig: p,
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (!isDefault)
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: AppSize.iconCard,
                                  color: cs.error,
                                ),
                                tooltip: '删除服务商',
                                onPressed: () => _confirmDelete(context, p),
                              ),
                          ],
                        ),
                        AppSpacing.hMd,
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.3,
                            ),
                            borderRadius: AppRadius.xsAll,
                          ),
                          child: Text(
                            p.baseUrl.isEmpty
                                ? '默认地址: ${registered.defaultBaseUrl}'
                                : '地址: ${p.baseUrl}',
                            style: ts.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              openBuilder: (BuildContext context, VoidCallback close) =>
                  ProviderEditPage(controller: controller, existingConfig: p),
            );
          },
        );
      },
    );
  }
}

/// 「添加服务商」浮动按钮(页面与 tab 共用)。
class AddProviderFab extends StatelessWidget {
  const AddProviderFab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    // FAB 即源容器:胶囊按钮放大为整页编辑器。
    return AppContainer<bool>(
      closedShape: const StadiumBorder(),
      closedBuilder: (BuildContext context, VoidCallback open) =>
          FloatingActionButton.extended(
            onPressed: open,
            icon: const Icon(Icons.add),
            label: const FitText('添加服务商'),
          ),
      openBuilder: (BuildContext context, VoidCallback close) =>
          ProviderEditPage(controller: controller),
    );
  }
}
