// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:dna/models/llm_model_config.dart';
import 'package:dna/models/llm_provider_config.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'model_edit_page.dart';

/// 模型预设列表独立管理页。
class ModelListPage extends StatelessWidget {
  const ModelListPage({super.key, required this.controller});

  final AppController controller;

  Future<void> _confirmDelete(
    BuildContext context,
    LlmModelConfig model,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final models = controller.settings.models;
        final activeId = controller.settings.activeModelId;

        return Scaffold(
          appBar: AppBar(
            title: const FitText('模型预设管理'),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '添加模型预设',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ModelEditPage(controller: controller),
                    ),
                  );
                },
              ),
            ],
          ),
          body: models.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.psychology_outlined,
                          size: 64, color: cs.outline),
                      const SizedBox(height: 12),
                      FitText('暂无模型预设', style: ts.titleMedium),
                      const SizedBox(height: 6),
                      FitText('点击右上角「+」添加新的大模型预设',
                          style: ts.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  itemCount: models.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final m = models[index];
                    final isActive = m.id == activeId;
                    final isDefault = m.isDefault;

                    final provider = controller.settings.providers.firstWhere(
                      (p) => p.id == m.providerId,
                      orElse: () => LlmProviderConfig.defaultConfig(),
                    );

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Radio<String>(
                                  value: m.id,
                                  groupValue: activeId,
                                  onChanged: (val) {
                                    if (val != null) {
                                      controller.setActiveModel(val);
                                    }
                                  },
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        children: <Widget>[
                                          Flexible(
                                            child: Text(
                                              m.alias,
                                              style: ts.titleSmall?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: isActive
                                                    ? cs.primary
                                                    : null,
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
                                          if (isActive) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: cs.primary,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '当前生效',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: cs.onPrimary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '服务商: ${provider.alias} • ${m.modelName.isEmpty ? "未指定模型" : m.modelName}',
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
                                        size: 20, color: cs.error),
                                    tooltip: '删除模型预设',
                                    onPressed: () =>
                                        _confirmDelete(context, m),
                                  ),
                              ],
                            ),
                            if (m.customSamplingEnabled) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.tertiaryContainer
                                      .withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(Icons.tune,
                                        size: 14, color: cs.onTertiaryContainer),
                                    const SizedBox(width: 4),
                                    Text(
                                      '专属采样参数已启用 (温度: ${(m.temperature ?? 0.7).toStringAsFixed(2)})',
                                      style: TextStyle(
                                        fontSize: 11,
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
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ModelEditPage(controller: controller),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const FitText('添加模型预设'),
          ),
        );
      },
    );
  }
}
