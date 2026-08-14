import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

import '../models/ta.dart';
import '../models/dialogue_style.dart';
import '../services/image_storage.dart';
import '../utils/platform_capabilities.dart';
import '../widgets/adaptive_text_field.dart';
import 'ta_editor/image_slot.dart';
import 'package:dna/services/ta_export_import_service.dart';
import '../state/app_controller.dart';
import '../utils/id_utils.dart';
import '../utils/ui_feedback.dart';
import 'dialogue_style_page.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/seed_input_field.dart';

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
  late final TextEditingController _seedController;
  late final TextEditingController _authorNoteController;
  late final TextEditingController _authorIntervalController;

  late String _gender;
  late String _taId;
  Map<String, String> _images = <String, String>{};
  final Set<String> _obsoleteImageRefs = <String>{};
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
    _seedController =
        TextEditingController(text: ta?.voiceSeed?.toString() ?? '');
    _authorNoteController = TextEditingController(text: ta?.authorNote ?? '');
    _authorIntervalController =
        TextEditingController(text: ta?.authorNoteInterval.toString() ?? '0');
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
    _seedController.dispose();
    _authorNoteController.dispose();
    _authorIntervalController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String slot, CropAspectRatio ratio) async {
    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (picked == null) {
      return;
    }

    // 裁剪仅 IO 平台可用（image_cropper 无 Web 实现）；Web 上直接用原图。
    CroppedFile? cropped;
    if (!kIsWeb && !Platform.isWindows) {
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

    final XFile source = cropped == null ? picked : XFile(cropped.path);
    final Uint8List bytes = await source.readAsBytes();
    final String ext = path.extension(source.name);
    final String? oldRef = _images[slot];
    final String storedPath = await widget.controller.storeTaImageBytes(
      taId: _taId,
      slot: slot,
      bytes: bytes,
      ext: ext.isEmpty ? null : ext,
    );

    if (!mounted) {
      return;
    }
    // 旧图片引用在保存 TA 后被替换，先记录，待保存成功再清理磁盘文件
    if (oldRef != null && oldRef.isNotEmpty && oldRef != storedPath) {
      _obsoleteImageRefs.add(oldRef);
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

  int? _parseSeed() {
    final String raw = _seedController.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
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
      voiceSeed: _parseSeed(),
      authorNote: _authorNoteController.text.trim().isEmpty
          ? null
          : _authorNoteController.text.trim(),
      authorNoteInterval: int.tryParse(_authorIntervalController.text.trim()) ?? 0,
    );
  }

  Future<void> _save() async {
    final TA ta = _buildCurrentTA();
    await widget.controller.upsertTa(ta);
    // 保存成功后清理被替换掉的旧图片文件，避免磁盘/IndexedDB 堆积
    if (_obsoleteImageRefs.isNotEmpty) {
      for (final String ref in _obsoleteImageRefs) {
        await ImageStorage.instance.delete(ref);
      }
      _obsoleteImageRefs.clear();
    }
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
          title: const FitText('导出角色'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FitText('将角色数据导出为JSON格式，包含文字设定和图片。'),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const FitText('压缩图片'),
                subtitle: const FitText('减小导出文件大小（推荐）'),
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
              child: const FitText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const FitText('导出'),
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
      showSnack(
        context,
        '已复制到剪贴板，可以粘贴分享',
        behavior: SnackBarBehavior.floating,
      );
    } else {
      showSnack(context, '导出完成，但复制到剪贴板失败');
    }
  }

  Future<void> _showImportDialog() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const FitText('导入角色'),
        content: const FitText('将从剪贴板读取角色数据并导入。支持本应用导出格式与酒馆（SillyTavern）角色卡 JSON。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const FitText('从剪贴板导入'),
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

    // 检查ID冲突：永不覆盖，命中则自动改用新 ID 导入为新角色
    TA taToImport = importedTA;
    final existingTA = widget.controller.getTaById(importedTA.id);
    if (existingTA != null) {
      taToImport = TA(
        id: newId(),
        name: importedTA.name,
        gender: importedTA.gender,
        persona: importedTA.persona,
        intro: importedTA.intro,
        opening: importedTA.opening,
        tags: importedTA.tags,
        images: importedTA.images,
        dialogueStyle: importedTA.dialogueStyle,
        archived: importedTA.archived,
        originalLink: importedTA.originalLink,
        voiceSeed: importedTA.voiceSeed,
        authorNote: importedTA.authorNote,
        authorNoteInterval: importedTA.authorNoteInterval,
      );
      if (!mounted) return;
      showSnack(context, 'ID 与已有角色冲突，已自动创建为新角色');
    }

    if (!mounted) return;
    // 永不覆盖已有角色，故图片回落始终为空（图片从导入包内恢复）
    await _importWithImages(taToImport, {});
  }

  Future<void> _importWithImages(TA ta, Map<String, String> existingImages) async {
    showSnack(context, '正在导入图片...');

    final Map<String, String> newImages = {};

    // 从导出包中恢复图片（仅本应用格式内嵌图片；酒馆角色卡无此结构，跳过）
    final pasteResult = await TaExportImportService.pasteFromClipboard();
    if (pasteResult.success) {
      try {
        final decoded = jsonDecode(pasteResult.data!);
        if (decoded is Map<String, dynamic> &&
            (decoded.containsKey('character') || decoded.containsKey('exportType'))) {
          final package = ExportPackage.fromJson(decoded);

          for (final entry in package.character.images.entries) {
            final slot = entry.key;
            final imageInfo = entry.value;

            if (imageInfo.data != null && imageInfo.data!.isNotEmpty) {
              final saveResult =
                  await TaExportImportService.saveImageToStorage(
                imageInfo.data!,
                taId: ta.id,
                slot: slot,
              );
              if (saveResult.success) {
                newImages[slot] = saveResult.data!;
              }
            } else if (existingImages.containsKey(slot)) {
              newImages[slot] = existingImages[slot]!;
            }
          }
        }
      } catch (_) {
        // 非本应用格式（如酒馆角色卡）无内嵌图片，忽略
      }
    }

    // 更新TA并保存（originalLink 已在 importCharacter 阶段设置）
    final finalTA = ta.copyWith(images: newImages);
    await widget.controller.upsertTa(finalTA);

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
      _seedController.text = finalTA.voiceSeed?.toString() ?? '';
      _authorNoteController.text = finalTA.authorNote ?? '';
      _authorIntervalController.text = finalTA.authorNoteInterval.toString();
      _images = Map<String, String>.from(finalTA.images);
      _dialogueStyle = List<DialogueTurn>.from(finalTA.dialogueStyle);
    });

    showSnack(context, '导入成功');
  }

  // ========== 构建UI ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FitText(widget.ta == null ? '创建TA' : '编辑TA'),
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
                    FitText('导出角色'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.download_outlined),
                    SizedBox(width: 8),
                    FitText('导入角色'),
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
                  FitText('TA形象', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ImageSlot(
                    title: '1:1 形象',
                    ref: _images['square'],
                    onTap: () => _pickImage('square', const CropAspectRatio(ratioX: 1, ratioY: 1)),
                  ),
                  const SizedBox(height: 12),
                  ImageSlot(
                    title: '16:9 形象',
                    ref: _images['landscape'],
                    onTap: () => _pickImage('landscape', const CropAspectRatio(ratioX: 16, ratioY: 9)),
                  ),
                  const SizedBox(height: 12),
                  ImageSlot(
                    title: '9:16 形象',
                    ref: _images['portrait'],
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
                  FitText('人设栏目', style: Theme.of(context).textTheme.titleLarge),
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
                    label: const FitText('对话风格'),
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
                      DropdownMenuItem(value: '男', child: FitText('男')),
                      DropdownMenuItem(value: '女', child: FitText('女')),
                      DropdownMenuItem(value: '无性', child: FitText('无性')),
                      DropdownMenuItem(value: '其他', child: FitText('其他')),
                    ],
                    onChanged: (String? value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _gender = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  AdaptiveTextField(
                    controller: _personaController,
                    decoration: const InputDecoration(
                      labelText: '设定',
                      hintText: '决定了TA的内在',
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdaptiveTextField(
                    controller: _introController,
                    decoration: const InputDecoration(
                      labelText: '介绍',
                      hintText: '仅对外展示',
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdaptiveTextField(
                    controller: _openingController,
                    decoration: const InputDecoration(
                      labelText: '开场白（可选）',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    shape: const Border(),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8),
                    leading: const Icon(Icons.tune),
                    title: const FitText('高级选项'),
                    subtitle: const FitText('语音合成 Seed、作者注释与注入间隔'),
                    children: <Widget>[
                      const SizedBox(height: 12),
                      SeedInputField(
                        controller: _seedController,
                        label: '语音合成 Seed（可选）',
                        hint: '留空则用全局 seed',
                        enabled: PlatformCapabilities.ttsSupported,
                      ),
                      const SizedBox(height: 4),
                      FitText(
                        '该角色固定音色，未设置时使用全局语音合成 seed。',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      AdaptiveTextField(
                        controller: _authorNoteController,
                        decoration: const InputDecoration(
                          labelText: '作者注释（可选）',
                          hintText: '该角色始终希望强调的内容，按间隔深度注入对话。留空则不注入。',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _authorIntervalController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '注入间隔（每多少条历史消息注入一次）',
                          hintText: '0 表示禁用',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FitText(
                        '作者注释会随角色卡导出/导入。留空则该角色不注入作者注释。',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
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
                  FitText('标签', style: Theme.of(context).textTheme.titleLarge),
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
        label: const FitText('保存TA'),
      ),
    );
  }
}


