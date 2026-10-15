import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/model_picker.dart';
import 'package:dna/widgets/provider_config_form.dart';

import '../../services/llm_provider.dart';
import '../splash/logo_painter.dart';
import 'step_hero.dart';

/// OOBE 引导流程中的子步骤 Widget 与导航 Intent，从 oobe_page 拆分而来。
///
/// ## 步骤顺序
///
/// 欢迎 → **社区** → API 配置 → 模型选择。
///
/// 社区排在第二位是刻意的：它是唯一「不需要 API Key 就能看到真实内容」的部分
/// （首页、角色卡、茶馆），而官方地址已经预填好。用户两步之内就能进社区逛，
/// 不必先跨过一整套模型配置。
///
/// ## 每一步的说明文案只写一份
///
/// 图标 / 短标签 / 标题 / 说明都收在 [kOobeSteps] 里，步骤条与步骤卡片共用，
/// 不会出现「进度条上叫这个名字、卡片里叫那个名字」的漂移。

/// 引导总步数：欢迎 → 社区 → API 配置 → 模型选择。
const int kOobeStepCount = 4;

/// 单个步骤的展示元信息。
class OobeStepMeta {
  const OobeStepMeta({
    required this.icon,
    required this.shortLabel,
    required this.title,
    required this.description,
  });

  /// 步骤图标。
  final IconData icon;

  /// 步骤条上的短标签（2~4 字，保证窄屏不折行）。
  final String shortLabel;

  /// 步骤卡片标题。
  final String title;

  /// 这一步要做什么，用一句人话说清。
  final String description;
}

/// 四个步骤的元信息，顺序与 PageView 的子项一致。
const List<OobeStepMeta> kOobeSteps = <OobeStepMeta>[
  OobeStepMeta(
    icon: Icons.waving_hand_outlined,
    shortLabel: '欢迎',
    title: '与汝共奏',
    description: '本地优先的角色扮演应用：角色、剧情与数据都留在你自己手里。',
  ),
  OobeStepMeta(
    icon: Icons.public_outlined,
    shortLabel: '社区',
    title: '步骤 2/4 · 社区',
    description: '官方服务器已经连好，直接下一步即可；也可以改成自建服务器。',
  ),
  OobeStepMeta(
    icon: Icons.key_outlined,
    shortLabel: 'API',
    title: '步骤 3/4 · API 配置',
    description: '选择服务商并填入 API Key，检测通过后就能用了。',
  ),
  OobeStepMeta(
    icon: Icons.tune_outlined,
    shortLabel: '模型',
    title: '步骤 4/4 · 模型选择',
    description: '挑一个模型作为默认模型，也可以手动填写。',
  ),
];

/// 社区步骤的连通状态。
enum CommunityStepStatus {
  /// 还没检测过（官方默认地址的情况，不影响使用）。
  unchecked,

  /// 检测通过。
  connected,

  /// 检测失败。
  failed,

  /// 检测失败，但用户选择跳过。
  ignored,
}

/// 顶部/侧边步骤条：编号圆点 + 标签，已完成打勾、当前高亮、未到置灰，圆点之间连线。
///
/// [onStepSelected] 非空时，[maxReached] 以内的步骤可以直接点过去 —— 想改第 1 步
/// 的设置不必连点「上一步」。
class StepTracker extends StatelessWidget {
  const StepTracker({
    super.key,
    required this.stepIndex,
    this.maxReached,
    this.onStepSelected,
    this.axis = Axis.horizontal,
  });

  final int stepIndex;

  /// 已经到过的最远步骤；为空时等于 [stepIndex]。
  final int? maxReached;

  /// 点击某一步的回调；为空则步骤条不可点。
  final ValueChanged<int>? onStepSelected;

  /// 横向（窄屏顶部）或纵向（宽屏左栏）。
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final int reached = maxReached ?? stepIndex;
    final List<Widget> items = List<Widget>.generate(
      kOobeStepCount,
      (int index) {
        final bool tappable =
            onStepSelected != null && index != stepIndex && index <= reached;
        return _StepTrackerItem(
          index: index,
          stepIndex: stepIndex,
          isFirst: index == 0,
          isLast: index == kOobeStepCount - 1,
          axis: axis,
          onTap: tappable ? () => onStepSelected!(index) : null,
        );
      },
    );

