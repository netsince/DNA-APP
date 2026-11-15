/// 设置 → 语音输入（配置驱动版）。
///
/// 声明即页面：两张卡片的文案、下载源选项与写入时机全在这里，页面不再持有
/// 业务状态。行为对齐点与取舍理由（逐条对照旧 voice_input_settings_page.dart）：
/// * 「模型是否已就绪」只用 AppSettings 里已有的两个键判断
///   （sherpaModelReady + sherpaModelPath 结尾是当前模型 id），因此
///   「未就绪时开关置灰」能留在声明层（enabledWhen），不需要页面代码；
/// * 下载源四选一的选项文案（含每条副标题）原样照搬，saveMode 默认即时落盘
///   （旧页面是 RadioGroup.onChanged 里立刻 saveSherpaModelSource）；
/// * 模型下载/重下/删除、自定义服务器地址输入是异步动作或文本框
///   （声明类型里没有文本项），各包一条 SettingAction。
library;

import 'package:flutter/material.dart';

import '../../models/voice_models.dart';
import '../../services/model_download_state.dart';
import '../../services/sherpa_model_service.dart';
import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import '../../utils/ui_feedback.dart';
import '../../widgets/fit_text.dart';
import 'package:dna/widgets/beta_tag.dart';
import '../../widgets/setting_section.dart';
import 'spec/settings_spec.dart';

/// 当前选中的识别模型是否已下载到本地。
///
/// 旧页面用 settings.sherpaModelReady && path.endsWith(model.id) 判断；
/// 两个字段都在 AppSettings 里，所以这条判断可以留在声明层。
bool _modelReadyForCurrent(SettingsRuntime runtime) {
  final String? path = runtime.settings.sherpaModelPath;
  return runtime.settings.sherpaModelReady &&
      path != null &&
      path.endsWith(voiceModelById(runtime.settings.selectedVoiceModelId).id);
}

/// 语音输入页的完整声明。
final FieldsEntry voiceInputEntry = FieldsEntry(
  id: 'voiceInput',
  groupId: SettingsGroupId.voice,
  icon: Icons.mic_none_outlined,
  title: '语音输入',
  subtitle: '用说话代替打字',
  gate: SettingsGate.voiceInput,
  sections: <SettingSectionSpec>[
    SettingSectionSpec(
      id: 'voiceInput.recognizer',
      icon: Icons.mic_outlined,
      title: '离线语音识别',
      description: '本机把说的话转成文字，不联网。',
      // 旧页面这张卡带 Beta 标记。
      trailing: const BetaTag(),
      items: <SettingItemSpec>[
        SettingToggle(
          id: 'voiceInput.enabled',
          title: '启用语音输入',
          // 状态指示型副标题：就绪 / 未就绪各一句（旧页面 _readyForCurrent 两态）。
          subtitleOf: (SettingsRuntime r) => _modelReadyForCurrent(r)
              ? '模型已就绪，随时可用。'
              : '需先下载下方的识别模型。',
          hint: '模型未下载完成前无法开启。',
          key: 'voiceInputEnabled',
          enabledWhen: _modelReadyForCurrent,
        ),
        SettingChoice<String>(
          id: 'voiceInput.model',
          title: '识别模型规格',
          key: 'selectedVoiceModelId',
          defaultValue: kVoiceModelDefaultId,
          layout: ChoiceLayout.dropdown,
          // 旧页面：下载中禁掉模型下拉 —— 中途换模型会让完成后的就绪标记
          // 与当前选择对不上。
          enabledWhen: (SettingsRuntime r) => !r.modelDownloading,
          options: <ChoiceOption<String>>[
            for (final VoiceModelOption m in kVoiceModelOptions)
              ChoiceOption<String>(value: m.id, label: m.label),
          ],
        ),
        SettingAction(
          id: 'voiceInput.modelHint',
          title: '模型说明',
          searchable: false,
          builder: (BuildContext context, AppController controller) =>
              SettingHint(
                voiceModelById(
                  controller.settings.selectedVoiceModelId,
                ).description,
                icon: Icons.info_outline,
              ),
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'voiceInput.download',
      icon: Icons.download_for_offline_outlined,
      title: '模型下载与管理',
      description: '下载一次即可离线使用。',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'voiceInput.modelPanel',
          title: '离线识别模型',
          subtitle: '下载、重新下载或删除模型',
          builder: (BuildContext context, AppController controller) =>
              _ModelManagerPanel(controller: controller),
        ),
        SettingChoice<String>(
          id: 'voiceInput.source',
          title: '模型下载源',
          key: 'sherpaModelSource',
          defaultValue: 'auto',
          layout: ChoiceLayout.radioList,
          // 同上：下载中换源，下载仍在按旧源跑。
          enabledWhen: (SettingsRuntime r) => !r.modelDownloading,
          options: const <ChoiceOption<String>>[
            ChoiceOption<String>(
              value: 'auto',
              label: '自动选择（推荐）',
              subtitle: '国内优先 ModelScope，海外用 GitHub',
            ),
            ChoiceOption<String>(
              value: 'modelscope',
              label: 'ModelScope 镜像',
              subtitle: '国内高速节点，无需代理直连',
            ),
            ChoiceOption<String>(
              value: 'github',
              label: 'GitHub 官方源',
              subtitle: '官方发布仓库，需良好海外网络环境',
            ),
            ChoiceOption<String>(
              value: 'custom',
              label: '自定义服务器源',
              subtitle: '使用自行搭建的模型存储服务',
            ),
          ],
        ),
        SettingAction(
          id: 'voiceInput.customUrl',
          title: '自定义服务器地址',
          subtitle: '自建模型存储服务的根地址',
          visibleWhen: (SettingsRuntime runtime) =>
              runtime.settings.sherpaModelSource == 'custom',
          builder: (BuildContext context, AppController controller) =>
              _CustomServerUrlField(controller: controller),
        ),
      ],
    ),
  ],
);

