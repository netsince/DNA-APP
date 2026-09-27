// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../services/tts/tts_audio_cache.dart';
import '../../utils/platform_capabilities.dart';
import '../../utils/ui_feedback.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

/// 语音合成缓存管理：展示缓存占用、清理已生成的音频缓存。
class TtsCachePage extends StatefulWidget {
  const TtsCachePage({super.key});

  @override
  State<TtsCachePage> createState() => _TtsCachePageState();
}

class _TtsCachePageState extends State<TtsCachePage> {
  int _bytes = 0;
  int _count = 0;
  bool _loading = true;

  static String _formatBytes(int b) {
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '$b B';
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final int bytes = await TtsAudioCache.instance.totalBytes();
    final int count = await TtsAudioCache.instance.count();
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _count = count;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const FitText('清空本地语音缓存'),
        content: const FitText('将删除所有已合成保存的音频文件。清空后再次点击播放将重新触发本地合成。确定继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const FitText('确认清空'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await TtsAudioCache.instance.clear();
    if (!mounted) return;
    showSnack(context, '本地语音缓存已清空。');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.ttsSupported) {
      return Scaffold(
        appBar: AppBar(title: const FitText('语音缓存')),
        body: const Center(
          child: FitText('当前平台不支持端侧语音合成'),
        ),
      );
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('语音音频缓存')),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          SettingSection(
            icon: Icons.pie_chart_outline,
            title: '缓存占用',
            description: '听过的台词存下来，再听不用合成。',
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      padding: AppInsets.card,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest
                            .withValues(alpha: AppAlpha.mutedStrong / 2),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          FitText('占用空间',
                              style: AppTextStyles.caption(theme)
                                  .copyWith(color: cs.outline)),
                          AppSpacing.hXs,
                          FitText(
                            _loading ? '计算中…' : _formatBytes(_bytes),
                            style: AppTextStyles.sectionTitle(theme)
                                .copyWith(color: cs.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AppSpacing.wMd,
                  Expanded(
                    child: Container(
                      padding: AppInsets.card,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest
                            .withValues(alpha: AppAlpha.mutedStrong / 2),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          FitText('已存句数',
                              style: AppTextStyles.caption(theme)
                                  .copyWith(color: cs.outline)),
                          AppSpacing.hXs,
                          FitText(
                            _loading ? '…' : '$_count 句',
                            style: AppTextStyles.sectionTitle(theme)
                                .copyWith(color: cs.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              AppSpacing.hLg,
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading || _count == 0 ? null : _clear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const FitText('清空所有音频缓存'),
                ),
              ),
              SettingHint(
                '清理缓存不会影响语音模型文件本身。',
                icon: Icons.info_outline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
