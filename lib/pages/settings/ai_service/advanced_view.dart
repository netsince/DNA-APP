import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import '../models/model_list_page.dart';
import '../models/provider_list_page.dart';
import 'contract.dart';

/// 分支 B:**完整模式** —— 分层路由入口(清爽分明)。
///
/// 与精简模式不同,这里不直接编辑连接参数,而是给出三块内容:
/// * 当前生效模型展示 + 「快速切换」弹窗入口
/// * 服务商管理入口(跳 [ProviderListPage])
/// * 模型预设管理入口(跳 [ModelListPage])
///
/// 控件清单由 `test/ai_service_page_render_test.dart` 锁定。
class AiServiceAdvancedView extends StatelessWidget {
  const AiServiceAdvancedView({super.key, required this.contract});

  final AiServicePageContract contract;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme ts = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _activeModelCard(context, cs, ts),
        AppSpacing.hLg,
        _entryRow(
          context,
          cs,
          icon: Icons.hub_outlined,
          iconBg: cs.secondaryContainer.withValues(alpha: 0.6),
          iconFg: cs.onSecondaryContainer,
          title: '服务商管理',
          subtitle: '已配置 ${contract.controller.settings.providers.length} 个服务商'
              '（支持 OpenAI / Anthropic / DeepSeek / 智谱等）',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProviderListPage(controller: contract.controller),
            ),
          ),
        ),
        AppSpacing.hMd,
        _entryRow(
          context,
          cs,
          icon: Icons.psychology_outlined,
          iconBg: cs.tertiaryContainer.withValues(alpha: 0.6),
          iconFg: cs.onTertiaryContainer,
          title: '模型预设管理',
          subtitle: '已配置 ${contract.controller.settings.models.length} 个模型预设'
              '（支持专属采样参数与深度思考设定）',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ModelListPage(controller: contract.controller),
            ),
          ),
        ),
      ],
    );
  }

  /// 当前生效模型 + 快速切换。
  Widget _activeModelCard(BuildContext context, ColorScheme cs, TextTheme ts) {
    final activeModel = contract.controller.activeModel;
    final activeProvider = contract.controller.activeProviderConfig;
    return Card(
      elevation: AppElevation.flat,
      color: cs.primaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: AppInsets.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.bolt_rounded, color: cs.primary, size: AppSize.iconCard),
                AppSpacing.wSm,
                Text(
                  '当前生效模型',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: AppWeight.medium,
                    color: cs.primary,
                  ),
                ),
                const Spacer(),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                  ),
                  onPressed: contract.onShowQuickSwitch,
                  child: const FitText('快速切换'),
                ),
              ],
            ),
            AppSpacing.hSm,
            Text(
              activeModel.alias,
              style: ts.titleMedium?.copyWith(fontWeight: AppWeight.medium),
            ),
            AppSpacing.hXs,
            Text(
              '模型: ${activeModel.modelName.isEmpty ? "未指定模型 ID" : activeModel.modelName}'
              ' • 服务商: ${activeProvider.alias} (${activeProvider.providerType})',
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 带图标圆底的跳转行。
  Widget _entryRow(
    BuildContext context,
    ColorScheme cs, {
    required IconData icon,
    required Color iconBg,
    required Color iconFg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: AppElevation.flat,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: AppInsets.tile,
          decoration: BoxDecoration(color: iconBg, borderRadius: AppRadius.smAll),
          child: Icon(icon, color: iconFg),
        ),
        title: FitText(title),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: cs.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
