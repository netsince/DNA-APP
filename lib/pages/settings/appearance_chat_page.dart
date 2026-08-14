import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 外观与体验 → 聊天界面
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
    return Scaffold(
      appBar: AppBar(title: const FitText('聊天界面')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FitText('底部提示显示时长',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FitText('控制复制、保存等操作底部提示（SnackBar）停留的时间。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                  onChangeEnd: (v) =>
                      widget.controller.saveSnackDuration(v.round()),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 64,
                child: FitText(
                  '${(_snackDurationMs / 1000).toStringAsFixed(1)} 秒',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          FitText('聊天背景遮罩强度',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FitText(
              '聊天界面背景图上的遮罩层不透明度。数值越大背景越暗、文字越清晰；0 为完全不遮罩，100 为遮罩最强。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Slider(
                  value: _chatMaskStrength.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '$_chatMaskStrength',
                  onChanged: (v) => setState(() => _chatMaskStrength = v.round()),
                  onChangeEnd: (v) =>
                      widget.controller.saveChatMaskStrength(v.round()),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 44,
                child: FitText(
                  '$_chatMaskStrength',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          FitText('对话框透明度',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FitText(
              '聊天消息气泡的不透明度，数值越小越透明、背景透出越多（0 为完全透明）。对用户与 AI 气泡均生效：AI 气泡在 100 时完全不透明，用户气泡保持较淡的层次。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Slider(
                  value: _chatBubbleOpacity.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '$_chatBubbleOpacity',
                  onChanged: (v) => setState(() => _chatBubbleOpacity = v.round()),
                  onChangeEnd: (v) =>
                      widget.controller.saveChatBubbleOpacity(v.round()),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 44,
                child: FitText(
                  '$_chatBubbleOpacity',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('半屏聊天'),
            subtitle: const FitText(
              '聊天记录只显示在页面下半部分，上半部分留空方便查看背景，交界处带渐变过渡',
              style: TextStyle(fontSize: 12),
            ),
            value: _halfScreenChat,
            onChanged: (bool v) async {
              setState(() => _halfScreenChat = v);
              await widget.controller.saveHalfScreenChat(v);
            },
          ),
          const Divider(),
          FitText('消息气泡快捷按钮',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FitText(
              '控制 AI 消息气泡左上的头像、右上的「重说 / 复制 / 继续说」快捷按钮是否显示；关闭后可通过长按 / 右键菜单使用对应功能。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const FitText('头像'),
            subtitle: const FitText('气泡左上角显示角色头像，群聊中便于区分发言者', style: TextStyle(fontSize: 12)),
            value: _showMessageAvatar,
            onChanged: (bool v) {
              setState(() => _showMessageAvatar = v);
              _saveQuickButtons();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const FitText('重说'),
            subtitle: const FitText('气泡右上角显示「重说」，仅最近一条 AI 消息可用', style: TextStyle(fontSize: 12)),
            value: _showMessageRetry,
            onChanged: (bool v) {
              setState(() => _showMessageRetry = v);
              _saveQuickButtons();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const FitText('复制'),
            subtitle: const FitText('气泡右上角显示「复制」，一键复制消息内容', style: TextStyle(fontSize: 12)),
            value: _showMessageCopy,
            onChanged: (bool v) {
              setState(() => _showMessageCopy = v);
              _saveQuickButtons();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const FitText('继续说'),
            subtitle: const FitText('气泡右上角显示「继续说」，仅最近一条 AI 消息可用', style: TextStyle(fontSize: 12)),
            value: _showMessageContinue,
            onChanged: (bool v) {
              setState(() => _showMessageContinue = v);
              _saveQuickButtons();
            },
          ),
        ],
      ),
    );
  }
}
