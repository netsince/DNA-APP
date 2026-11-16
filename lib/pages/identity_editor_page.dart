import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../models/user_identity.dart';
import '../services/export_file_utils.dart';
import '../services/identity_export_import_service.dart';
import '../state/app_controller.dart';
import '../utils/id_utils.dart';
import '../widgets/adaptive_text_field.dart';
import 'package:dna/widgets/export_import/transport_source_dialog.dart';
import 'package:dna/widgets/fit_text.dart';
import '../widgets/app_editor_frame.dart';

/// 用户身份（User Persona）编辑页。
class IdentityEditorPage extends StatefulWidget {
  const IdentityEditorPage({super.key, required this.controller, this.identity});

  final AppController controller;
  final UserIdentity? identity;

  @override
  State<IdentityEditorPage> createState() => _IdentityEditorPageState();
}

class _IdentityEditorPageState extends State<IdentityEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _personaController;
  late String _identityId;
  final ScrollController _scrollController = ScrollController();

  /// 名称必填：未填时就地报错，而不是弹一条 snackbar
  /// （审计 3.5「表单校验用 snackbar 而不是字段 errorText」）。
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final UserIdentity? identity = widget.identity;
    _identityId = identity?.id ?? newId();
    _nameController = TextEditingController(text: identity?.name ?? '');
    _personaController = TextEditingController(text: identity?.persona ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _personaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 把视口带回第一个出错的字段（名称在本页最上面）。
  void _revealFirstError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  UserIdentity _buildCurrentIdentity() {
    return UserIdentity(
      id: _identityId,
      name: _nameController.text.trim(),
      persona: _personaController.text.trim(),
      intro: '',
    );
  }

  Future<void> _save() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '请填写身份名称（必填）。');
      _revealFirstError();
      return;
    }
    final UserIdentity identity = _buildCurrentIdentity();
    await widget.controller.upsertIdentity(identity);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  /// 将当前编辑中的身份导出到剪贴板或文件，便于分享或跨设备传递。
  Future<void> _copyToClipboard() async {
    // 询问导出目的地(剪贴板 / 文件)
    final ExportTarget? target = await showExportTargetDialog(
      context: context,
      title: '导出身份',
      description: '导出内容为该身份的完整人设设定。',
    );
    if (target == null || !mounted) return;

    final UserIdentity identity = _buildCurrentIdentity();
    final ExportImportResult<String> result =
        IdentityExportImportService.exportIdentity(identity);
    if (!mounted) return;
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText(result.message ?? '导出失败')),
      );
      return;
    }

    if (target == ExportTarget.clipboard) {
      final ExportImportResult<void> copyResult =
          await IdentityExportImportService.copyToClipboard(result.data!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: FitText(
            copyResult.success
                ? '已复制到剪贴板，可以粘贴分享'
                : (copyResult.message ?? '复制失败'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 导出为文件
    final ExportImportResult<String?> fileResult =
        await ExportFileUtils.exportText(
      content: result.data!,
      fileName: ExportFileUtils.buildFileName(
        name: identity.name,
        fallbackName: '身份',
        ext: _fileExt,
      ),
      ext: _fileExt,
      dialogTitle: '导出身份',
    );
    if (!mounted) return;
    if (!fileResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText(fileResult.message ?? '导出到文件失败')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: FitText(
          fileResult.data == null ? '已取消导出' : '已导出到：${fileResult.data}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 身份导出扩展名。
  static const String _fileExt = 'dnapersona';

  /// 从剪贴板或文件导入身份，回填到当前表单（需用户检查后保存）。
  Future<void> _importFromClipboard() async {
    final ImportSource? source = await showImportSourceDialog(
      context: context,
      title: '导入身份',
      description: '支持本应用导出的身份文件与直接的身份 JSON。',
    );
    if (source == null || !mounted) return;

    final String? content;
    if (source == ImportSource.clipboard) {
      final ExportImportResult<String> pasteResult =
          await IdentityExportImportService.pasteFromClipboard();
      if (!mounted) return;
      if (!pasteResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: FitText(pasteResult.message ?? '读取剪贴板失败')),
        );
        return;
      }
      content = pasteResult.data;
    } else {
      final ExportImportResult<String?> fileResult =
          await ExportFileUtils.importText(
        exts: const <String>[_fileExt, 'json'],
        dialogTitle: '选择身份文件',
      );
      if (!mounted) return;
      if (!fileResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: FitText(fileResult.message ?? '读取文件失败')),
        );
        return;
      }
      if (fileResult.data == null) return; // 用户取消
      content = fileResult.data;
    }

    if (content == null || content.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: FitText('没有可导入的内容')),
      );
      return;
    }

    final ExportImportResult<UserIdentity> importResult =
        IdentityExportImportService.importIdentity(content);
    if (!mounted) return;
    if (!importResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText(importResult.message ?? '导入失败')),
      );
      return;
    }
    final UserIdentity imported = importResult.data!;
    setState(() {
      _nameController.text = imported.name;
      _personaController.text = imported.persona;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: FitText('已从剪贴板导入身份，请检查后保存'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FitText(widget.identity == null ? '创建身份' : '编辑身份'),
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: const Icon(Icons.import_export),
            tooltip: '导出 / 导入',
            onSelected: (String value) {
              switch (value) {
                case 'copy':
                  _copyToClipboard();
                  break;
                case 'import':
                  _importFromClipboard();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'copy',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.ios_share),
                    SizedBox(width: 8),
                    FitText('导出身份'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'import',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.file_download_outlined),
                    SizedBox(width: 8),
                    FitText('导入身份'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      // 主操作放回右下 FAB（拇指可达）；顶栏不再放同一个动作（审计回归 R4）。
      floatingActionButton: AppEditorFab(
        onPressed: _save,
        icon: const Icon(Icons.check),
        label: const FitText('保存身份'),
      ),
      body: ListView(
        controller: _scrollController,
        padding: AppEditorLayout.bodyPadding(context),
        children: <Widget>[
          _section(
            icon: Icons.badge_outlined,
            title: '我的身份信息',
            description: '在对话中作为你的专属人设注入给 AI，让 TA 了解你是谁。',
            children: <Widget>[
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '身份名称 *',
                  hintText: '例如：旅行者、指挥官、学弟',
                  border: const OutlineInputBorder(),
                  errorText: _nameError,
                ),
                onChanged: (String value) {
                  if (_nameError != null && value.trim().isNotEmpty) {
                    setState(() => _nameError = null);
                  }
                },
              ),
              AppSpacing.hLg,
              AdaptiveTextField(
                controller: _personaController,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: '人设（我的身份设定，发送给 AI）*',
                  hintText: '描述你的性格、外貌、背景、说话口吻以及与 TA 的关系...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 一个无容器的字段分组（审计 3.3 / 4.2）：照 lib/widgets/setting_section.dart
  /// 的写法 —— 图标与标题用 onSurfaceVariant（primary 是交互色），
  /// 靠标题字号与 AppSpacing.xl 分节，不再整组套一张 Card。
  Widget _section({
    IconData? icon,
    required String title,
    String? description,
    required List<Widget> children,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, color: cs.onSurfaceVariant, size: AppSize.iconCard),
                AppSpacing.wSm,
              ],
              Expanded(
                child: FitText(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: AppWeight.medium,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (description != null) ...<Widget>[
            AppSpacing.hXs,
            FitText(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          AppSpacing.hSm,
          ...children,
        ],
      ),
    );
  }
}
