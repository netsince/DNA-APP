import 'package:flutter/material.dart';

import '../../services/tts/tts_service.dart';
import '../../state/app_controller.dart';
import '../../utils/platform_capabilities.dart';
import '../../utils/ui_feedback.dart';
import 'package:dna/widgets/beta_tag.dart';
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

  /// 全局 seed 允许的最大值（与引擎能力对齐）。
  static const int _maxSeed = 0x7FFFFFFF;

  @override
  void initState() {
    super.initState();
    _seedCtrl = TextEditingController(
      text: widget.controller.settings.ttsGlobalSeed?.toString() ?? '',
    );
    // 监听控制器：模型下载完成 / 开关状态变化时立即重新刷新就绪状态，
    // 避免「下载完成后必须退出页面再进入，启用按钮才可点」的问题。
    widget.controller.addListener(_onControllerChanged);
    _refresh();
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
    // 模型未就绪时不允许开启：强制保持关闭。
    if (!ready && widget.controller.settings.ttsEnabled) {
      await widget.controller.saveTtsEnabled(false);
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
    // 删除模型后自动关闭 TTS（未就绪时不允许开启）。
    await widget.controller.saveTtsEnabled(false);
    if (!mounted) return;
    showSnack(context, '模型已删除。');
    await _refresh();
  }

  /// 清除全局 seed，使其回退到默认值 1（解锁输入框以便重新填写）。
  void _clearSeed() {
    _seedCtrl.text = '';
    widget.controller.saveTtsGlobalSeed(null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Web 端不支持端侧语音合成：整页置灰不可用。
    if (!PlatformCapabilities.ttsSupported) {
      return Scaffold(
        appBar: AppBar(title: const FitText('语音合成')),
        body: const Center(
          child: FitText('当前平台不支持端侧语音合成'),
        ),
      );
    }
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool enabled = widget.controller.settings.ttsEnabled;

    return Scaffold(
      appBar: AppBar(title: const FitText('语音合成')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              FitText('端侧语音合成',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              const BetaTag(),
            ],
          ),
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
            subtitle: _ready
                ? null
                : const FitText('请先下载模型才能启用',
                    style: TextStyle(fontSize: 12)),
            value: _ready && enabled,
            onChanged: _ready
                ? (bool v) => widget.controller.saveTtsEnabled(v)
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('优先朗读引号内容'),
            subtitle: const FitText(
              '开启：文本含引号时只读引号内的内容；不含引号则读全文。'
              '括号内容始终不会朗读。',
              style: TextStyle(fontSize: 12),
            ),
            value: widget.controller.settings.ttsQuoteOnly,
            onChanged: (bool v) => widget.controller.saveTtsQuoteOnly(v),
          ),
          const Divider(),

          // 全局 seed
          FitText('全局音色 Seed',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FitText(
            '角色未单独设置 seed 时使用此值。留空则自动使用 1；'
            '填写后仍可随时修改、随机或测试。最大不超过 $_maxSeed。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SeedInputField(
            controller: _seedCtrl,
            label: '全局 Seed（整数）',
            maxValue: _maxSeed,
            onChanged: (String raw) {
              final int? seed = raw.trim().isEmpty
                  ? null
                  : int.tryParse(raw.trim());
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
          const Divider(),

          // 模型
          FitText('离线模型',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          // 下载/删除按钮置前
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
          // 状态
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
          FitText('模型约 400MB，含 GPT/Embed/DVAE/Vocos，首次下载后完全离线。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
