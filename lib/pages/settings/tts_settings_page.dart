import 'package:flutter/material.dart';

import '../../services/tts/tts_service.dart';
import '../../state/app_controller.dart';
import '../../utils/ui_feedback.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/seed_input_field.dart';

/// 端侧语音合成（TTS）设置：开关、全局 seed、模型下载。
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

  @override
  void initState() {
    super.initState();
    _seedCtrl = TextEditingController(
      text: widget.controller.settings.ttsGlobalSeed?.toString() ?? '',
    );
    _refresh();
  }

  @override
  void dispose() {
    _seedCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    bool ready = false;
    try {
      ready = await TtsService.instance.isModelsReady();
    } catch (_) {
      ready = false;
    }
    if (!mounted) return;
    setState(() {
      _ready = ready;
      _status = ready ? '模型已就绪，可离线合成' : '';
    });
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _bytesText = '';
      _speedText = '';
      _fileInfo = '';
      _status = '正在下载模型…';
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
            _fileInfo = '文件 ${p.doneFiles + 1} / ${p.totalFiles}：${p.currentFile}';
          });
        },
      );
      if (mounted) {
        showSnack(context, '语音模型已就绪。');
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, '下载失败：$e');
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
        title: const FitText('删除模型'),
        content: const FitText('将删除已下载的语音模型，删除后需重新下载才能合成。确定继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const FitText('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await TtsService.instance.deleteModels();
    showSnack(context, '模型已删除。');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool enabled = widget.controller.settings.ttsEnabled;

    return Scaffold(
      appBar: AppBar(title: const FitText('语音合成')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FitText('端侧语音合成',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FitText(
            '开启后，角色回复左上角会出现播放按钮，点击即可合成并播放语音。'
            '全部在本地完成，无需联网（首次需下载模型）。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('启用语音合成'),
            value: enabled,
            onChanged: (bool v) => widget.controller.saveTtsEnabled(v),
          ),
          const Divider(),

          // 全局 seed
          FitText('全局音色 Seed',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FitText(
            '角色未单独设置 seed 时使用此值，保证音色稳定。留空则每次随机。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SeedInputField(
            controller: _seedCtrl,
            label: '全局 Seed（整数，可留空）',
            onChanged: (String raw) {
              final int? seed = raw.trim().isEmpty
                  ? null
                  : int.tryParse(raw.trim());
              widget.controller.saveTtsGlobalSeed(seed);
            },
          ),
          const Divider(),

          // 模型
          FitText('离线模型',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _ready ? Icons.check_circle : Icons.download_outlined,
              color: _ready ? Colors.green : cs.onSurfaceVariant,
            ),
            title: FitText(_ready ? '模型已就绪' : '模型未下载'),
            subtitle: FitText(_status),
          ),
          const SizedBox(height: 8),
          if (_downloading) ...<Widget>[
            if (_progress != null) ...<Widget>[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
            ],
            if (_fileInfo.isNotEmpty)
              FitText(_fileInfo,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            if (_bytesText.isNotEmpty)
              FitText(_bytesText + (_speedText.isNotEmpty ? ' · $_speedText' : ''),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
          ],
          if (_ready) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _downloading ? null : _download,
                    child: const FitText('重新下载'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _downloading ? null : _delete,
                    child: const FitText('删除'),
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
                label: FitText(_downloading ? '下载中…' : '下载语音模型'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          FitText('模型约 400MB，含 GPT/Embed/DVAE/Vocos，首次下载后完全离线。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
