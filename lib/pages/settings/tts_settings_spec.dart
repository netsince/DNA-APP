/// 设置 → 语音合成（配置驱动版）。背景音乐已独立成 bgmEntry。
///
/// 声明即页面：五张卡片的文案、范围、写入时机全在这里，页面不再持有业务状态。
/// 行为对齐点与取舍理由（逐条对照旧 tts_settings_page.dart）：
/// * 四个分组、图标、标题、说明原样保留；「一拨即存」的开关直接走 key；
/// * 背景音乐音量旧页面是 CollapsibleNumberSetting(step 5, unit %)，对应
///   SettingInt(editor: collapsibleStepper)；旧页面把说明放在 helper 上，
///   渲染器把 hint 当 helper，所以那段文案写进 hint 而不是 subtitle；
/// * 音色种子整行是一条 SettingAction（理由见 _GlobalSeedSetting 的注释）；
/// * 模型下载/取消/删除是异步动作，包一条 SettingAction。
/// * 语音音频缓存不在这里管：存储空间页的「缓存」分类已经覆盖（同一份 tts_cache 目录）。
library;

import 'package:material_ui/material_ui.dart';

import '../../services/tts/tts_service.dart';
import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import '../../utils/ui_feedback.dart';
import '../../widgets/fit_text.dart';
import '../../widgets/seed_input_field.dart';
import 'package:dna/widgets/beta_tag.dart';
import '../../widgets/setting_section.dart';
import 'spec/settings_spec.dart';

/// 种子未指定时实际生效的值。
///
/// 依据不是文案而是代码：tts_service_io.dart 里
/// effectiveSeed = roleSeed ?? globalSeed ?? 1，所以 null 等价于 1。
/// 写在声明文件里，是为了旧页面被删掉后「默认 1」仍只有一个来源。
const int _defaultSeed = 1;

/// 种子输入上限：沿用 32 位有符号整数上限（旧页面的 _maxSeed）。
const int _maxSeed = 0x7FFFFFFF;

// 动作项的 title/subtitle 在声明里只服务搜索与断言，真正渲染的是 builder；
// 两边共用同一份常量，免得同一条文案写两遍后各改各的。
const String _seedTitle = '音色种子';

/// 探测端侧模型是否就绪，并校正「模型没了但开关还开着」的脏状态。
///
/// 这是旧 tts_settings_page.dart 里 `_refresh()` 的等价物：它在 init 与每次
/// controller 变化时跑，模型不就绪就把 ttsEnabled 写回 false。搬到声明的
/// 运行态钩子里之后，只在进入页面时跑一次 —— 少了每次设置变化就查文件的开销，
/// 行为对用户可见的部分一致（脏状态仍会被纠正）。
Future<SettingsRuntime> _resolveTtsRuntime(
  AppController controller,
  SettingsRuntime base,
) async {
  bool ready = false;
  try {
    ready = await TtsService.instance.isModelsReady();
  } catch (_) {
    ready = false;
  }
  if (!ready && controller.settings.ttsEnabled) {
    await controller.patchSettings('ttsEnabled', false);
  }
  return SettingsRuntime(
    settings: controller.settings,
    biometricEnrolled: base.biometricEnrolled,
    ttsModelsReady: ready,
  );
}

