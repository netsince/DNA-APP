import 'package:flutter/material.dart';

import '../../models/voice_models.dart';
import '../../services/sherpa_model_service.dart';
import '../../state/app_controller.dart';
import '../../utils/ui_feedback.dart';
import 'package:dna/widgets/fit_text.dart';

/// 语音输入设置：选择模型、选择下载源、下载/删除离线模型。
class VoiceInputSettingsPage extends StatefulWidget {
  const VoiceInputSettingsPage({required this.controller, super.key});

  final AppController controller;

  @override
  State<VoiceInputSettingsPage> createState() => _VoiceInputSettingsPageState();
}

class _VoiceInputSettingsPageState extends State<VoiceInputSettingsPage> {
  bool _downloading = false;
  double? _progress;
  String _status = '';

  @override
  void initState() {
    super.initState();
    // 监听控制器：模型下载完成 / 切换模型 / 开关状态变化时立即刷新界面，
    // 避免「下载完成后必须退出页面再进入，启用按钮才可点」的问题。
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

  static String _formatBytes(int b) {
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '$b B';
  }

  static String _formatSpeed(double? bps) {
    if (bps == null) return '';
    if (bps >= 1024 * 1024) {
      return '${(bps / 1024 / 1024).toStringAsFixed(1)} MB/s';
    }
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    return '${bps.toStringAsFixed(0)} B/s';
  }

  VoiceModelOption get _model =>
      voiceModelById(widget.controller.settings.selectedVoiceModelId);

  bool get _readyForCurrent {
    final String? p = widget.controller.settings.sherpaModelPath;
    return widget.controller.settings.sherpaModelReady &&
        p != null &&
        p.endsWith(_model.id);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final s = widget.controller.settings;

    return Scaffold(
      appBar: AppBar(title: const FitText('语音输入')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FitText('离线语音识别',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FitText('下载模型后，点聊天输入框的麦克风即可语音输入。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('启用语音输入'),
            subtitle: _readyForCurrent
                ? null
                : const FitText('请先下载模型才能启用',
                    style: TextStyle(fontSize: 12)),
            value: _readyForCurrent && s.voiceInputEnabled,
            onChanged: _readyForCurrent
                ? (bool v) => widget.controller.saveVoiceInputEnabled(v)
                : null,
          ),
          const SizedBox(height: 8),
          const Divider(),

          // 模型选择
          FitText('识别模型',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder()),
            child: DropdownButton<VoiceModelOption>(
              value: _model,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: kVoiceModelOptions
                  .map((VoiceModelOption m) =>
                      DropdownMenuItem<VoiceModelOption>(
                        value: m,
                        child: FitText(m.label),
                      ))
                  .toList(),
              onChanged: _downloading
                  ? null
                  : (VoiceModelOption? v) {
                      if (v != null) {
                        widget.controller.saveSelectedVoiceModel(v.id);
                        setState(() {});
                      }
                    },
            ),
          ),
          const SizedBox(height: 6),
          FitText(_model.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),

          // 下载源
          FitText('下载来源',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          RadioGroup<String>(
            groupValue: s.sherpaModelSource,
            onChanged: (String? v) {
              if (_downloading || v == null) return;
              widget.controller.saveSherpaModelSource(v);
              setState(() {});
            },
            child: Column(
              children: <Widget>[
                RadioListTile<String>(
                  title: const FitText('自动选择'),
                  subtitle: const FitText('依次尝试可达的源'),
                  value: 'auto',
                ),
                RadioListTile<String>(
                  title: const FitText('ModelScope（国内）'),
                  subtitle: const FitText('只用此源'),
                  value: 'modelscope',
                ),
                RadioListTile<String>(
                  title: const FitText('GitHub'),
                  subtitle: const FitText('只用此源'),
                  value: 'github',
                ),
                RadioListTile<String>(
                  title: const FitText('自定义服务器'),
                  subtitle: const FitText('只用此源'),
                  value: 'custom',
                ),
              ],
            ),
          ),
          if (s.sherpaModelSource == 'custom')
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 4),
              child: TextFormField(
                initialValue: s.sherpaCustomBaseUrl ?? '',
                decoration: const InputDecoration(
                  labelText: '服务器根地址',
                  hintText: 'https://your-server/models',
                  border: OutlineInputBorder(),
                ),
                onChanged: (String v) =>
                    widget.controller.saveSherpaCustomBaseUrl(v.trim()),
              ),
            ),
          const SizedBox(height: 16),
          const Divider(),

          // 下载/删除按钮置前
          if (_downloading) ...<Widget>[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            FitText(_status,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
          ],
          if (_readyForCurrent) ...<Widget>[
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
                icon: const Icon(Icons.download),
                label: FitText(_downloading ? '下载中…' : '下载模型'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // 状态
          if (_readyForCurrent) ...<Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const FitText('模型已就绪'),
              subtitle: FitText(_model.label),
            ),
            const SizedBox(height: 8),
          ],
          FitText('首次下载需联网，之后完全离线使用。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _download() async {
    final String src = widget.controller.settings.sherpaModelSource;
    final String? customUrl = widget.controller.settings.sherpaCustomBaseUrl;

      setState(() {
        _downloading = true;
        _progress = null;
        _status =
            src == 'auto' ? '正在选择可用下载源…' : '正在准备下载…';
      });

    final List<SherpaModelSource> sources;
    if (src == 'auto') {
      // 自动选择：探测并按顺序回退（自定义 > ModelScope > GitHub）。
      sources = orderedSherpaCandidates(
        customBaseUrl: customUrl,
        preferredPreset: 'modelscope',
      );
    } else {
      // 单曲模式：严格使用所选来源，不做任何回退。
      final SherpaModelSource? single =
          buildSherpaSource(id: src, customBaseUrl: customUrl);
      if (single == null) {
        if (mounted) {
          showSnack(context, '请先填写自定义服务器根地址。');
        }
        setState(() {
          _downloading = false;
          _status = '';
        });
        return;
      }
      sources = <SherpaModelSource>[single];
    }

    SherpaDownloadResult? result;
    String? lastMessage;
    for (final SherpaModelSource source in sources) {
      setState(() => _status = '正在从「${source.label}」下载…');
      result = await SherpaModelDownloadService.downloadModel(
        source: source,
        model: _model,
        onProgress: (double? p, int received, int? total, double? speed) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            final String size = total != null
                ? '${_formatBytes(received)} / ${_formatBytes(total)}'
                : _formatBytes(received);
            final String spd = _formatSpeed(speed);
            _status = '正在从「${source.label}」下载：$size'
                '${spd.isNotEmpty ? ' · $spd' : ''}';
          });
        },
      );
      if (result.success) break;
      lastMessage = result.message;
      // 单曲模式严格不回退：失败时立即结束。
      if (src != 'auto') break;
    }

    if (result?.success == true) {
      await widget.controller.setSherpaModelReady(result!.modelDir);
      if (mounted) {
        showSnack(context, '语音模型已就绪，可长按聊天麦克风按钮使用。');
      }
      setState(() {
        _downloading = false;
        _status = '';
        _progress = null;
      });
    } else {
      if (mounted) {
        showSnack(context, lastMessage ?? '模型下载失败。');
      }
      setState(() {
        _downloading = false;
        _status = '';
        _progress = null;
      });
    }
  }

  Future<void> _delete() async {
    await SherpaModelDownloadService.deleteModel(_model.id);
    await widget.controller.setSherpaModelReady(null);
    // 删除模型后自动关闭语音输入（未就绪时不允许开启）。
    await widget.controller.saveVoiceInputEnabled(false);
    if (mounted) {
      showSnack(context, '已删除本地模型。');
    }
    setState(() {});
  }
}
