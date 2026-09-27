// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../services/tts/tts_audio_cache.dart';
import '../../services/tts/tts_service.dart';
import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import '../../utils/platform_capabilities.dart';
import '../../utils/ui_feedback.dart';
import 'package:dna/widgets/beta_tag.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/seed_input_field.dart';
import 'package:dna/widgets/setting_collapsible.dart';
import 'package:dna/widgets/setting_section.dart';
import 'tts_cache_page.dart';

/// 端侧语音合成（TTS）设置：开关、台词朗读、全局音色种子、模型管理与音频缓存。
///
/// **本次重构**（见 `SETTINGS_AUDIT.md`）：
/// * 5 张手写 `Card > Padding > Column` 样板 → 5 个 `SettingSection`；
/// * 全局音色种子改为**可折叠数值项**，收起态只显示「名称 + 当前值」；
/// * 卡片说明压到一行以内，模块清单、默认值等参考信息移入条目内说明；
/// * 「Token」等黑话改为「记忆容量」这类中文说法。
class TtsSettingsPage extends StatefulWidget {
  const TtsSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<TtsSettingsPage> createState() => _TtsSettingsPageState();
}

/// 全局音色种子未指定时的兜底值（服务端同样使用 1）。
const int kDefaultTtsSeed = 1;

class _TtsSettingsPageState extends State<TtsSettingsPage> {
  /// 界面数值上限（保持原有 32 位有符号整数上限，功能不变）。
  static const int _maxSeed = 0x7FFFFFFF;

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

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _refresh();
    _refreshCache();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
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
    } on TtsDownloadCancelled {
      if (mounted) {
        showSnack(context, '模型下载已取消。');
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

  Future<void> _cancel() async {
    TtsService.instance.cancelDownload();
    if (mounted) {
      setState(() {
        _fileInfo = '正在取消下载，请稍候…';
      });
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
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool enabled = widget.controller.settings.ttsEnabled;
    final s = widget.controller.settings;
    final int? seed = s.ttsGlobalSeed;

    return Scaffold(
      appBar: AppBar(title: const FitText('端侧语音合成')),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          // ===== 1. 朗读开关与偏好 =====
          SettingSection(
            icon: Icons.record_voice_over_outlined,
            title: '语音朗读',
            description: '让 AI 的消息可以朗读出来。',
            trailing: const BetaTag(),
            children: <Widget>[
              SettingSwitch(
                title: '启用端侧语音合成',
                subtitle: _ready ? '模型已就绪，随时可朗读。' : '需先下载下方的语音模型。',
                value: _ready && enabled,
                onChanged:
                    _ready ? (bool v) => widget.controller.saveTtsEnabled(v) : null,
              ),
              SettingSwitch(
                title: '只读引号里的台词',
                subtitle: '跳过动作与旁白，只念说话内容。',
                value: s.ttsQuoteOnly,
                onChanged: (bool v) => widget.controller.saveTtsQuoteOnly(v),
              ),
            ],
          ),

          // ===== 2. 全局音色种子 =====
          SettingSection(
            icon: Icons.tune,
            title: '全局音色',
            description: '角色卡没单独指定嗓音时使用。',
            children: <Widget>[
              _SeedSetting(
                value: seed,
                maxValue: _maxSeed,
                onChanged: (int? v) =>
                    widget.controller.saveTtsGlobalSeed(v),
              ),
            ],
          ),

          // ===== 3. 离线语音模型 =====
          SettingSection(
            icon: Icons.download_for_offline_outlined,
            title: '离线语音模型',
            description: '下载一次，之后不再联网。',
            children: <Widget>[
              SettingHint('模型约 400MB，包含声学与声码模块。'),
              if (_downloading) ...<Widget>[
                if (_progress != null) ...<Widget>[
                  LinearProgressIndicator(value: _progress),
                  AppSpacing.hSm,
                ],
                if (_fileInfo.isNotEmpty)
                  FitText(
                    _fileInfo,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
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
                  leading: Icon(
                    Icons.check_circle,
                    color: cs.primary,
                  ),
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
          ),

          // ===== 4. 语音音频缓存 =====
          SettingSection(
            icon: Icons.cleaning_services_outlined,
            title: '语音音频缓存',
            description: '听过的台词会存下来，再听不再合成。',
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest
                      .withValues(alpha: AppAlpha.half),
                  borderRadius: AppRadius.smAll,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: FitText(
                        _cacheLoading
                            ? '正在计算缓存…'
                            : '已缓存 $_cacheCount 条音频 '
                                '(${_formatBytes(_cacheBytes)})',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: AppWeight.medium,
                        ),
                      ),
                    ),
                    AppSpacing.wSm,
                    FilledButton.tonalIcon(
                      onPressed: _cacheLoading || _cacheCount == 0
                          ? null
                          : _clearCache,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                      label: const FitText('一键清空'),
                    ),
                  ],
                ),
              ),
              SettingTile(
                icon: Icons.pie_chart_outline,
                title: '缓存详情',
                subtitle: '查看占用空间与缓存条目',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TtsCachePage()),
                ),
              ),
            ],
          ),

          // ===== 5. 角色背景音乐 =====
          SettingSection(
            icon: Icons.music_note_outlined,
            title: '角色背景音乐',
            description: '进入聊天时播放角色的专属配乐。',
            children: <Widget>[
              SettingHint(
                '在「TA 编辑」里为角色绑定音乐。仅保存在本机，群聊不播放。',
                icon: Icons.info_outline,
              ),
              CollapsibleNumberSetting(
                title: '背景音乐音量',
                value: s.bgmVolume.clamp(0, 100),
                min: 0,
                max: 100,
                step: 5,
                unit: '%',
                helper: '朗读台词或语音输入时音量会自动调小，结束后恢复。',
                onChanged: (int v) => widget.controller.saveBgmVolume(v),
              ),
              SettingSwitch(
                title: '允许超过 10MB 的音乐',
                subtitle: '开启后可选更大的音频文件。',
                value: s.bgmSizeLimitUnlocked,
                onChanged: (bool v) =>
                    widget.controller.saveBgmSizeLimitUnlocked(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 全局音色种子的可折叠输入项。
///
/// **外观**与 [CollapsibleNumberSetting] 保持一致（收起态「名称 + 当前值」），
/// 但数值范围极大（0 ~ 2147483647），滑块无法逐档选择，因此展开态仍为
/// 原有的 [SeedInputField]（数字输入 + 随机 + 试听），**功能不变**。
class _SeedSetting extends StatefulWidget {
  const _SeedSetting({
    required this.value,
    required this.maxValue,
    required this.onChanged,
  });

  /// 当前种子；null 表示未指定（实际使用默认值 1）。
  final int? value;

  final int maxValue;
  final ValueChanged<int?> onChanged;

  @override
  State<_SeedSetting> createState() => _SeedSettingState();
}

class _SeedSettingState extends State<_SeedSetting> {
  late final TextEditingController _ctrl;
  bool _expanded = false;
  bool _adjusting = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void didUpdateWidget(_SeedSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_adjusting) return;
    final String next = widget.value?.toString() ?? '';
    if (next != _ctrl.text) _ctrl.text = next;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 未指定种子时显示默认值。
  String get _displayValue =>
      _ctrl.text.trim().isEmpty ? '默认 1' : _ctrl.text.trim();

  void _clear() {
    _ctrl.text = '';
    widget.onChanged(null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ===== 收起态：名称 + 当前值 =====
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: AppRadius.xsAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FitText('音色种子', style: AppTextStyles.body(theme)),
                ),
                AppSpacing.wMd,
                FitText(
                  _displayValue,
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

        // ===== 展开态：原输入控件 + 说明 =====
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
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
                  label: '音色种子（0 - ${widget.maxValue}）',
                  maxValue: widget.maxValue,
                  onChanged: (String raw) {
                    final String text = raw.trim();
                    final int? seed =
                        text.isEmpty ? null : int.tryParse(text);
                    _adjusting = true;
                    widget.onChanged(seed);
                    _adjusting = false;
                    setState(() {});
                  },
                ),
                AppSpacing.hSm,
                FitText(
                  '种子决定嗓音与语气：数值不同，音色不同；相同种子结果稳定。'
                  '留空则按默认值 $kDefaultTtsSeed 处理。',
                  style:
                      AppTextStyles.caption(theme).copyWith(color: cs.outline),
                ),
                if (_ctrl.text.trim().isNotEmpty) ...<Widget>[
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
