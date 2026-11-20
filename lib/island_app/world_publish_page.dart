import 'dart:convert';

import 'package:flutter/material.dart';

import '../utils/action_table.dart';
import 'package:flutter/services.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/island_app/world_tag_suggestions.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/world_editor/world_editor_form.dart';
import 'package:dna/services/export_file_utils.dart';
import 'package:dna/services/world_export_import_service.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/app_editor_frame.dart';
import 'package:dna/widgets/fit_text.dart';

/// 发布世界卡：选一个本地世界，**在完整世界观编辑器里**改完再发。
///
/// 发布 = 快照上传：编辑器里的那份是「待发布副本」，提交后社区存一份，本地世界
/// 不动。本地 id 与社区 id 是两套（社区那份由后端分配 UUID），混用会撞。
///
/// 发的是**裸 World.toJson()**，不是 WorldExportImportService.exportWorld 的带
/// 信封格式 —— 服务端只读顶层的 name / summary / tags / entries。
class WorldPublishPage extends StatefulWidget {
  const WorldPublishPage({super.key, this.source, this.publisher});

  /// 本地世界来源（窄接口）。为空时页面只给提示。
  final WorldPublishSource? source;

  /// 发布回调（测试可注入）。为空时走 [ApiClient.publishWorld]。
  final Future<Map<String, dynamic>> Function(String rawJson)? publisher;

  @override
  State<WorldPublishPage> createState() => _WorldPublishPageState();
}

class _WorldPublishPageState extends State<WorldPublishPage> {
  /// 「从 JSON 识别」展开的文本框。
  final TextEditingController _jsonController = TextEditingController();
  bool _showJson = false;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  /// 打开完整编辑器；保存时把 World 交给社区。
  Future<void> _openEditor(World? initial) async {
    // 候选标签在**社区页**拉好再传进去：编辑器自己不碰社区接口。
    final List<String> suggestions = await loadWorldTagSuggestions();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityWorldEditorPage(
          world: initial,
          title: '发布世界卡',
          tagSuggestions: suggestions,
          saveLabel: '发布到社区',
          onSave: _publish,
        ),
      ),
    );
  }

  /// 保存 = 发布。抛异常会让编辑器停在原地并提示，用户不会丢内容。
  Future<void> _publish(World world) async {
    final String raw = jsonEncode(world.toJson());
    final Future<Map<String, dynamic>> Function(String)? publish =
        widget.publisher;
    final Map<String, dynamic> result = publish != null
        ? await publish(raw)
        : await ApiClient.instance.publishWorld(raw);
    if (!mounted) return;
    final bool reused = result['reused'] == true;
    _toast(reused ? '这个世界之前已经提交过，正在审核中' : '已提交，等待审核');
  }

  /// 把一段世界文本解析成 World，然后进编辑器。
  ///
  /// 支持三种格式（与编辑器里的「导入世界观」同一套）：本应用导出的 .dnaworld
  /// 信封、裸 World JSON、第三方世界书。
  Future<void> _openEditorFromText(String text) async {
    if (text.trim().isEmpty) {
      _toast('没有可识别的内容');
      return;
    }
    final ExportImportResult<World> parsed =
        WorldExportImportService.importWorld(text);
    final World? world = parsed.data;
    if (world == null) {
      _toast(parsed.message ?? '无法识别这份世界数据');
      return;
    }
    if (!mounted) return;
    await _openEditor(world);
  }

  /// 从剪贴板识别。
  Future<void> _importFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String raw = (data?.text ?? '').trim();
    if (raw.isEmpty) {
      _toast('剪贴板里没有可识别的 JSON');
      return;
    }
    await _openEditorFromText(raw);
  }

  /// 从 .dnaworld / .json 文件导入。
  Future<void> _importFromFile() async {
    final ExportImportResult<String?> picked = await ExportFileUtils.importText(
      exts: const <String>['dnaworld', 'json'],
      dialogTitle: '选择世界观文件',
    );
    if (!mounted) return;
    if (!picked.success) {
      _toast(picked.message ?? '读取文件失败');
      return;
    }
    if (picked.data == null) return; // 用户取消
    await _openEditorFromText(picked.data!);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final List<World> worlds = widget.source?.localWorlds() ?? const <World>[];
    return Scaffold(
      appBar: AppBar(title: const Text('发布世界卡')),
      body: widget.source == null
          ? _empty(context, '当前环境没有可读取的本地世界')
          : _list(context, worlds),
    );
  }

  Widget _empty(BuildContext context, String text) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.public_off_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            AppSpacing.hMd,
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<World> worlds) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            '选一个本地世界、导入一份世界书，或者直接新建，在完整编辑器里改完再发布。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: () => _openEditor(null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建世界并发布'),
              ),
              OutlinedButton.icon(
                onPressed: _importFromClipboard,
                icon: const Icon(Icons.content_paste_go_outlined, size: 18),
                label: const Text('从剪贴板识别'),
              ),
              OutlinedButton.icon(
                onPressed: _importFromFile,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('导入 .dnaworld'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _showJson = !_showJson),
                icon: const Icon(Icons.data_object, size: 18),
                label: const Text('从 JSON 识别'),
              ),
            ],
          ),
        ),
        if (_showJson)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _jsonController,
                  minLines: 6,
                  maxLines: 12,
                  style: const TextStyle(fontSize: AppFontSize.caption),
                  decoration: const InputDecoration(
                    hintText: '在此粘贴导出的世界 JSON（.dnaworld 信封或裸 World JSON）…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                AppSpacing.hXs,
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => _openEditorFromText(_jsonController.text),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('识别并继续'),
                  ),
                ),
              ],
            ),
          ),
        AppSpacing.hMd,
        if (worlds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              '或从本地世界开始',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        if (worlds.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: _empty(context, '你还没有创建过世界，先在「世界」里建一个吧'),
          )
        else
          for (final World w in worlds)
            ListTile(
              title: Text(
                w.name.isEmpty ? '未命名世界' : w.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                <String>[
                  if (w.entries.isNotEmpty) '${w.entries.length} 词条',
                  if (w.summary.isNotEmpty) w.summary,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: () => _openEditor(w),
            ),
      ],
    );
  }
}

