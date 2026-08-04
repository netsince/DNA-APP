import 'package:flutter/material.dart';

import '../models/user_identity.dart';
import '../services/identity_export_import_service.dart';
import '../state/app_controller.dart';
import '../utils/id_utils.dart';
import '../widgets/adaptive_text_field.dart';
import 'package:dna/widgets/fit_text.dart';

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
  late final TextEditingController _introController;
  late String _identityId;

  @override
  void initState() {
    super.initState();
    final UserIdentity? identity = widget.identity;
    _identityId = identity?.id ?? newId();
    _nameController = TextEditingController(text: identity?.name ?? '');
    _personaController = TextEditingController(text: identity?.persona ?? '');
    _introController = TextEditingController(text: identity?.intro ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _personaController.dispose();
    _introController.dispose();
    super.dispose();
  }

  UserIdentity _buildCurrentIdentity() {
    return UserIdentity(
      id: _identityId,
      name: _nameController.text.trim(),
      persona: _personaController.text.trim(),
      intro: _introController.text.trim(),
    );
  }

  Future<void> _save() async {
    final UserIdentity identity = _buildCurrentIdentity();
    await widget.controller.upsertIdentity(identity);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  /// 将当前编辑中的身份复制到剪贴板，便于分享或跨设备粘贴。
  Future<void> _copyToClipboard() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: FitText('请先填写身份名称再复制。')),
      );
      return;
    }
    final ExportImportResult<String> result =
        IdentityExportImportService.exportIdentity(_buildCurrentIdentity());
    if (!mounted) return;
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText(result.message ?? '导出失败')),
      );
      return;
    }
    final ExportImportResult<void> copyResult =
        await IdentityExportImportService.copyToClipboard(result.data!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: FitText(copyResult.success ? '已复制到剪贴板，可以粘贴分享' : (copyResult.message ?? '复制失败')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 从剪贴板导入身份，回填到当前表单（需用户检查后保存）。
  Future<void> _importFromClipboard() async {
    final ExportImportResult<String> pasteResult =
        await IdentityExportImportService.pasteFromClipboard();
    if (!mounted) return;
    if (!pasteResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText(pasteResult.message ?? '读取剪贴板失败')),
      );
      return;
    }
    final ExportImportResult<UserIdentity> importResult =
        IdentityExportImportService.importIdentity(pasteResult.data!);
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
      _introController.text = imported.intro;
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
                    Icon(Icons.copy_outlined),
                    SizedBox(width: 8),
                    FitText('复制到剪贴板'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'import',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.content_paste_outlined),
                    SizedBox(width: 8),
                    FitText('从剪贴板导入'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            tooltip: '保存',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('身份信息', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: '身份名称'),
                  ),
                  const SizedBox(height: 12),
                  AdaptiveTextField(
                    controller: _personaController,
                    decoration: const InputDecoration(
                      labelText: '人设',
                      hintText: '描述你的身份、性格、说话方式等',
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdaptiveTextField(
                    controller: _introController,
                    decoration: const InputDecoration(labelText: '介绍'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save_outlined),
        label: const FitText('保存身份'),
      ),
    );
  }
}
