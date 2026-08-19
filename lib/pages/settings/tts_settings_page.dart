// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../services/tts/tts_audio_cache.dart';
import '../../services/tts/tts_service.dart';
import '../../state/app_controller.dart';
import '../../utils/platform_capabilities.dart';
import '../../utils/ui_feedback.dart';
import 'package:dna/widgets/beta_tag.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/seed_input_field.dart';
import 'tts_cache_page.dart';

/// 端侧语音合成（TTS）设置：开关、台词朗读、全局 seed、模型管理与音频缓存。
class TtsSettingsPage extends StatefulWidget {
  const TtsSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<TtsSettingsPage> createState() => _TtsSettingsPageState();
}

class _TtsSettingsPageState extends State<TtsSettingsPage> {
  late final TextEditingController _seedCtrl;
  bool _downloading = false;
  bool _ready = false;
  String _status = '';
  double? _progress;
  String _bytesText = '';
  String _speedText = '';
  String _fileInfo = '';

  int _cacheBytes = 0;
  int _cacheCount = 0;
  bool _cacheLoading = true;

  static String _formatBytes(int b) {
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '$b B';
  }

  static String _formatSpeed(double bps) {
    if (bps >= 1024 * 1024) return '${(bps / 1024 / 1024).toStringAsFixed(1)} MB/s';
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${bps.toStringAsFixed(0)} B/s';
  }

  static const int _maxSeed = 0x7FFFFFFF;

  @override
  void initState() {
    super.initState();
    _seedCtrl = TextEditingController(
      text: widget.controller.settings.ttsGlobalSeed?.toString() ?? '',
    );
    widget.controller.addListener(_onControllerChanged);
    _refresh();
    _refreshCache();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _seedCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _refresh();
  }

  Future<void> _refresh() async {
    bool ready = false;
    try {
      ready = await TtsService.instance.isModelsReady();
    } catch (_) {
      ready = false;
    }
    if (!mounted) return;
    if (!ready && widget.controller.settings.ttsEnabled) {
      await widget.controller.saveTtsEnabled(false);
    }
    if (!mounted) return;
    setState(() {
      _ready = ready;
      _status = ready ? '模型已就绪，完全离线合成' : '';
    });
  }

