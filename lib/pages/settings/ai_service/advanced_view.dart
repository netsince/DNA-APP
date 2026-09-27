// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/models/llm_model_config.dart';
import 'package:dna/models/llm_provider_config.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

import '../models/model_list_page.dart';
import '../models/provider_list_page.dart';
import '../sampler_settings_page.dart';
import 'quick_switch_sheet.dart';
import 'widgets.dart';

/// 设置 → AI 服务(完整模式)。
///
/// 展示**当前生效模型**并提供三个管理入口:服务商、模型预设、采样参数。
///
/// **本次重构**(见 `SETTINGS_AUDIT.md`):
/// * 三张手写 `Card > ListTile` 入口卡收敛为 `AiEntryCard`;
/// * 原副标题 35~38 字(「已配置 N 个服务商(支持 OpenAI / Anthropic …)」)
///   压到 20 字以内,厂商清单这类参考信息下移到 `SettingHint`;
/// * 两个管理入口合并进同一分组,页面从 4 张卡降到 3 张。
///
/// **行为与重构前完全一致**:快速切换模型、两个管理路由、采样参数路由均未改动。
class AiServiceAdvancedView extends StatelessWidget {
  const AiServiceAdvancedView({
    super.key,
    required this.controller,
    required this.activeModel,
    required this.activeProvider,
  });

  final AppController controller;
  final LlmModelConfig activeModel;
  final LlmProviderConfig activeProvider;

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  /// 当前生效模型的只读三行摘要(模型名 / 服务商 / 接口地址)。
  Widget _activeModelSection(BuildContext context) {
    final AppController c = controller;

    return SettingSection(
      icon: Icons.bolt_outlined,
      title: '当前生效模型',
      children: <Widget>[
        AiActiveModelSummary(
          title: activeModel.alias,
          modelName: activeModel.modelName.isEmpty
              ? '未指定模型名称'
              : activeModel.modelName,
          providerLabel:
              '${activeProvider.alias} · ${activeProvider.providerType}',
          trailing: FilledButton.tonal(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
            ),
            onPressed: () => showAiQuickSwitchModelSheet(context, c),
            child: const FitText('切换'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppController c = controller;
    final int providerCount = c.settings.providers.length;
    final int modelCount = c.settings.models.length;

    return ListView(
      padding: AppInsets.page,
      children: <Widget>[
        // ===== 1. 当前生效模型 =====
        _activeModelSection(context),

        // ===== 2. 服务商与模型管理 =====
        SettingSection(
          icon: Icons.hub_outlined,
          title: '服务商与模型',
          description: '在多个平台与模型之间自由切换。',
          children: <Widget>[
            AiEntryCard(
              icon: Icons.hub_outlined,
              title: '服务商管理',
              subtitle: '已配置 $providerCount 个',
              onTap: () => _open(
                context,
                ProviderListPage(controller: c),
              ),
            ),
            AppSpacing.hMd,
            AiEntryCard(
              icon: Icons.psychology_outlined,
              title: '模型预设管理',
              subtitle: '已配置 $modelCount 个',
              onTap: () => _open(
                context,
                ModelListPage(controller: c),
              ),
            ),
            SettingHint(
              '服务商支持 OpenAI、Anthropic、DeepSeek、智谱等；'
              '模型预设可单独保存采样参数与深度思考设定。',
              icon: Icons.info_outline,
            ),
          ],
        ),

        // ===== 3. 采样参数 =====
        SettingSection(
          icon: Icons.tune,
          title: '采样参数',
          description: '所有模型共用的默认生成参数。',
          children: <Widget>[
            AiEntryCard(
              icon: Icons.equalizer_outlined,
              title: '全局默认采样参数',
              subtitle: '温度、随机性与防复读',
              onTap: () => _open(
                context,
                SamplerSettingsPage(controller: c),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
