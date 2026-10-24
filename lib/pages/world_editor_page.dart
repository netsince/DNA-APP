// ignore_for_file: deprecated_member_use
import 'dart:convert';

import 'package:flutter/material.dart';

import '../island_app/api/client.dart';
import '../models/world.dart';
import '../services/export_file_utils.dart';
import '../services/world_export_import_service.dart';
import '../state/app_controller.dart';
import '../utils/id_utils.dart';
import '../widgets/app_editor_frame.dart';
import '../widgets/fit_text.dart';
import 'package:dna/widgets/export_import/transport_source_dialog.dart';
import 'world_editor/world_editor_form.dart';

/// 世界观编辑器**外壳**：顶栏、菜单、保存按钮、导入导出、导航都在这里。
///
/// 表单本体在 [WorldEditorForm]（只有字段与词条），通过 [WorldFormController] 取值/回填。
/// 这样「怎么存、按钮叫什么、要不要校验」只由宿主决定，表单不再自带一套行为 ——
/// 之前社区里出现「按钮写保存、点下去却发布」就是两边混在一起导致的。
class WorldEditorPage extends StatefulWidget {
  const WorldEditorPage({
    super.key,
    this.controller,
    this.world,
    this.onSave,
    this.title,
    this.tagSuggestions = const <String>[],
    this.saveLabel = '保存',
  });

  /// 本地世界库。社区发布/编辑世界卡时**不传**。
  final AppController? controller;

  final World? world;

  /// 保存回调。给了它就用它，不再写本地库。
  final Future<void> Function(World world)? onSave;

  /// 顶栏标题；为空时按「创建世界 / 编辑世界」自动判断。
  final String? title;

  /// 标签候选，由调用方注入（表单自己不拉社区接口）。
  final List<String> tagSuggestions;

  /// 保存按钮文案：本体「保存」/ 社区「发布到社区」/ 编辑「保存并重新提审」。
  final String saveLabel;

  @override
  State<WorldEditorPage> createState() => _WorldEditorPageState();
}