/// 语音合成页的完整声明。
final FieldsEntry ttsEntry = FieldsEntry(
  id: 'tts',
  groupId: SettingsGroupId.voice,
  icon: Icons.volume_up_outlined,
  title: '语音合成',
  subtitle: '让角色开口说话',
  gate: SettingsGate.tts,
  resolveRuntime: _resolveTtsRuntime,
  sections: <SettingSectionSpec>[
    SettingSectionSpec(
      id: 'tts.readAloud',
      icon: Icons.record_voice_over_outlined,
      title: '语音朗读',
      description: '让 AI 的消息可以朗读出来。',
      // 旧页面这张卡带 Beta 标记 —— 提示「该功能仍在打磨」。
      trailing: const BetaTag(),
      items: <SettingItemSpec>[
        SettingToggle(
          id: 'tts.enabled',
          title: '启用端侧语音合成',
          // 副标题是状态指示（就绪 / 未就绪各一句），声明里用 subtitleOf 表达。
          subtitleOf: (SettingsRuntime r) => r.ttsModelsReady == true
              ? '模型已就绪，随时可朗读。'
              : '需先下载下方的语音模型。',
          key: 'ttsEnabled',
          // 旧页面：模型没就绪时开关置灰（value 还强制显示为 false）。
          // 运行态由 ttsEntry.resolveRuntime 探测后传进来。
          enabledWhen: (SettingsRuntime r) => r.ttsModelsReady != false,
        ),
        SettingToggle(
          id: 'tts.quoteOnly',
          title: '只读引号里的台词',
          subtitle: '跳过动作与旁白，只念说话内容。',
          key: 'ttsQuoteOnly',
          defaultValue: true,
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'tts.globalVoice',
      icon: Icons.tune,
      title: '全局音色',
      description: '角色卡没单独指定嗓音时使用。',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'tts.globalSeed',
          title: _seedTitle,
          subtitle: '留空表示用默认值，相同种子音色稳定',
          builder: (BuildContext context, AppController controller) =>
              _GlobalSeedSetting(controller: controller),
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'tts.offlineModels',
      icon: Icons.download_for_offline_outlined,
      title: '离线语音模型',
      description: '下载一次，之后不再联网。',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'tts.modelPanel',
          title: '离线语音模型',
          subtitle: '下载、重新下载或删除模型',
          builder: (BuildContext context, AppController controller) =>
              _ModelDownloadPanel(controller: controller),
        ),
      ],
    ),
  ],
);

/// 「背景音乐」单列一页：它和语音合成没有关系（一个管角色说话，一个管聊天时的配乐），
/// 挤在同一页只会让两边都找不到。
final FieldsEntry bgmEntry = FieldsEntry(
  id: 'bgm',
  groupId: SettingsGroupId.voice,
  icon: Icons.music_note_outlined,
  title: '背景音乐',
  subtitle: '角色专属配乐与音量',
  sections: <SettingSectionSpec>[
    SettingSectionSpec(
      id: 'tts.bgm',
      icon: Icons.music_note_outlined,
      title: '角色背景音乐',
      description: '进入聊天时播放角色的专属配乐。',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'tts.bgmNotice',
          title: '背景音乐说明',
          searchable: false,
          builder: (BuildContext context, AppController controller) =>
              const SettingHint(
                '在「TA 编辑」里为角色绑定音乐。仅保存在本机，群聊不播放。',
                icon: Icons.info_outline,
              ),
        ),
        SettingInt(
          id: 'tts.bgmVolume',
          title: '背景音乐音量',
          hint: '朗读台词或语音输入时音量会自动调小，结束后恢复。',
          key: 'bgmVolume',
          defaultValue: 50,
          min: 0,
          max: 100,
          step: 5,
          unit: '%',
          saveMode: SettingsSaveMode.immediate,
        ),
        SettingToggle(
          id: 'tts.bgmSizeUnlocked',
          title: '允许超过 10MB 音乐',
          subtitle: '开启后可选更大的音频文件。',
          key: 'bgmSizeLimitUnlocked',
        ),
      ],
    ),
  ],
);

/// 全局音色种子（可空整数）。
///
/// 为什么不是 SettingInt：
/// * SettingInt 的写通道只能收 int —— 「清空成 null」表达不出来，而 null
///   （= 默认 1）与 0 是两种不同的音色，不能用同一个数字顶替；
/// * 旧控件的展开态是 SeedInputField，自带随机与试听，试听要异步合成并播放。
/// 两条合起来，整行只能留在 SettingAction 里自绘。
class _GlobalSeedSetting extends StatefulWidget {
  const _GlobalSeedSetting({required this.controller});

  final AppController controller;

  @override
  State<_GlobalSeedSetting> createState() => _GlobalSeedSettingState();
}

class _GlobalSeedSettingState extends State<_GlobalSeedSetting> {
  late final TextEditingController _ctrl;
  bool _expanded = false;

