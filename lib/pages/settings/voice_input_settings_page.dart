import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../models/voice_models.dart';
import '../../services/sherpa_model_service.dart';
import '../../state/app_controller.dart';
import '../../utils/platform_capabilities.dart';
import '../../utils/ui_feedback.dart';
import 'package:dna/widgets/beta_tag.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

/// 语音输入设置：选择识别模型、选择下载源、下载/删除离线模型。
///
/// **本次重构**（见 `SETTINGS_AUDIT.md`）：
/// * 原「3 张卡装 3 个设置项」→ **2 张卡**：
///   模型规格并入「离线语音识别」卡，不再单独成卡；
/// * 3 处手写 `Card > Padding > Column` 样板 → `SettingSection`；
/// * 卡片说明压到一行以内，超长提示（33 字）改写并下沉为条目说明。
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
    // Web 端不支持离线语音输入：整页置灰不可用。
    if (!PlatformCapabilities.voiceInputSupported) {
      return Scaffold(
        appBar: AppBar(title: const FitText('语音输入')),
        body: const Center(
          child: FitText('当前平台不支持离线语音输入'),
        ),
      );
    }
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final s = widget.controller.settings;

    return Scaffold(
      appBar: AppBar(title: const FitText('语音输入')),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          // ===== 1. 离线语音识别（开关 + 模型规格合并为一张卡） =====
          SettingSection(
            icon: Icons.mic_outlined,
            title: '离线语音识别',
            description: '本机把说的话转成文字，不联网。',
            trailing: const BetaTag(),
            children: <Widget>[
              SettingSwitch(
                title: '启用语音输入',
                subtitle:
                    _readyForCurrent ? '模型已就绪，随时可用。' : '需先下载下方的识别模型。',
                value: _readyForCurrent && s.voiceInputEnabled,
                onChanged: _readyForCurrent
                    ? (bool v) => widget.controller.saveVoiceInputEnabled(v)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '识别模型规格',
                  ),
                  child: DropdownButton<VoiceModelOption>(
                    value: _model,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: kVoiceModelOptions
                        .map((VoiceModelOption m) => DropdownMenuItem<VoiceModelOption>(
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
              ),
              SettingHint(_model.description, icon: Icons.info_outline),
            ],
          ),

          // ===== 2. 模型下载与管理（下载源并入本卡） =====
          SettingSection(
            icon: Icons.download_for_offline_outlined,
            title: '模型下载与管理',
            description: '下载一次即可离线使用。',
            children: <Widget>[
              if (_downloading) ...<Widget>[
                LinearProgressIndicator(value: _progress),
                AppSpacing.hSm,
                FitText(
                  _status,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                ),
                AppSpacing.hMd,
              ],
              if (_readyForCurrent) ...<Widget>[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_circle, color: cs.primary),
                  title: const FitText('模型已就绪（可离线使用）'),
                  subtitle: FitText('当前模型：${_model.label}'),
                ),
                AppSpacing.hSm,
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _downloading ? null : _download,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const FitText('重新下载'),
                      ),
                    ),
                    AppSpacing.wMd,
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
                    icon: const Icon(Icons.download),
                    label: FitText(_downloading ? '下载中…' : '下载离线语音模型'),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: RadioGroup<String>(
                  groupValue: s.sherpaModelSource,
                  onChanged: (String? v) {
                    if (_downloading || v == null) return;
                    widget.controller.saveSherpaModelSource(v);
                    setState(() {});
                  },
                  child: Column(
                    children: const <Widget>[
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: FitText('自动选择（推荐）'),
                        subtitle: FitText('国内优先 ModelScope，海外用 GitHub'),
                        value: 'auto',
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: FitText('ModelScope 镜像'),
                        subtitle: FitText('国内高速节点，无需代理直连'),
                        value: 'modelscope',
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: FitText('GitHub 官方源'),
                        subtitle: FitText('官方发布仓库，需良好海外网络环境'),
                        value: 'github',
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: FitText('自定义服务器源'),
                        subtitle: FitText('使用自行搭建的模型存储服务'),
                        value: 'custom',
                      ),
                    ],
                  ),
                ),
              ),
              if (s.sherpaModelSource == 'custom')
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
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
            ],
          ),
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
