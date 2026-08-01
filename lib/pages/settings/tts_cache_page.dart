import 'package:flutter/material.dart';

import '../../services/tts/tts_audio_cache.dart';
import '../../utils/ui_feedback.dart';
import 'package:dna/widgets/fit_text.dart';

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
        title: const FitText('清理缓存'),
        content: const FitText('将删除所有已合成的缓存音频文件，删除后相同文本需重新合成。确定继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const FitText('清理'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await TtsAudioCache.instance.clear();
    showSnack(context, '缓存已清理。');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('语音缓存')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FitText('缓存管理',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FitText(
            '已合成的音频按「文本 + seed」缓存到本地，相同内容不会重复生成。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: const FitText('缓存占用'),
                    trailing: FitText(
                      _loading ? '计算中…' : _formatBytes(_bytes),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Divider(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.audiotrack_outlined),
                    title: const FitText('缓存音频数量'),
                    trailing: FitText(
                      _loading ? '…' : '$_count 条',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading || _count == 0 ? null : _clear,
              icon: const Icon(Icons.delete_outline),
              label: const FitText('清理缓存'),
            ),
          ),
          const SizedBox(height: 12),
          FitText(
            '清理缓存不会删除模型文件，仅删除合成的音频缓存。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