    if (axis == Axis.vertical) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSize.contentMaxWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items
              .map((Widget item) => Expanded(child: item))
              .toList(),
        ),
      ),
    );
  }
}

class _StepTrackerItem extends StatelessWidget {
  const _StepTrackerItem({
    required this.index,
    required this.stepIndex,
    required this.isFirst,
    required this.isLast,
    required this.axis,
    required this.onTap,
  });

  final int index;
  final int stepIndex;
  final bool isFirst;
  final bool isLast;
  final Axis axis;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool done = index < stepIndex;
    final bool active = index == stepIndex;

    final Color circleColor = done
        ? cs.primary
        : active
            ? cs.primaryContainer
            : cs.surfaceContainerHighest;
    final Color onCircle = done
        ? cs.onPrimary
        : active
            ? cs.onPrimaryContainer
            : cs.onSurfaceVariant;
    final Color lineColor = done ? cs.primary : cs.outlineVariant;

    final Widget circle = AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.standard,
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: circleColor,
        shape: BoxShape.circle,
        border: active ? Border.all(color: cs.primary, width: 2) : null,
      ),
      child: done
          ? Icon(Icons.check, size: AppSize.iconInline, color: onCircle)
          : FitText(
              (index + 1).toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AppFontSize.caption,
                fontWeight: AppWeight.medium,
                color: onCircle,
                height: 1,
              ),
            ),
    );

    final TextStyle labelStyle = theme.textTheme.bodySmall!.copyWith(
      fontSize: AppFontSize.caption,
      fontWeight: active ? AppWeight.medium : AppWeight.regular,
      color: active || done ? cs.onSurface : cs.onSurfaceVariant,
    );

    final Widget body;
    if (axis == Axis.vertical) {
      body = SizedBox(
        height: AppSize.touchTarget,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 30,
              child: Column(
                children: <Widget>[
                  circle,
                  if (!isLast)
                    Expanded(
                      child: _StepConnector(color: lineColor, vertical: true),
                    ),
                ],
              ),
            ),
            AppSpacing.wMd,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: FitText(
                  kOobeSteps[index].shortLabel,
                  style: labelStyle,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      body = Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: isFirst
                    ? const SizedBox.shrink()
                    : _StepConnector(color: lineColor),
              ),
              circle,
              Expanded(
                child: isLast
                    ? const SizedBox.shrink()
                    : _StepConnector(color: lineColor),
              ),
            ],
          ),
          AppSpacing.hSm,
          FitText(
            kOobeSteps[index].shortLabel,
            textAlign: TextAlign.center,
            style: labelStyle,
          ),
        ],
      );
    }

    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smAll,
      child: body,
    );
  }
}

/// 两个步骤圆点之间的连线（首尾两段不画）。
class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.color, this.vertical = false});

  final Color color;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return Center(
        child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: color),
      );
    }
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      color: color,
    );
  }
}

/// 步骤头：色块图标 + 标题 + 一句说明。四个步骤共用，保证每屏的顶部语序一致。
class OobeStepHeader extends StatelessWidget {
  const OobeStepHeader({
    super.key,
    required this.stepIndex,
    required this.heroSize,
    this.providerId,
  });

  /// 步骤序号（图标、标题、说明都取 [kOobeSteps]）。
  final int stepIndex;

  /// 英雄位边长，由父级按可用高度算好（矮屏就小一点，但不隐藏）。
  final double heroSize;