class _WorldEditorPageState extends State<WorldEditorPage> {
  final WorldFormController _form = WorldFormController();

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  /// 世界观导出扩展名。
  static const String _fileExt = 'dnaworld';

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: FitText(text)),
    );
  }

  Future<void> _save() async {
    final World world = _form.current();
    // 名称必填由**宿主**决定（表单只交值）。
    if (world.name.trim().isEmpty) {
      _snack('请填写世界名称');
      return;
    }
    final Future<void> Function(World)? onSave = widget.onSave;
    if (onSave != null) {
      await onSave(world);
    } else {
      await widget.controller!.upsertWorld(world);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 导出：询问目的地（剪贴板 / 文件）后导出当前表单内容。
  Future<void> _copyToClipboard() async {
    final ExportTarget? target = await showExportTargetDialog(
      context: context,
      title: '导出世界观',
      description: '导出内容为该世界的完整设定与全部词条。',
    );
    if (target == null || !mounted) return;

    final World currentWorld = _form.current();
    final ExportImportResult<String> result =
        WorldExportImportService.exportWorld(currentWorld);
    if (!mounted) return;
    if (!result.success) {
      _snack(result.message ?? '导出失败');
      return;
    }

    if (target == ExportTarget.clipboard) {
      final ExportImportResult<void> copyResult =
          await WorldExportImportService.copyToClipboard(result.data!);
      if (!mounted) return;
      _snack(copyResult.success
          ? '已复制到剪贴板，可以粘贴分享'
          : (copyResult.message ?? '复制到剪贴板失败'));
      return;
    }

    final ExportImportResult<String?> fileResult =
        await ExportFileUtils.exportText(
      content: result.data!,
      fileName: ExportFileUtils.buildFileName(
        name: currentWorld.name,
        fallbackName: '世界',
        ext: _fileExt,
      ),
      ext: _fileExt,
      dialogTitle: '导出世界观',
    );
    if (!mounted) return;
    if (!fileResult.success) {
      _snack(fileResult.message ?? '导出到文件失败');
      return;
    }
    _snack(fileResult.data == null ? '已取消导出' : '已导出到：${fileResult.data}');
  }

  /// 导入：解析后回填表单；有本地库时顺带落盘（社区模式只回填，不建本地世界）。
  Future<void> _importFromClipboard() async {
    final ImportSource? source = await showImportSourceDialog(
      context: context,
      title: '导入世界观',
      description: '支持本应用导出的世界观文件与直接的世界 JSON。',
    );
    if (source == null || !mounted) return;

    final String? content;
    if (source == ImportSource.clipboard) {
      final ExportImportResult<String> pasteResult =
          await WorldExportImportService.pasteFromClipboard();
      if (!mounted) return;
      if (!pasteResult.success) {
        _snack(pasteResult.message ?? '读取剪贴板失败');
        return;
      }
      content = pasteResult.data;
    } else {
      final ExportImportResult<String?> fileResult =
          await ExportFileUtils.importText(
        exts: const <String>[_fileExt, 'json'],
        dialogTitle: '选择世界观文件',
      );
      if (!mounted) return;
      if (!fileResult.success) {
        _snack(fileResult.message ?? '读取文件失败');
        return;
      }
      if (fileResult.data == null) return;
      content = fileResult.data;
    }

    if (content == null || content.isEmpty) {
      _snack('没有可导入的内容');
      return;
    }

    final ExportImportResult<World> importResult =
        WorldExportImportService.importWorld(content);
    if (!mounted) return;
    if (!importResult.success) {
      _snack(importResult.message ?? '导入失败');
      return;
    }

    World worldToImport = importResult.data!;
    final AppController? controller = widget.controller;
    if (controller != null) {
      if (controller.getWorldById(worldToImport.id) != null) {
        worldToImport = worldToImport.copyWith(id: newId());
        if (!mounted) return;
        _snack('ID 与已有世界冲突，已自动创建为新世界');
      }
      await controller.upsertWorld(worldToImport);
    }
    if (!mounted) return;
    _form.reset(worldToImport);
    _snack('导入成功');
  }

  /// 发布到社区：先落盘（社区读的是本地世界），再提交。
  Future<void> _publishToCommunity() async {
    final World current = _form.current();
    if (current.name.trim().isEmpty) {
      _snack('先给世界起个名字');
      return;
    }
    try {
      await widget.controller!.upsertWorld(current);
      final Map<String, dynamic> result =
          await ApiClient.instance.publishWorld(jsonEncode(current.toJson()));
      if (!mounted) return;
      final bool reused = result['reused'] == true;
      _snack(reused ? '这个世界之前已经提交过，正在审核中' : '已提交，等待审核');
    } catch (e) {
      _snack('发布失败：$e');
    }
  }

  /// 返回时若还有未保存修改，先确认；没有修改就直接走。
  Future<void> _handlePop(bool didPop, Object? result) async {
    if (didPop) return;
    if (!mounted) return;
    if (!_form.isDirty) {
      Navigator.of(context).pop(result);
      return;
    }
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const FitText('放弃修改？'),
        content: const FitText('还有未保存的修改，返回会丢失。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const FitText('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const FitText('放弃'),
          ),
        ],
      ),
    );
    if (!mounted || discard != true) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.world == null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
      appBar: AppBar(
        title: FitText(widget.title ?? (isNew ? '创建世界' : '编辑世界')),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String value) {
              switch (value) {
                case 'copy':
                  _copyToClipboard();
                  break;
                case 'import':
                  _importFromClipboard();
                  break;
                case 'publish':
                  _publishToCommunity();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'copy',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.ios_share),
                    SizedBox(width: 8),
                    FitText('导出世界观'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'import',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.file_download_outlined),
                    SizedBox(width: 8),
                    FitText('导入世界观'),
                  ],
                ),
              ),
              // 「发布到社区」只在本地编辑器出现，且跟着「社区」开关走。
              if (widget.controller != null &&
                  widget.controller!.settings.enableCommunity)
                const PopupMenuItem<String>(
                  value: 'publish',
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.public_outlined),
                      SizedBox(width: 8),
                      FitText('发布到社区'),
                    ],
                  ),
                ),
            ],
          ),
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check, size: 18),
            label: Text(widget.saveLabel),
          ),
        ],
      ),
      body: WorldEditorForm(
        world: widget.world,
        formController: _form,
        tagSuggestions: widget.tagSuggestions,
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
