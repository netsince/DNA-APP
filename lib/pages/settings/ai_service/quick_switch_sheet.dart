import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import '../../../models/llm_model_config.dart';
import '../../../models/llm_provider_config.dart';
import '../../../state/app_controller.dart';

/// 「快速切换当前生效模型」底部弹窗。
///
/// 从 `ai_service_settings_page.dart` 抽出,逻辑逐行保持:
/// 列出 `settings.models`,标注所属服务商,点击即 `setActiveModel` 并关闭。
///
/// 服务商查不到时回退到第一个服务商(仍为空则用当前激活配置),
/// 与原实现一致 —— 避免列表在配置不完整时抛异常。
void showQuickSwitchModelSheet(BuildContext context, AppController controller) {
  final List<LlmModelConfig> models = controller.settings.models;
  final String activeId = controller.settings.activeModelId;

  showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: AppInsets.card,
              child: Row(
                children: <Widget>[
                  const Icon(Icons.bolt),
                  AppSpacing.wSm,
                  const FitText(
                    '切换当前生效模型',
                    style: TextStyle(
                      fontSize: AppFontSize.subtitle,
                      fontWeight: AppWeight.medium,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const FitText('关闭'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: models.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (BuildContext c, int idx) {
                  final LlmModelConfig m = models[idx];
                  final bool isSel = m.id == activeId;
                  final LlmProviderConfig provider =
                      controller.settings.providers.firstWhere(
                    (LlmProviderConfig p) => p.id == m.providerId,
                    orElse: () => controller.settings.providers.isNotEmpty
                        ? controller.settings.providers.first
                        : controller.activeProviderConfig,
                  );
                  return ListTile(
                    leading: Icon(
                      isSel
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSel ? Theme.of(c).colorScheme.primary : null,
                    ),
                    title: Text(
                      m.alias,
                      style: TextStyle(
                        fontWeight:
                            isSel ? AppWeight.medium : AppWeight.regular,
                      ),
                    ),
                    subtitle: Text(
                      '${provider.alias} • '
                      '${m.modelName.isEmpty ? "未指定模型" : m.modelName}',
                      style: const TextStyle(fontSize: AppFontSize.caption),
                    ),
                    onTap: () {
                      controller.setActiveModel(m.id);
                      Navigator.of(c).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