  /// 传了就用该服务商的真实品牌标做英雄位（API 步骤用）。
  final String? providerId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final OobeStepMeta meta = kOobeSteps[stepIndex];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        StepHero(
          stepIndex: stepIndex,
          icon: meta.icon,
          size: heroSize,
          providerId: providerId,
        ),
        AppSpacing.wLg,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FitText(meta.title, style: AppTextStyles.pageTitle(theme)),
              AppSpacing.hXs,
              FitText(
                meta.description,
                style: AppTextStyles.caption(
                  theme,
                ).copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 步骤 0：欢迎。
///
/// 这里是整个引导唯一的「品牌时刻」：品牌图形 + 一句话定位 + 三条要点，
/// 外加一个「先看看」出口 —— 不想现在配置的人可以先进去看一眼。
class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key, this.onLookAround});

  /// 「先看看」：直接进入主界面，不做二次确认（这一步用户还没投入任何成本）。
  final VoidCallback? onLookAround;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(child: _WelcomeLogo(color: cs.primary)),
                    AppSpacing.hLg,
                    FitText(
                      kOobeSteps[0].title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headline(theme),
                    ),
                    AppSpacing.hSm,
                    FitText(
                      kOobeSteps[0].description,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(
                        theme,
                      ).copyWith(color: cs.onSurfaceVariant),
                    ),
                    AppSpacing.hXl,
                    const _WelcomeFeature(
                      icon: Icons.public_outlined,
                      title: '先连上社区',
                      description: '官方服务器开箱即用，能直接看到角色卡',
                    ),
                    const _WelcomeFeature(
                      icon: Icons.key_outlined,
                      title: '接入你的 AI',
                      description: '选择服务商、填入 API Key，一键检测连通性',
                    ),
                    const _WelcomeFeature(
                      icon: Icons.tune_outlined,
                      title: '挑一个模型',
                      description: '自动拉取可用模型，也可以手动添加',
                    ),
                    AppSpacing.hMd,
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.keyboard_outlined,
                          size: AppSize.iconInline,
                          color: cs.onSurfaceVariant,
                        ),
                        AppSpacing.wSm,
                        Expanded(
                          child: FitText(
                            '提示：方向键或滑动手势可在步骤之间移动。',
                            style: AppTextStyles.caption(
                              theme,
                            ).copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    if (onLookAround != null) ...<Widget>[
                      AppSpacing.hLg,
                      Center(
                        child: TextButton.icon(
                          onPressed: onLookAround,
                          icon: const Icon(
                            Icons.explore_outlined,
                            size: AppSize.iconInline,
                          ),
                          label: const FitText('先看看，稍后再配置'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 欢迎页的品牌标：进来时自己「画」一遍（先勾轮廓、再填充）。
///
/// 与启动页是同一套手法（[LogoPainter] 的 drawProgress / fillProgress），
/// 相当于把品牌时刻延长了一次。只播一次 —— 循环动画会让 pumpAndSettle 卡死。
class _WelcomeLogo extends StatefulWidget {
  const _WelcomeLogo({required this.color});

  final Color color;

  @override
  State<_WelcomeLogo> createState() => _WelcomeLogoState();
}

class _WelcomeLogoState extends State<_WelcomeLogo>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 900);

  late final AnimationController _controller;
  late final Animation<double> _draw;
  late final Animation<double> _fill;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    // 描边先走完，填充紧接着推上来（时间上略微重叠，收尾更顺）。
    _draw = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.6, curve: Curves.easeOut),
    );
    _fill = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.55, 0.9, curve: Curves.easeIn),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) => CustomPaint(
          painter: LogoPainter(
            drawProgress: _draw.value,
            fillProgress: _fill.value,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

/// 欢迎页的一条要点：图标块 + 标题 + 说明。
class _WelcomeFeature extends StatelessWidget {
  const _WelcomeFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: AppSize.iconBox,
            height: AppSize.iconBox,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(
              icon,
              size: AppSize.iconCard,
              color: cs.onSurfaceVariant,
            ),
          ),
          AppSpacing.wMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FitText(title, style: AppTextStyles.sectionTitle(theme)),
                AppSpacing.hXs,
                FitText(
                  description,
                  style: AppTextStyles.caption(
                    theme,
                  ).copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 步骤 1：社区（折叠态）。
///
/// 默认只显示一行结论 —— 官方地址已经连好，绝大多数用户直接下一步即可。
/// 想改地址、想检测连通性、想关掉整个社区功能，都点「改」进编辑页，
/// 不在这张卡片里铺开一堆输入框和按钮。
class CommunityStep extends StatelessWidget {
  const CommunityStep({
    super.key,
    required this.enabled,
    required this.url,
    required this.defaultUrl,
    required this.status,
    required this.heroSize,
    required this.onEdit,
  });

  /// 社区功能是否开启（设置 → 界面与显示 → 社区）。
  final bool enabled;

  /// 当前社区服务器地址。
  final String url;

  /// 官方地址。
  final String defaultUrl;

  /// 上一次检测的结果。
  final CommunityStepStatus status;

  /// 英雄位边长（见 [OobeStepHeader.heroSize]）。
  final double heroSize;

  /// 点「改」进入编辑页。
  final VoidCallback onEdit;

  bool get _isOfficial => url.trim() == defaultUrl;

  String get _title {
    if (!enabled) return '社区已关闭';
    return _isOfficial ? '已连接官方服务器' : '使用自建服务器';
  }

  String? get _subtitle {
    if (!enabled) return '底栏与侧栏不会显示社区。可以随时在这里重新打开。';
    return url.trim().isEmpty ? defaultUrl : url.trim();
  }

  String? get _statusText {
    switch (status) {
      case CommunityStepStatus.connected:
        return '上次检测：连接正常';
      case CommunityStepStatus.failed:
        return '上次检测：连接失败';
      case CommunityStepStatus.ignored:
        return '上次检测：连接失败，已选择跳过';
      case CommunityStepStatus.unchecked:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String? statusText = _statusText;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OobeStepHeader(stepIndex: 1, heroSize: heroSize),
            AppSpacing.hLg,
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Container(
                      padding: AppInsets.card,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: AppAlpha.half,
                        ),
                        borderRadius: AppRadius.smAll,
                        border: Border.all(color: AppBorder.color(cs)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            enabled
                                ? Icons.public_outlined
                                : Icons.block_outlined,
                            size: AppSize.iconCard,
                            color: enabled ? cs.primary : cs.outline,
                          ),
                          AppSpacing.wMd,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                FitText(
                                  _title,
                                  style: AppTextStyles.sectionTitle(theme),
                                ),
                                if (_subtitle != null) ...<Widget>[
                                  AppSpacing.hXs,
                                  FitText(
                                    _subtitle!,
                                    style: AppTextStyles.caption(theme).copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                if (statusText != null) ...<Widget>[
                                  AppSpacing.hXs,
                                  FitText(
                                    statusText,
                                    style: AppTextStyles.caption(theme).copyWith(
                                      color: status == CommunityStepStatus.connected
                                          ? cs.primary
                                          : cs.error,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          AppSpacing.wSm,
                          TextButton(
                            onPressed: onEdit,
                            child: const FitText('改'),
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.hMd,
                    FitText(
                      '不改也能直接下一步 —— 官方地址开箱即用。'
                      '想换自建服务器、重新检测，或关掉整个社区功能，点「改」。',
                      style: AppTextStyles.caption(
                        theme,
                      ).copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 步骤 2：API 配置。
class ApiStep extends StatelessWidget {
  const ApiStep({
    super.key,
    required this.providers,
    required this.selectedProviderId,
    required this.baseUrlController,
    required this.apiKeyController,
    required this.baseUrlHint,
    required this.requiresApiKey,
    required this.heroSize,
    required this.checkingApi,
    required this.apiValidated,
    required this.apiError,
    required this.ignoreApiIssue,
    required this.onProviderChanged,
    required this.onIgnoreChanged,
    required this.onCheck,
    required this.onInputChanged,
    this.hideBaseUrl = false,
  });

  final List<LlmProvider> providers;
  final String selectedProviderId;
  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final String baseUrlHint;
  final bool requiresApiKey;

  /// 英雄位边长（见 [OobeStepHeader.heroSize]）。
  final double heroSize;
  final bool checkingApi;
  final bool apiValidated;
  final String? apiError;
  final bool ignoreApiIssue;
  final ValueChanged<LlmProvider> onProviderChanged;
  final ValueChanged<bool> onIgnoreChanged;
  final VoidCallback onCheck;
  final VoidCallback onInputChanged;
  final bool hideBaseUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // API 步骤的英雄位画当前服务商的真实品牌标：切服务商时它会重新
            // 描边生长一次，比让用户去看一排小 Chip 更直观。
            OobeStepHeader(
              stepIndex: 2,
              heroSize: heroSize,
              providerId: selectedProviderId,
            ),
            AppSpacing.hLg,
            Expanded(
              child: SingleChildScrollView(
                child: ProviderConfigForm(
                  providers: providers,
                  selectedProviderId: selectedProviderId,
                  baseUrlController: baseUrlController,
                  apiKeyController: apiKeyController,
                  defaultBaseUrl: baseUrlHint,
                  hideBaseUrl: hideBaseUrl,
                  requiresApiKey: requiresApiKey,
                  providerLabel: '服务商',
                  onProviderChanged: onProviderChanged,
                  onInputChanged: onInputChanged,
                  checking: checkingApi,
                  checkLabel: '保存并检测 API',
                  checkIcon: Icons.verified_outlined,
                  onCheck: onCheck,
                  onSubmitApiKey: onCheck,
                  validated: apiValidated,
                  validatedMessage: '连接验证成功。',
                  error: apiError,
                  ignoreIssue: ignoreApiIssue,
                  onIgnoreChanged: onIgnoreChanged,
                  ignoreHint: '勾选后允许跳过本次检测并进入下一步。',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 步骤 3：模型选择。
class ModelStep extends StatelessWidget {
  const ModelStep({
    super.key,
    required this.loadingModels,
    required this.models,
    required this.modelsError,
    required this.selectedModel,
    required this.onReload,
    required this.onSelect,
    required this.onCustom,
    required this.heroSize,
  });

  final bool loadingModels;
  final List<String> models;
  final String? modelsError;
  final String? selectedModel;
  final VoidCallback onReload;
  final ValueChanged<String> onSelect;
  final VoidCallback onCustom;

  /// 英雄位边长（见 [OobeStepHeader.heroSize]）。
  final double heroSize;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OobeStepHeader(stepIndex: 3, heroSize: heroSize),
            AppSpacing.hLg,
            Expanded(
              child: ModelPicker(
                models: models,
                selectedModel: selectedModel,
                loading: loadingModels,
                error: modelsError,
                onReload: onReload,
                onSelect: onSelect,
                onCustom: onCustom,
                fill: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 页脚：上一步 / 主按钮，外加「为什么还不能继续」的一行说明。
class OobeFooter extends StatelessWidget {
  const OobeFooter({
    super.key,
    required this.stepIndex,
    required this.canGoNext,
    required this.onBack,
    required this.onNext,
    required this.ignoreIssue,
    this.hint,
  });

  final int stepIndex;
  final bool canGoNext;
  final VoidCallback onBack;
  final VoidCallback onNext;

  /// 当前步的检测失败但用户勾了「忽略此问题」。
  final bool ignoreIssue;

  /// 主按钮禁用时说明缺什么；可继续时为 null。
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String nextLabel;
    if (stepIndex == 0) {
      nextLabel = '开始';
    } else if (stepIndex >= kOobeStepCount - 1) {
      nextLabel = ignoreIssue ? '忽略并继续' : '完成';
    } else {
      nextLabel = ignoreIssue ? '忽略并继续' : '下一步';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (hint != null) ...<Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.info_outline,
                size: AppSize.iconInline,
                color: cs.onSurfaceVariant,
              ),
              AppSpacing.wSm,
              Expanded(
                child: FitText(
                  hint!,
                  style: AppTextStyles.caption(
                    theme,
                  ).copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          AppSpacing.hMd,
        ],
        Row(
          children: <Widget>[
            OutlinedButton(
              onPressed: stepIndex == 0 ? null : onBack,
              child: const FitText('上一步'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: canGoNext ? onNext : null,
              icon: Icon(
                stepIndex >= kOobeStepCount - 1
                    ? Icons.check
                    : Icons.arrow_forward,
              ),
              label: FitText(nextLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class NextIntent extends Intent {
  const NextIntent();
}

class BackIntent extends Intent {
  const BackIntent();
}