  Future<void> _refreshCache() async {
    try {
      final int b = await TtsAudioCache.instance.totalBytes();
      final int c = await TtsAudioCache.instance.count();
      if (!mounted) return;
      setState(() {
        _cacheBytes = b;
        _cacheCount = c;
        _cacheLoading = false;
      });
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const FitText('清理音频缓存'),
        content: const FitText('将删除所有已合成保存的音频缓存，后续播放相同句子需重新合成。确定继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const FitText('确认清理'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await TtsAudioCache.instance.clear();
    if (!mounted) return;
    showSnack(context, '音频缓存已清空。');
    await _refreshCache();
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _bytesText = '';
      _speedText = '';
      _fileInfo = '';
      _status = '正在准备下载声学模型…';
    });
    try {
      await TtsService.instance.ensureModels(
        onProgress: (TtsDownloadProgress p) {
          if (!mounted) return;
          final double? prog = (p.totalBytes != null && p.totalBytes! > 0)
              ? p.receivedBytes / p.totalBytes!
              : null;
          final String bytes = p.totalBytes != null
              ? '${_formatBytes(p.receivedBytes)} / ${_formatBytes(p.totalBytes!)}'
              : _formatBytes(p.receivedBytes);
          setState(() {
            _progress = prog;
            _bytesText = bytes;
            _speedText = p.speedBps != null ? _formatSpeed(p.speedBps!) : '';
            _fileInfo = '正在下载文件 ${p.doneFiles + 1} / ${p.totalFiles}：${p.currentFile}';
          });
        },
      );
      if (mounted) {
        showSnack(context, '端侧语音模型已就绪。');
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, '模型下载失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _progress = null;
        });
      }
      await _refresh();
    }
  }

  Future<void> _delete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const FitText('删除语音模型'),
        content: const FitText('将删除本地约 400MB 的语音模型文件，删除后需重新下载方可播放。确定继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const FitText('确认删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await TtsService.instance.deleteModels();
    await widget.controller.saveTtsEnabled(false);
    if (!mounted) return;
    showSnack(context, '模型文件已移除。');
    await _refresh();
  }

  void _clearSeed() {
    _seedCtrl.text = '';
    widget.controller.saveTtsGlobalSeed(null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.ttsSupported) {
      return Scaffold(
        appBar: AppBar(title: const FitText('端侧语音合成')),
        body: const Center(
          child: FitText('当前平台不支持端侧语音合成'),
        ),
      );
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;
    final bool enabled = widget.controller.settings.ttsEnabled;

    return Scaffold(
      appBar: AppBar(title: const FitText('端侧语音合成')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 1. 主控开关与朗读偏好 =====
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
                  Row(
                    children: <Widget>[
                      Icon(Icons.record_voice_over_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('语音朗读功能', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      const BetaTag(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '开启后，AI 消息左上角将展示播放按钮，点击即可朗读。完全在本地离线运行。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('启用端侧语音合成'),
                    subtitle: _ready
                        ? const FitText('模型已就绪，随时可点击播放')
                        : const FitText('请先下载下方语音模型后方可开启', style: TextStyle(fontSize: 12)),
                    value: _ready && enabled,
                    onChanged: _ready
                        ? (bool v) => widget.controller.saveTtsEnabled(v)
                        : null,
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('优先朗读引号对话台词'),
                    subtitle: const FitText('含引号时仅读说话台词，跳过动作与旁白描写（括号内容始终跳过）。'),
                    value: widget.controller.settings.ttsQuoteOnly,
                    onChanged: (bool v) => widget.controller.saveTtsQuoteOnly(v),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 2. 全局音色 Seed 调节 =====
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
                  Row(
                    children: <Widget>[
                      Icon(Icons.tune, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('全局音色 Seed', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '当角色卡未单独指定音色时采用此全局数值。数值不同，生成的嗓音与语气风格不同。留空默认使用 1。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  SeedInputField(
                    controller: _seedCtrl,
                    label: '全局 Seed 整数（最大 $_maxSeed）',
                    maxValue: _maxSeed,
                    onChanged: (String raw) {
                      final int? seed = raw.trim().isEmpty ? null : int.tryParse(raw.trim());
                      widget.controller.saveTtsGlobalSeed(seed);
                      setState(() {});
                    },
                  ),
                  if (_seedCtrl.text.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _clearSeed,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const FitText('清除 Seed（恢复默认 1）'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 3. 本地声学模型管理 =====
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
                  Row(
                    children: <Widget>[
                      Icon(Icons.download_for_offline_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('离线声学模型', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '模型约 400MB（含 GPT/Embed/DVAE/Vocos 模块），首次下载完成后永久离线运行。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  if (_downloading) ...<Widget>[
                    if (_progress != null) ...<Widget>[
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 8),
                    ],
                    if (_fileInfo.isNotEmpty)
                      FitText(_fileInfo, style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    if (_bytesText.isNotEmpty)
                      FitText(
                        _bytesText + (_speedText.isNotEmpty ? ' · $_speedText' : ''),
                        style: ts.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.bold),
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (_ready) ...<Widget>[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: const FitText('语音模型已就绪'),
                      subtitle: FitText(_status),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _downloading ? null : _download,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const FitText('重新下载'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _downloading ? null : _delete,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const FitText('删除模型'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...<Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _downloading ? null : _download,
                        icon: Icon(_downloading ? Icons.hourglass_top : Icons.download),
                        label: FitText(_downloading ? '下载中…' : '下载离线语音模型'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 4. 本地音频缓存管理 =====
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.cleaning_services_outlined, color: cs.primary, size: 20),
                          const SizedBox(width: 8),
                          FitText('语音音频缓存', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const TtsCachePage()),
                        ),
                        icon: const Icon(Icons.chevron_right, size: 18),
                        label: const FitText('详情'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '已合成音频按「台词 + Seed」自动缓存在本地，避免二次播放消耗算力。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        FitText(
                          _cacheLoading ? '正在计算缓存…' : '已缓存 $_cacheCount 条音频 (${_formatBytes(_cacheBytes)})',
                          style: ts.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _cacheLoading || _cacheCount == 0 ? null : _clearCache,
                          icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                          label: const FitText('一键清空'),
                        ),
                      ],
                    ),
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
