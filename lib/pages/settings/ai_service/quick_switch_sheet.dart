// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/models/llm_model_config.dart';
import 'package:dna/models/llm_provider_config.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

/// 「切换当前生效模型」底部弹层。
///
/// 从 `ai_service_settings_page.dart` 原样抽出 —— 逻辑、回调与
/// `setActiveModel` 的调用方式都未改动,只是把裸 `Text` 换成 `FitText`、
/// 手写间距换成 `AppSpacing` 令牌,并给标题加了关闭按钮的触摸目标。
Future<void> showAiQuickSwitchModelSheet(
  BuildContext context,
  AppController controller,
) {
  final List<LlmModelConfig> models = controller.settings.models;
  final String activeId = controller.settings.activeModelId;

  return showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext sheetCtx) {
      final ColorScheme cs = Theme.of(sheetCtx).colorScheme;

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: AppInsets.page,
              child: Row(
                children: <Widget>[
                  Icon(Icons.bolt, color: cs.primary),
                  AppSpacing.wSm,
                  Expanded(
                    child: FitText(
                      '切换当前生效模型',
                      style: AppTextStyles.sectionTitle(Theme.of(sheetCtx)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                    child: const FitText('关闭'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: models.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(height: 1),
                itemBuilder: (BuildContext ctx, int idx) {
                  final LlmModelConfig m = models[idx];
                  final bool isSelected = m.id == activeId;
                  final LlmProviderConfig provider =
                      controller.settings.providers.firstWhere(
                    (LlmProviderConfig p) => p.id == m.providerId,
                    orElse: () => controller.settings.providers.isNotEmpty
                        ? controller.settings.providers.first
                        : controller.activeProviderConfig,
                  );

                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected ? cs.primary : cs.outline,
                    ),
                    title: FitText(
                      m.alias,
                      style: AppTextStyles.body(Theme.of(ctx)).copyWith(
                        fontWeight: isSelected
                            ? AppWeight.medium
                            : AppWeight.regular,
                      ),
                    ),
                    subtitle: FitText(
                      '${provider.alias} · '
                      '${m.modelName.isEmpty ? "未指定模型" : m.modelName}',
                      style: AppTextStyles.caption(Theme.of(ctx))
                          .copyWith(color: cs.onSurfaceVariant),
                    ),
                    onTap: () {
                      controller.setActiveModel(m.id);
                      Navigator.of(ctx).pop();
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
