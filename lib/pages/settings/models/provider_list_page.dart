// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:dna/models/llm_provider_config.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'provider_edit_page.dart';

/// 服务商列表独立管理页。
class ProviderListPage extends StatelessWidget {
  const ProviderListPage({super.key, required this.controller});

  final AppController controller;

  Future<void> _confirmDelete(
    BuildContext context,
    LlmProviderConfig provider,
  ) async {
    final relatedModels = controller.settings.models
        .where((m) => m.providerId == provider.id && !m.isDefault)
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const FitText('删除服务商'),
          content: FitText(
            relatedModels.isNotEmpty
                ? '删除服务商【${provider.alias}】将同时删除归属于它的 ${relatedModels.length} 个模型预设。\n\n是否确认删除？'
                : '确定要删除服务商【${provider.alias}】吗？',
          ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final providers = controller.settings.providers;

        return Scaffold(
          appBar: AppBar(
            title: const FitText('服务商管理'),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '添加服务商',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProviderEditPage(controller: controller),
                    ),
                  );
                },
              ),
            ],
          ),
          body: providers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.hub_outlined, size: 64, color: cs.outline),
                      const SizedBox(height: 12),
                      FitText('暂无服务商', style: ts.titleMedium),
                      const SizedBox(height: 6),
                      FitText('点击右上角「+」添加新的大模型服务商',
                          style: ts.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  itemCount: providers.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final p = providers[index];
                    final registered = controller.llmProviders.firstWhere(
                      (item) => item.id == p.providerType,
                      orElse: () => controller.llmProviders.first,
                    );
                    final isDefault = p.isDefault;

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer
                                        .withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.cloud_outlined,
                                      color: cs.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        children: <Widget>[
                                          Flexible(
                                            child: Text(
                                              p.alias,
                                              style: ts.titleSmall?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isDefault) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: cs.secondaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '默认项',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      cs.onSecondaryContainer,
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
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 20),
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
                                    icon: Icon(Icons.delete_outline,
                                        size: 20, color: cs.error),
                                    tooltip: '删除服务商',
                                    onPressed: () =>
                                        _confirmDelete(context, p),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
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
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProviderEditPage(controller: controller),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const FitText('添加服务商'),
          ),
        );
      },
    );
  }
}