  int? get _seed => widget.controller.settings.ttsGlobalSeed;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _seed?.toString() ?? '');
  }

  @override
  void didUpdateWidget(_GlobalSeedSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String next = _seed?.toString() ?? '';
    if (next != _ctrl.text) _ctrl.text = next;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final String text = raw.trim();
    widget.controller.saveTtsGlobalSeed(
      text.isEmpty ? null : int.tryParse(text),
    );
    setState(() {});
  }

  void _clear() {
    _ctrl.text = '';
    widget.controller.saveTtsGlobalSeed(null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String text = _ctrl.text.trim();
    final String display = text.isEmpty ? '默认 $_defaultSeed' : text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: AppRadius.xsAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FitText(_seedTitle, style: AppTextStyles.body(theme)),
                ),
                AppSpacing.wMd,
                FitText(
                  display,
                  style: AppTextStyles.body(theme).copyWith(
                    color: cs.primary,
                    fontWeight: AppWeight.medium,
                  ),
                ),
                AppSpacing.wXs,
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: AppSize.iconInline,
                  color: cs.outline,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SeedInputField(
                  controller: _ctrl,
                  label: '音色种子（0 - $_maxSeed）',
                  maxValue: _maxSeed,
                  onChanged: _onChanged,
                ),
                AppSpacing.hSm,
                FitText(
                  '种子决定嗓音与语气：数值不同，音色不同；相同种子结果稳定。'
                  '留空则按默认值 $_defaultSeed 处理。',
                  style: AppTextStyles.caption(theme).copyWith(color: cs.outline),
                ),
                if (text.isNotEmpty) ...<Widget>[
                  AppSpacing.hXs,
                  TextButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const FitText('清除种子（恢复默认）'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 离线语音模型的下载/重下/删除面板（异步，含进度）。
class _ModelDownloadPanel extends StatefulWidget {
  const _ModelDownloadPanel({required this.controller});

  final AppController controller;

  @override
  State<_ModelDownloadPanel> createState() => _ModelDownloadPanelState();
}

class _ModelDownloadPanelState extends State<_ModelDownloadPanel> {
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
    if (bps >= 1024 * 1024) {
      return '${(bps / 1024 / 1024).toStringAsFixed(1)} MB/s';
    }
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${bps.toStringAsFixed(0)} B/s';
  }

  @override
  void initState() {
    super.initState();
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
    setState(() {
      _ready = ready;
      _status = ready ? '模型已就绪，完全离线合成' : '';
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
              ? '${_formatBytes(p.receivedBytes)} / '
                    '${_formatBytes(p.totalBytes!)}'
              : _formatBytes(p.receivedBytes);
          setState(() {
            _progress = prog;
            _bytesText = bytes;
            _speedText = p.speedBps != null ? _formatSpeed(p.speedBps!) : '';
            _fileInfo =
                '正在下载文件 ${p.doneFiles + 1} / ${p.totalFiles}：'
                '${p.currentFile}';
          });
        },
      );
      if (mounted) showSnack(context, '端侧语音模型已就绪。');
    } on TtsDownloadCancelled {
      if (mounted) showSnack(context, '模型下载已取消。');
    } catch (e) {
      if (mounted) showSnack(context, '模型下载失败：$e');
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

  void _cancel() {
    TtsService.instance.cancelDownload();
    if (mounted) {
      setState(() => _fileInfo = '正在取消下载，请稍候…');
    }
  }

  Future<void> _delete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const FitText('删除语音模型'),
        content: const FitText(
          '将删除本地约 400MB 的语音模型文件，删除后需重新下载方可播放。确定继续？',
        ),
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SettingHint('模型约 400MB，包含声学与声码模块。'),
        if (_downloading) ...<Widget>[
          if (_progress != null) ...<Widget>[
            LinearProgressIndicator(value: _progress),
            AppSpacing.hSm,
          ],
          if (_fileInfo.isNotEmpty)
            FitText(
              _fileInfo,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          if (_bytesText.isNotEmpty)
            FitText(
              _bytesText + (_speedText.isNotEmpty ? ' · $_speedText' : ''),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.primary,
                fontWeight: AppWeight.medium,
              ),
            ),
          AppSpacing.hMd,
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const FitText('取消下载'),
            ),
          ),
          AppSpacing.hXs,
        ],
        if (_ready) ...<Widget>[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle, color: cs.primary),
            title: const FitText('语音模型已就绪'),
            subtitle: FitText(_status),
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
              icon: Icon(_downloading ? Icons.hourglass_top : Icons.download),
              label: FitText(_downloading ? '下载中…' : '下载离线语音模型'),
            ),
          ),
        ],
      ],
    );
  }
}