/// 社区侧的世界观编辑页：社区壳自带 chrome，直接套共享表单。
class CommunityWorldEditorPage extends StatefulWidget {
  const CommunityWorldEditorPage({
    super.key,
    this.world,
    this.title,
    this.tagSuggestions = const <String>[],
    this.saveLabel = '发布到社区',
    required this.onSave,
  });

  final World? world;
  final String? title;
  final List<String> tagSuggestions;
  final String saveLabel;
  final Future<void> Function(World world) onSave;

  @override
  State<CommunityWorldEditorPage> createState() =>
      _CommunityWorldEditorPageState();
}

class _CommunityWorldEditorPageState extends State<CommunityWorldEditorPage> {
  final WorldFormController _form = WorldFormController();
  bool _saving = false;

  /// 「世界名称」为空时的就地校验文案（审计 3.5：校验不能靠一闪而过的 snackbar）。
  ///
  /// 名称字段的 TextField 在共享的 [WorldEditorForm] 里，那个组件没有暴露
  /// 字段级 errorText 的入口（它的注释写明「要不要校验全归外壳决定」），
  /// 所以外壳把错误**常驻渲染在表单正上方**——紧挨着第一个字段、不随 snackbar 消失；
  /// 下一次点保存通过校验时清掉。
  String? _nameError;

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  static String _errorText(Object e) {
    final String text = e.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  Future<void> _save() async {
    if (_saving) return;
    final World world = _form.current();
    if (world.name.trim().isEmpty) {
      // 就地报错：错误条常驻在表单顶部（世界名称就是第一个字段），
      // 用户补完再点保存就消失。
      setState(() => _nameError = '请填写世界名称再发布');
      return;
    }
    setState(() {
      _nameError = null;
      _saving = true;
    });
    try {
      await widget.onSave(world);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: FitText(_errorText(e))));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _handlePop(bool didPop, Object? result) async {
    if (didPop || !mounted) return;
    if (!_form.isDirty) {
      Navigator.of(context).pop(result);
      return;
    }
    // 「放弃修改？」的文案与按钮由动作表统一（5 个外壳原来各抄一遍）。
    if (!await confirmDiscardEdits(context)) return;
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        appBar: AppBar(
          title: FitText(widget.title ?? '发布世界卡'),
          actions: <Widget>[
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check, size: 18),
              label: FitText(widget.saveLabel),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            if (_nameError != null) _InlineFormError(message: _nameError!),
            Expanded(
              child: WorldEditorForm(
                world: widget.world,
                formController: _form,
                tagSuggestions: widget.tagSuggestions,
                // 错误同时落在字段上（能定位）与表单顶部（读屏可播报）。
                nameError: _nameError,
                onNameChanged: () {
                  if (_nameError == null) return;
                  setState(() => _nameError = null);
                },
              ),
            ),
          ],
        ),
        floatingActionButton: AppEditorFab(
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: FitText(widget.saveLabel),
        ),
      ),
    );
  }
}

/// 表单级就地错误条：贴在表单顶部，**不自动消失**（与 snackbar 相反）。
///
/// 用 errorContainer / onErrorContainer 语义色，并标为 live region ——
/// 读屏用户在保存失败时能听到这条错误，而不是只看到颜色变化。
class _InlineFormError extends StatelessWidget {
  const _InlineFormError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: cs.errorContainer,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, size: 18, color: cs.onErrorContainer),
            AppSpacing.wSm,
            Expanded(
              child: FitText(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
