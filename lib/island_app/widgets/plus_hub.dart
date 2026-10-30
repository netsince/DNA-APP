import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

/// 底栏中间「＋」弹出的选项。
enum PlusHubChoice { publishCard, publishWorld, imageGen }

/// 「＋」枢纽浮层：全屏高斯模糊 + 贴底的两个大按钮 + 底部正中的关闭按钮。
///
/// 抄自网页版的移动底栏，但有一处**刻意不同：不露出底栏**。
///
/// 网页版靠 z-index（底栏 1050 > 浮层 1045）让底栏压在浮层之上，于是 ＋ 一直
/// 看得见、能再点一次关掉。副作用是底栏那一带不经过蒙层 —— 点它会切栏目却收不掉
/// 浮层，得靠导航代码到处补「顺手关一下」。现在整屏一起糊、出口只有一个，
/// 行为没有例外。
///
/// 与网页版的另一处差异：网页版这套浮层是写死的深色，这里跟随主题。
class PlusHubOverlay extends StatefulWidget {
  const PlusHubOverlay({
    super.key,
    required this.open,
    required this.onClose,
    required this.onSelect,
    required this.bottomBarHeight,
  });

  /// 是否展开。
  final bool open;

  /// 点蒙层空白处 / 点底部的关闭按钮。
  final VoidCallback onClose;

  /// 选了某一项。调用方负责关闭并导航。
  final ValueChanged<PlusHubChoice> onSelect;

  /// 底栏内容高度（**不含**系统底部安全区）。
  ///
  /// 关闭按钮就落在这一格的正中，也就是原来 ＋ 的位置 —— 手指不用挪。
  final double bottomBarHeight;

  @override
  State<PlusHubOverlay> createState() => _PlusHubOverlayState();
}

class _PlusHubOverlayState extends State<PlusHubOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// 蒙层的进度。与内容**分开给曲线** —— 这正是 Material 原生 modal bottom sheet
  /// 的做法（sheet 一条曲线、barrier 另一条）。
  late final Animation<double> _scrim;

  /// 内容的进度。
  late final Animation<double> _content;

  @override
  void initState() {
    super.initState();
    // 时长取 MD3 原生令牌，与 Material 自己的 modal bottom sheet 同一组：
    // 进场 Durations.medium1（250ms）、出场 Durations.short4（200ms，退出更快）。
    _controller = AnimationController(
      vsync: this,
      duration: Durations.medium1,
      reverseDuration: Durations.short4,
      value: widget.open ? 1 : 0,
    );
    _scrim = CurvedAnimation(
      parent: _controller,
      curve: Easing.standard,
      reverseCurve: Easing.standardAccelerate,
    );
    _content = CurvedAnimation(
      parent: _controller,
      curve: Easing.emphasizedDecelerate,
      reverseCurve: Easing.emphasizedAccelerate,
    );
  }

  @override
  void didUpdateWidget(PlusHubOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      if (widget.open) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        // 完全收起时什么都不画：既不拦指针，也不让 BackdropFilter 空转。
        if (_controller.value == 0) return const SizedBox.shrink();
        final ColorScheme cs = Theme.of(context).colorScheme;
        final double safeBottom = MediaQuery.paddingOf(context).bottom;
        return IgnorePointer(
          // 动画途中不接收点击，避免误触。
          ignoring: _controller.value < 1,
          child: Stack(
            children: <Widget>[
              // 全屏蒙层：连底栏一起盖住。点空白处关闭。
              Positioned.fill(
                child: FadeTransition(
                  opacity: _scrim,
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: ColoredBox(
                          color: cs.scrim.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 两个大按钮：贴在关闭按钮那一格之上。
              Positioned(
                left: 0,
                right: 0,
                bottom: widget.bottomBarHeight + safeBottom,
                child: SlideTransition(
                  // 位移与淡入都交给 _content（已带 MD3 缓动）。
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.18),
                    end: Offset.zero,
                  ).animate(_content),
                  child: FadeTransition(
                    opacity: _content,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              PlusHubButton(
                                icon: Icons.badge_outlined,
                                title: '发布角色卡',
                                description: '创建与共享全新 AI 属性卡',
                                onTap: () =>
                                    widget.onSelect(PlusHubChoice.publishCard),
                              ),
                              AppSpacing.hMd,
                              PlusHubButton(
                                icon: Icons.public_outlined,
                                title: '发布世界卡',
                                description: '把你的世界书分享到社区',
                                onTap: () =>
                                    widget.onSelect(PlusHubChoice.publishWorld),
                              ),
                              AppSpacing.hMd,
                              PlusHubButton(
                                icon: Icons.auto_awesome_outlined,
                                title: 'AI生图',
                                description: '灵感画廊与在线绘图生成',
                                onTap: () =>
                                    widget.onSelect(PlusHubChoice.imageGen),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 关闭按钮：原来 ＋ 的位置。
              Positioned(
                left: 0,
                right: 0,
                bottom: safeBottom,
                height: widget.bottomBarHeight,
                child: Center(
                  child: FadeTransition(
                    opacity: _content,
                    child: IconButton.filledTonal(
                      tooltip: '关闭',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 「＋」枢纽里的一个大按钮：图标块 + 标题 + 一句说明 + 右箭头。
class PlusHubButton extends StatelessWidget {
  const PlusHubButton({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: AppRadius.mdAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.xxs),
          decoration: BoxDecoration(
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(icon, size: 26, color: cs.onPrimaryContainer),
              ),
              AppSpacing.wMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: AppFontSize.title,
                        fontWeight: AppWeight.medium,
                      ),
                    ),
                    AppSpacing.hXxs,
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