/// 识别模型的下载/重下/删除（异步，含进度与控制）。
class _ModelManagerPanel extends StatefulWidget {
  const _ModelManagerPanel({required this.controller});

  final AppController controller;

  @override
  State<_ModelManagerPanel> createState() => _ModelManagerPanelState();
}

class _ModelManagerPanelState extends State<_ModelManagerPanel> {
  bool _downloading = false;
  double? _progress;
  String _status = '';

  bool get _readyForCurrent {
    final String? p = widget.controller.settings.sherpaModelPath;
    return widget.controller.settings.sherpaModelReady &&
        p != null &&
        p.endsWith(_model.id);
  }

  VoiceModelOption get _model =>
      voiceModelById(widget.controller.settings.selectedVoiceModelId);

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

  Future<void> _download() async {
    ModelDownloads.begin();
    try {
      await _runDownload();
    } finally {
      ModelDownloads.end();
    }
  }

  Future<void> _runDownload() async {
    final String src = widget.controller.settings.sherpaModelSource;
    final String? customUrl = widget.controller.settings.sherpaCustomBaseUrl;

    setState(() {
      _downloading = true;
      _progress = null;
      _status = src == 'auto' ? '正在选择可用下载源…' : '正在准备下载…';
    });

    final List<SherpaModelSource> sources;
    if (src == 'auto') {
      // 自动选择：探测并按顺序回退（自定义 > ModelScope > GitHub）。
      sources = orderedSherpaCandidates(
        customBaseUrl: customUrl,
        preferredPreset: 'modelscope',
      );
    } else {
      // 单源模式：严格使用所选来源，不做任何回退。
      final SherpaModelSource? single = buildSherpaSource(
        id: src,
        customBaseUrl: customUrl,
      );
      if (single == null) {
        if (mounted) showSnack(context, '请先填写自定义服务器根地址。');
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
            _status =
                '正在从「${source.label}」下载：$size'
                '${spd.isNotEmpty ? ' · $spd' : ''}';
          });
        },
      );
      if (result.success) break;
      lastMessage = result.message;
      // 单源模式严格不回退：失败时立即结束。
      if (src != 'auto') break;
    }

    if (result?.success == true) {
      await widget.controller.setSherpaModelReady(result!.modelDir);
      if (mounted) {
        showSnack(context, '语音模型已就绪，可长按聊天麦克风按钮使用。');
      }
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = '';
        _progress = null;
      });
    } else {
      if (mounted) showSnack(context, lastMessage ?? '模型下载失败。');
      if (!mounted) return;
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
    if (!mounted) return;
    showSnack(context, '已删除本地模型。');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
      ],
    );
  }
}

/// 自定义下载源的服务器根地址。
///
/// 旧页面是 TextFormField + initialValue，每敲一个字符就
/// saveSherpaCustomBaseUrl(v.trim())（不是回车才存）；这里保持同样的时机：
/// 输入即写、写入前 trim，且不回灌设置值，避免把用户正在输入的尾部空格截掉。
class _CustomServerUrlField extends StatefulWidget {
  const _CustomServerUrlField({required this.controller});

  final AppController controller;

  @override
  State<_CustomServerUrlField> createState() => _CustomServerUrlFieldState();
}

class _CustomServerUrlFieldState extends State<_CustomServerUrlField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.controller.settings.sherpaCustomBaseUrl ?? '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(
          labelText: '服务器根地址',
          hintText: 'https://your-server/models',
          border: OutlineInputBorder(),
        ),
        onChanged: (String v) =>
            widget.controller.saveSherpaCustomBaseUrl(v.trim()),
      ),
    );
  }
}
