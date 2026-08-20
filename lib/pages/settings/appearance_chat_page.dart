// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 外观与体验 → 聊天界面。
///
/// 聊天相关的显示细节：提示时长、遮罩、气泡透明度、半屏聊天与快捷按钮。
class AppearanceChatPage extends StatefulWidget {
  const AppearanceChatPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppearanceChatPage> createState() => _AppearanceChatPageState();
}

class _AppearanceChatPageState extends State<AppearanceChatPage> {
  int _snackDurationMs = 1000;
  int _chatMaskStrength = 75;
  int _chatBubbleOpacity = 100;
  bool _halfScreenChat = false;
  bool _dynamicHalfScreen = false;
  bool _showMessageAvatar = true;
  bool _showMessageRetry = true;
  bool _showMessageCopy = true;
  bool _showMessageContinue = true;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _snackDurationMs = s.snackDurationMs;
    _chatMaskStrength = s.chatMaskStrength;
    _chatBubbleOpacity = s.chatBubbleOpacity;
    _halfScreenChat = s.halfScreenChat;
    _dynamicHalfScreen = s.dynamicHalfScreen;
    _showMessageAvatar = s.showMessageAvatar;
    _showMessageRetry = s.showMessageRetry;
    _showMessageCopy = s.showMessageCopy;
    _showMessageContinue = s.showMessageContinue;
  }

  Future<void> _saveQuickButtons() =>
      widget.controller.saveMessageQuickButtons(
        showAvatar: _showMessageAvatar,
        showRetry: _showMessageRetry,
        showCopy: _showMessageCopy,
        showContinue: _showMessageContinue,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('聊天界面')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 视觉与透明度 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('视觉与透明度', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // 1. 背景遮罩强度
                  FitText('背景遮罩强度', style: ts.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  FitText('调节背景图暗度，数值越大背景越暗、文字越清晰。', style: ts.bodySmall?.copyWith(color: cs.outline)),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Slider(
                          value: _chatMaskStrength.toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 100,
                          onChanged: (v) => setState(() => _chatMaskStrength = v.round()),
                          onChangeEnd: (v) => widget.controller.saveChatMaskStrength(v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: FitText('$_chatMaskStrength', textAlign: TextAlign.right, style: ts.bodyMedium),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 2. 对话框透明度
                  FitText('对话气泡透明度', style: ts.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  FitText('调节消息气泡透明度，数值越小背景透出越多。', style: ts.bodySmall?.copyWith(color: cs.outline)),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Slider(
                          value: _chatBubbleOpacity.toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 100,
                          onChanged: (v) => setState(() => _chatBubbleOpacity = v.round()),
                          onChangeEnd: (v) => widget.controller.saveChatBubbleOpacity(v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: FitText('$_chatBubbleOpacity', textAlign: TextAlign.right, style: ts.bodyMedium),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // 3. 半屏聊天
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('半屏聊天模式'),
                    subtitle: const FitText('仅在屏幕下半部显示聊天内容，留出上半部欣赏角色立绘/背景。'),
                    value: _halfScreenChat,
                    onChanged: (bool v) async {
                      setState(() => _halfScreenChat = v);
                      await widget.controller.saveHalfScreenChat(v);
                    },
                  ),

                  // 3.1 动态自适应滚动（前置条件：开启半屏模式）
                  AnimatedCrossFade(
                    firstChild: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const FitText('滚动自适应全半屏'),
                        subtitle: const FitText(
                          '翻看上方历史时自动展开为全屏；向下滑动或滚到底部时自动收敛回半屏。',
                        ),
                        value: _dynamicHalfScreen,
                        onChanged: (bool v) async {
                          setState(() => _dynamicHalfScreen = v);
                          await widget.controller.saveDynamicHalfScreen(v);
                        },
                      ),
                    ),
                    secondChild: const SizedBox.shrink(),
                    crossFadeState: _halfScreenChat
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    duration: const Duration(milliseconds: 200),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 交互与快捷按钮 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('消息气泡快捷按钮', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  FitText('在消息气泡边缘显示的一键快捷操作（关闭后仍可通过长按/右键菜单使用）。', style: ts.bodySmall?.copyWith(color: cs.outline)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const FitText('头像显示'),
                    subtitle: const FitText('气泡左上角显示角色头像，便于在多角色/群聊中分辨发言者'),
                    value: _showMessageAvatar,
                    onChanged: (bool v) {
                      setState(() => _showMessageAvatar = v);
                      _saveQuickButtons();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const FitText('重说按钮'),
                    subtitle: const FitText('气泡右上角显示重新生成'),
                    value: _showMessageRetry,
                    onChanged: (bool v) {
                      setState(() => _showMessageRetry = v);
                      _saveQuickButtons();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const FitText('复制按钮'),
                    subtitle: const FitText('气泡右上角显示一键复制消息'),
                    value: _showMessageCopy,
                    onChanged: (bool v) {
                      setState(() => _showMessageCopy = v);
                      _saveQuickButtons();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const FitText('继续说按钮'),
                    subtitle: const FitText('气泡右上角显示让 AI 接着未完的内容继续作答'),
                    value: _showMessageContinue,
                    onChanged: (bool v) {
                      setState(() => _showMessageContinue = v);
                      _saveQuickButtons();
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 提示时长 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('底部轻量提示（SnackBar）', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  FitText('控制复制、保存等操作的底部提示停留时长。', style: ts.bodySmall?.copyWith(color: cs.outline)),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Slider(
                          value: _snackDurationMs.toDouble(),
                          min: 1000,
                          max: 10000,
                          divisions: 18,
                          label: '${(_snackDurationMs / 1000).toStringAsFixed(1)} 秒',
                          onChanged: (v) => setState(() => _snackDurationMs = v.round()),
                          onChangeEnd: (v) => widget.controller.saveSnackDuration(v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: FitText(
                          '${(_snackDurationMs / 1000).toStringAsFixed(1)} 秒',
                          textAlign: TextAlign.right,
                          style: ts.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
