import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 角色背景音乐设置：音量与 10MB 大小上限解锁。
class BgmSettingsPage extends StatefulWidget {
  const BgmSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<BgmSettingsPage> createState() => _BgmSettingsPageState();
}

class _BgmSettingsPageState extends State<BgmSettingsPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = widget.controller.settings;

    return Scaffold(
      appBar: AppBar(title: const FitText('角色背景音乐')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const FitText('背景音乐音量',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  FitText(
                    '聊天时循环播放角色背景音乐的音量。朗读台词或语音输入时会自动调小。',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Icon(Icons.volume_down_outlined, color: cs.primary, size: 20),
                      Expanded(
                        child: Slider(
                          value: s.bgmVolume.toDouble().clamp(0, 100),
                          min: 0,
                          max: 100,
                          divisions: 100,
                          label: '${s.bgmVolume}%',
                          onChanged: (double v) =>
                              widget.controller.saveBgmVolume(v.round()),
                        ),
                      ),
                      Icon(Icons.volume_up_outlined, color: cs.primary, size: 20),
                      SizedBox(
                        width: 44,
                        child: FitText(
                          '${s.bgmVolume}%',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const FitText('解锁背景音乐大小上限（10MB）'),
              subtitle: const FitText('默认限制音乐不超过 10MB；开启后可选择更大的音频文件。'),
              value: s.bgmSizeLimitUnlocked,
              onChanged: (bool v) => widget.controller.saveBgmSizeLimitUnlocked(v),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const FitText('说明',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  _bullet(cs, '在「TA 编辑」中可为角色设置一首背景音乐，进入聊天时自动循环播放。'),
                  _bullet(cs, '背景音乐仅保存在本机，不会随角色卡导出或分享。'),
                  _bullet(cs, '群聊不播放背景音乐。'),
                  _bullet(cs, '朗读台词或语音输入时，背景音乐会自动调小音量，结束后恢复。'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 8),
            child: Icon(Icons.circle, size: 6, color: cs.primary),
          ),
          Expanded(child: FitText(text)),
        ],
      ),
    );
  }
}
