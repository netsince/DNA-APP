import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/ta.dart';
import '../models/dialogue_style.dart';
import 'package:dna/services/ta_db_service.dart';
import 'package:dna/services/ta_export_import_service.dart';
import '../state/app_controller.dart';
import '../utils/id_utils.dart';
import '../utils/ui_feedback.dart';
import 'dialogue_style_page.dart';

class TaEditorPage extends StatefulWidget {
  const TaEditorPage({super.key, required this.controller, this.ta});

  final AppController controller;
  final TA? ta;

  @override
  State<TaEditorPage> createState() => _TaEditorPageState();
}

class _TaEditorPageState extends State<TaEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _personaController;
  late final TextEditingController _introController;
  late final TextEditingController _openingController;
  late final TextEditingController _tagsController;

  late String _gender;
  late String _taId;
  Map<String, String> _images = <String, String>{};
  List<DialogueTurn> _dialogueStyle = <DialogueTurn>[];

  @override
  void initState() {
    super.initState();
    final TA? ta = widget.ta;
    _taId = ta?.id ?? newId();
    _nameController = TextEditingController(text: ta?.name ?? '');
    _personaController = TextEditingController(text: ta?.persona ?? '');
    _introController = TextEditingController(text: ta?.intro ?? '');
    _openingController = TextEditingController(text: ta?.opening ?? '');
    _tagsController = TextEditingController(text: (ta?.tags ?? <String>[]).join(', '));
    _gender = ta?.gender ?? '无性';
    _images = Map<String, String>.from(ta?.images ?? <String, String>{});
    _dialogueStyle = List<DialogueTurn>.from(ta?.dialogueStyle ?? <DialogueTurn>[]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _personaController.dispose();
    _introController.dispose();
    _openingController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String slot, CropAspectRatio ratio) async {
    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (picked == null) {
      return;
    }

    CroppedFile? cropped;
    if (!Platform.isWindows) {
      try {
        cropped = await ImageCropper().cropImage(
          sourcePath: picked.path,
          aspectRatio: ratio,
          compressQuality: 95,
          uiSettings: <PlatformUiSettings>[
            AndroidUiSettings(toolbarTitle: '裁剪图片'),
            IOSUiSettings(title: '裁剪图片'),
          ],
        );
      } on MissingPluginException {
        cropped = null;
      } on PlatformException {
        cropped = null;
      } catch (_) {
        cropped = null;
      }
    }

    if (cropped == null) {
      if (!mounted) {
        return;
      }
      showSnack(context, '裁剪失败，请重试。');
    }

    final String storedPath = await widget.controller.storeTaImage(
      taId: _taId,
      slot: slot,
      sourcePath: cropped?.path ?? picked.path,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _images = Map<String, String>.from(_images)..[slot] = storedPath;
    });
  }

  List<String> _parseTags(String raw) {
    return raw
        .split(',')
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList();
  }

  TA _buildCurrentTA() {
    return TA(
      id: _taId,
      name: _nameController.text.trim(),
      gender: _gender,
      persona: _personaController.text.trim(),
      intro: _introController.text.trim(),
      opening: _openingController.text.trim(),
      tags: _parseTags(_tagsController.text),
      images: _images,
      dialogueStyle: _dialogueStyle,
    );
  }

  Future<void> _save() async {
    final TA ta = _buildCurrentTA();
    await widget.controller.upsertTa(ta);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  // ========== 导出导入功能 ==========

  Future<void> _showExportDialog() async {
    bool compressImages = true;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('导出角色'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('将角色数据导出为JSON格式，包含文字设定和图片。'),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('压缩图片'),
                subtitle: const Text('减小导出文件大小（推荐）'),
                value: compressImages,
                onChanged: (value) {
                  setState(() => compressImages = value ?? true);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('导出'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    showSnack(context, '正在导出...');

    final currentTA = _buildCurrentTA();
    final result = await TaExportImportService.exportCharacter(
      currentTA,
      compressImages: compressImages,
    );

    if (!mounted) return;

    if (!result.success) {
      showSnack(context, result.message ?? '导出失败');
      return;
    }

    // 复制到剪贴板
    final copyResult = await TaExportImportService.copyToClipboard(result.data!);

    if (!mounted) return;

    if (copyResult.success) {
      showSnack(context, '已复制到剪贴板，可以粘贴分享');
    } else {
      showSnack(context, '导出完成，但复制到剪贴板失败');
    }
  }

  Future<void> _showImportDialog() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入角色'),
        content: const Text('将从剪贴板读取角色数据并导入。请确保剪贴板中包含有效的导出数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('从剪贴板导入'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 读取剪贴板
    final pasteResult = await TaExportImportService.pasteFromClipboard();

    if (!pasteResult.success) {
      if (!mounted) return;
      showSnack(context, pasteResult.message ?? '读取剪贴板失败');
      return;
    }

    // 解析导入数据
    final importResult = TaExportImportService.importCharacter(pasteResult.data!);

    if (!importResult.success) {
      if (!mounted) return;
      showSnack(context, importResult.message ?? '导入失败');
      return;
    }

    final importedTA = importResult.data!.ta;

    // 检查ID冲突
    final existingTA = widget.controller.getTaById(importedTA.id);

    if (!mounted) return;

    if (existingTA != null) {
      // ID冲突，询问用户
      final action = await _showConflictDialog(existingTA.name);

      if (action == null || !mounted) return;

      if (action == _ConflictAction.cancel) {
        return;
      } else if (action == _ConflictAction.overwrite) {
        // 保留图片（如果需要）
        await _importWithImages(importedTA, existingTA.images);
      } else if (action == _ConflictAction.createNew) {
        // 创建新角色 - 重新构建TA以使用新ID
        final newTA = TA(
          id: newId(),
          name: importedTA.name,
          gender: importedTA.gender,
          persona: importedTA.persona,
          intro: importedTA.intro,
          opening: importedTA.opening,
          tags: importedTA.tags,
          images: {},
          dialogueStyle: importedTA.dialogueStyle,
        );
        await _importWithImages(newTA, {});
      }
    } else {
      // 无冲突，直接导入
      await _importWithImages(importedTA, {});
    }
  }

  Future<void> _importWithImages(TA ta, Map<String, String> existingImages) async {
    showSnack(context, '正在导入图片...');

    // 获取TA存储目录
    final docDir = await getApplicationDocumentsDirectory();
    final taDir = Directory(path.join(docDir.path, 'tas'));
    if (!await taDir.exists()) {
      await taDir.create(recursive: true);
    }

    final Map<String, String> newImages = {};

    // Extract original link from import data
    String? originalLink;

    // 从ExportedCharacter中恢复图片
    // 需要重新解析JSON获取图片数据
    final pasteResult = await TaExportImportService.pasteFromClipboard();
    if (pasteResult.success) {
      final decoded = jsonDecode(pasteResult.data!);
      final package = ExportPackage.fromJson(decoded);
      originalLink = package.originalLink;

      for (final entry in package.character.images.entries) {
        final slot = entry.key;
        final imageInfo = entry.value;

        if (imageInfo.data != null && imageInfo.data!.isNotEmpty) {
          // 保存Base64图片
          final ext = _getExtensionFromMimeType(imageInfo.data!);
          final fileName = '${ta.id}_$slot$ext';
          final targetPath = path.join(taDir.path, fileName);

          final saveResult = await TaExportImportService.saveBase64Image(
            imageInfo.data!,
            targetPath,
          );

          if (saveResult.success) {
            newImages[slot] = targetPath;
          }
        } else if (existingImages.containsKey(slot)) {
          // 使用现有图片
          newImages[slot] = existingImages[slot]!;
        }
      }
    }

    // 更新TA并保存
    final finalTA = ta.copyWith(images: newImages);
    await widget.controller.upsertTa(finalTA);

    // Save original link if present (disguised as _lk in export)
    if (originalLink != null && originalLink.isNotEmpty) {
      final taDbService = TaDbService();
      await taDbService.setOriginalLink(finalTA.id, originalLink);
    }

    if (!mounted) return;

    // 更新当前页面状态
    setState(() {
      _taId = finalTA.id;
      _nameController.text = finalTA.name;
      _gender = finalTA.gender;
      _personaController.text = finalTA.persona;
      _introController.text = finalTA.intro;
      _openingController.text = finalTA.opening;
      _tagsController.text = finalTA.tags.join(', ');
      _images = Map<String, String>.from(finalTA.images);
      _dialogueStyle = List<DialogueTurn>.from(finalTA.dialogueStyle);
    });

    showSnack(context, '导入成功');
  }

  Future<_ConflictAction?> _showConflictDialog(String existingName) async {
    return showDialog<_ConflictAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('角色已存在'),
        content: Text('ID与现有角色 "$existingName" 冲突，请选择操作：'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ConflictAction.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ConflictAction.createNew),
            child: const Text('创建为新角色'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_ConflictAction.overwrite),
            child: const Text('覆盖现有角色'),
          ),
        ],
      ),
    );
  }

  String _getExtensionFromMimeType(String dataUri) {
    if (dataUri.contains('image/png')) return '.png';
    if (dataUri.contains('image/webp')) return '.webp';
    if (dataUri.contains('image/gif')) return '.gif';
    return '.jpg';
  }

  // ========== 构建UI ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ta == null ? '创建TA' : '编辑TA'),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'export':
                  _showExportDialog();
                  break;
                case 'import':
                  _showImportDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.upload_outlined),
                    SizedBox(width: 8),
                    Text('导出角色'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.download_outlined),
                    SizedBox(width: 8),
                    Text('导入角色'),
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
                  Text('TA形象', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  _ImageSlot(
                    title: '1:1 形象',
                    path: _images['square'],
                    onTap: () => _pickImage('square', const CropAspectRatio(ratioX: 1, ratioY: 1)),
                  ),
                  const SizedBox(height: 12),
                  _ImageSlot(
                    title: '16:9 形象',
                    path: _images['landscape'],
                    onTap: () => _pickImage('landscape', const CropAspectRatio(ratioX: 16, ratioY: 9)),
                  ),
                  const SizedBox(height: 12),
                  _ImageSlot(
                    title: '9:16 形象',
                    path: _images['portrait'],
                    onTap: () => _pickImage('portrait', const CropAspectRatio(ratioX: 9, ratioY: 16)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('人设栏目', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final TA current = _buildCurrentTA();
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) => DialogueStylePage(
                            controller: widget.controller,
                            ta: current,
                          ),
                        ),
                      );
                      if (!mounted) {
                        return;
                      }
                      final TA? updated = widget.controller.getTaById(_taId);
                      setState(() {
                        _dialogueStyle = List<DialogueTurn>.from(updated?.dialogueStyle ?? _dialogueStyle);
                      });
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('对话风格'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: '名字'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    decoration: const InputDecoration(labelText: '性别'),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: '男', child: Text('男')),
                      DropdownMenuItem(value: '女', child: Text('女')),
                      DropdownMenuItem(value: '无性', child: Text('无性')),
                      DropdownMenuItem(value: '其他', child: Text('其他')),
                    ],
                    onChanged: (String? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _gender = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _AdaptiveTextField(
                    controller: _personaController,
                    decoration: const InputDecoration(
                      labelText: '设定',
                      hintText: '决定了TA的内在',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AdaptiveTextField(
                    controller: _introController,
                    decoration: const InputDecoration(
                      labelText: '介绍',
                      hintText: '仅对外展示',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AdaptiveTextField(
                    controller: _openingController,
                    decoration: const InputDecoration(
                      labelText: '开场白（可选）',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>
[
                  Text('标签', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: '标签（逗号分隔）',
                      hintText: '例如：治愈, 暖心, 励志',
                    ),
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
        label: const Text('保存TA'),
      ),
    );
  }
}

class _ImageSlot extends StatelessWidget {
  const _ImageSlot({required this.title, required this.path, required this.onTap});

  final String title;
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(title)),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.upload_outlined),
          label: const Text('上传'),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 72,
          height: 72,
          child: path == null || path!.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image_outlined),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(path!), fit: BoxFit.cover),
                ),
        ),
      ],
    );
  }
}

enum _ConflictAction {
  cancel,
  overwrite,
  createNew,
}

class _AdaptiveTextField extends StatefulWidget {
  const _AdaptiveTextField({
    required this.controller,
    this.decoration,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;

  @override
  State<_AdaptiveTextField> createState() => _AdaptiveTextFieldState();
}

class _AdaptiveTextFieldState extends State<_AdaptiveTextField> {
  late int _lineCount;

  @override
  void initState() {
    super.initState();
    _lineCount = _calculateLineCount(widget.controller.text);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final int newLineCount = _calculateLineCount(widget.controller.text);
    if (newLineCount != _lineCount) {
      setState(() {
        _lineCount = newLineCount;
      });
    }
  }

  int _calculateLineCount(String text) {
    if (text.isEmpty) return 1;
    final int count = text.split('\n').length;
    return count < 1 ? 1 : count;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      minLines: _lineCount,
      maxLines: _lineCount,
      decoration: widget.decoration,
    );
  }
}
