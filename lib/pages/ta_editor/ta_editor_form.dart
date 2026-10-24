import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../models/ta.dart';
import '../../models/dialogue_style.dart';
import '../../services/export_file_utils.dart';
import '../../services/image_pick_capability.dart';
import '../../services/image_storage.dart';
import '../../services/ta_service.dart';
import '../../utils/platform_capabilities.dart';
import '../../widgets/adaptive_text_field.dart';
import '../../widgets/tag_input.dart';
import 'image_slot.dart';
import 'package:dna/services/ta_export_import_service.dart';
import '../../utils/id_utils.dart';
import '../../utils/ui_feedback.dart';
import '../dialogue_style_page.dart';
import 'package:dna/island_app/widgets/card_crop_page.dart' show FreeImageCrop;
import 'package:dna/widgets/export_import/transport_source_dialog.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/seed_input_field.dart';
import '../../widgets/app_editor_frame.dart';

/// 角色卡表单的句柄：外壳用它取值、判断是否有未保存改动。
///
/// 只是**句柄**：字段状态仍在 [TaEditorForm] 自己的 State 里，外壳拿不到
/// 「怎么存」，只能 current() / isDirty。
class TaFormController extends ChangeNotifier {
  _TaEditorFormState? _state;
  String? _baseline;

  void _attach(_TaEditorFormState state) {
    _state = state;
    _baseline = jsonEncode(state._buildCurrentTA().toJson());
  }

  void _detach(_TaEditorFormState state) {
    if (identical(_state, state)) {
      _state = null;
      _baseline = null;
    }
  }

  /// 当前表单内容（外壳点保存时取）。
  TA current() {
    final _TaEditorFormState? state = _state;
    if (state == null) {
      throw StateError('表单尚未挂载：请把 formController 传给 TaEditorForm');
    }
    return state._buildCurrentTA();
  }

  /// 是否有未保存改动。
  bool get isDirty {
    final _TaEditorFormState? state = _state;
    if (state == null || _baseline == null) return false;
    return jsonEncode(state._buildCurrentTA().toJson()) != _baseline;
  }

  /// 用一份新数据回填表单（切换编辑对象）。基线一并重置，避免刚打开就显示「已修改」。
  void reset(TA ta) {
    final _TaEditorFormState? state = _state;
    if (state == null) return;
    state._applyTa(ta);
    _baseline = jsonEncode(state._buildCurrentTA().toJson());
  }

  /// 打开导出对话框（对话框的 UI 仍在表单里，外壳只负责触发）。
  Future<void> exportViaDialog() async => _state?._showExportDialog();

  /// 打开导入对话框。
  Future<void> importViaDialog() async => _state?._showImportDialog();

  /// 保存成功后清理被替换掉的旧图片文件。
  Future<void> afterSave() async => _state?._cleanupObsoleteImages();
}

/// 角色卡**表单**：只有字段与图片槽，没有顶栏 / 底栏 / 保存按钮。
///
/// 存本地还是发社区、按钮叫什么、要不要校验，全归外壳决定。
class TaEditorForm extends StatefulWidget {
  const TaEditorForm({
    super.key,
    this.ta,
    required this.formController,
    this.bgmSizeLimitUnlocked = false,
    required this.imagePicker,
  });

  /// 初始数据；为空表示新建。
  final TA? ta;

  /// 外壳持有的句柄。
  final TaFormController formController;

  /// 背景音乐大小上限是否已解锁（设置项，由外壳注入 —— 表单读不到设置）。
  final bool bgmSizeLimitUnlocked;

  /// 选图 / 裁剪能力，由外壳注入（表单自己不 new 选择器）。
  final ImagePickCapability imagePicker;

  @override
  State<TaEditorForm> createState() => _TaEditorFormState();
}

class _TaEditorFormState extends State<TaEditorForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _personaController;
  late final TextEditingController _introController;
  late final TextEditingController _openingController;

  /// 标签用 chips 编辑（与社区角色卡发布页、世界编辑器共用 TagInput）。
  late List<String> _tags;

  late final TextEditingController _seedController;
  late final TextEditingController _authorNoteController;
  late final TextEditingController _authorIntervalController;

  late String _gender;
  late String _taId;
  Map<String, String> _images = <String, String>{};
  final Set<String> _obsoleteImageRefs = <String>{};
  List<DialogueTurn> _dialogueStyle = <DialogueTurn>[];
  String? _musicPath;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _personaController = TextEditingController();
    _introController = TextEditingController();
    _openingController = TextEditingController();
    _seedController = TextEditingController();
    _authorNoteController = TextEditingController();
    _authorIntervalController = TextEditingController();
    _applyTa(widget.ta);
    widget.formController._attach(this);
  }

  /// 用一份数据回填表单（初始化 / 外壳调用 reset 切换编辑对象）。
  void _applyTa(TA? ta) {
    _taId = ta?.id ?? newId();
    _nameController.text = ta?.name ?? '';
    _personaController.text = ta?.persona ?? '';
    _introController.text = ta?.intro ?? '';
    _openingController.text = ta?.opening ?? '';
    _tags = List<String>.from(ta?.tags ?? const <String>[]);
    _seedController.text = ta?.voiceSeed?.toString() ?? '';
    _authorNoteController.text = ta?.authorNote ?? '';
    _authorIntervalController.text =
        ta?.authorNoteInterval.toString() ?? '0';
    _gender = ta?.gender ?? '无性';
    _images = Map<String, String>.from(ta?.images ?? <String, String>{});
    _dialogueStyle =
        List<DialogueTurn>.from(ta?.dialogueStyle ?? <DialogueTurn>[]);
    _musicPath = ta?.musicPath;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.formController._detach(this);
    _nameController.dispose();
    _personaController.dispose();
    _introController.dispose();
    _openingController.dispose();
    _seedController.dispose();
    _authorNoteController.dispose();
    _authorIntervalController.dispose();
    super.dispose();
  }

  /// 保存成功后清理被替换掉的旧图片文件，避免磁盘 / IndexedDB 堆积。
  Future<void> _cleanupObsoleteImages() async {
    if (_obsoleteImageRefs.isEmpty) return;
    for (final String ref in _obsoleteImageRefs) {
      await ImageStorage.instance.delete(ref);
    }
    _obsoleteImageRefs.clear();
  }

  Future<void> _pickImage(String slot, double aspect) async {
    final PickedImage? picked = await widget.imagePicker.pickAndCrop(
      aspect: FreeImageCrop.enabled ? null : aspect,
    );
    if (picked == null || picked.bytes.isEmpty) return;
    final String? oldRef = _images[slot];
    // 表单不碰本地库：图片一律落平台存储。
    final String storedPath = await ImageStorage.instance.saveBytes(
      taId: _taId,
      slot: slot,
      bytes: picked.bytes,
      ext: picked.extension.isEmpty ? null : picked.extension,
    );
    if (!mounted) return;
    if (oldRef != null && oldRef.isNotEmpty && oldRef != storedPath) {
      _obsoleteImageRefs.add(oldRef);
    }
    setState(() {
      _images = Map<String, String>.from(_images)..[slot] = storedPath;
    });
  }

  /// 在文件管理器中挑选背景音乐并拷贝到应用私有目录。
  ///
  /// 默认限制 10MB 以内（可在设置中解锁）。背景音乐不会随角色卡导出，
  /// 仅供本地聊天时循环播放。
  Future<void> _pickMusic() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['mp3', 'm4a', 'aac', 'ogg', 'wav'],
    );
    if (result == null || result.files.isEmpty) return;
    final String sourcePath = result.files.single.path ?? '';
    if (sourcePath.isEmpty) return;

    // 背景音乐只在本地有意义（不随角色卡导出），社区模式下这段 UI 也不会出现。
    final bool unlocked = widget.bgmSizeLimitUnlocked;
    final String? stored = await TaService().storeMusic(
      sourcePath: sourcePath,
      taId: _taId,
      oldMusicPath: _musicPath,
      sizeLimitUnlocked: unlocked,
    );
    if (stored == null) {
      if (mounted) {
        showSnack(
          context,
          unlocked
              ? '无法保存该背景音乐，请确认文件为支持的音频格式。'
              : '背景音乐大小不能超过 10MB，可在设置中解锁限制。',
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _musicPath = stored;
    });
  }

  /// 清除当前角色的背景音乐并删除本地文件。
  Future<void> _clearMusic() async {
    final String? old = _musicPath;
    setState(() {
      _musicPath = null;
    });
    await TaService().deleteMusic(old);
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
      tags: _tags,
      images: _images,
      dialogueStyle: _dialogueStyle,
      voiceSeed: _parseSeed(),
      authorNote: _authorNoteController.text.trim().isEmpty
          ? null
          : _authorNoteController.text.trim(),
      authorNoteInterval: int.tryParse(_authorIntervalController.text.trim()) ?? 0,
      musicPath: _musicPath,
    );
  }

  // ========== 导出导入功能 ==========

  Future<void> _showExportDialog() async {
    bool compressImages = true;

    // 询问导出目的地(剪贴板 / 文件),并保留原有的「压缩图片」选项。
    final ExportTarget? target = await showExportTargetDialog(
      context: context,
      title: '导出角色',
      description: '导出内容包含文字设定与图片。'
          '注：背景音乐仅保存在本机，不会随角色卡导出。',
      extraOptions: StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setSB) => CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const FitText('压缩图片'),
          subtitle: const FitText('减小导出文件大小（推荐）'),
          value: compressImages,
          onChanged: (bool? value) => setSB(() => compressImages = value ?? true),
        ),
      ),
    );

    if (target == null || !mounted) return;

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

    if (target == ExportTarget.clipboard) {
      // 复制到剪贴板(原有行为)
      final copyResult =
          await TaExportImportService.copyToClipboard(result.data!);
      if (!mounted) return;
      showSnack(
        context,
        copyResult.success ? '已复制到剪贴板，可以粘贴分享' : '导出完成，但复制到剪贴板失败',
        behavior: SnackBarBehavior.floating,
      );
      return;
    }

    // 导出为文件
    final fileResult = await ExportFileUtils.exportText(
      content: result.data!,
      fileName: ExportFileUtils.buildFileName(
        name: currentTA.name,
        fallbackName: '角色',
        ext: _fileExt,
      ),
      ext: _fileExt,
      dialogTitle: '导出角色卡',
    );
    if (!mounted) return;
    if (!fileResult.success) {
      showSnack(context, fileResult.message ?? '导出到文件失败');
      return;
    }
    showSnack(
      context,
      fileResult.data == null ? '已取消导出' : '已导出到：${fileResult.data}',
      behavior: SnackBarBehavior.floating,
    );
  }

  /// 角色卡导出扩展名。
  static const String _fileExt = 'dnata';

  Future<void> _showImportDialog() async {
    final ImportSource? source = await showImportSourceDialog(
      context: context,
      title: '导入角色',
      description: '支持本应用导出的角色卡，以及酒馆（SillyTavern）角色卡 JSON。',
    );

    if (source == null || !mounted) return;

    // 取得导入内容:剪贴板或文件
    final String? content;
    if (source == ImportSource.clipboard) {
      final pasteResult = await TaExportImportService.pasteFromClipboard();
      if (!mounted) return;
      if (!pasteResult.success) {
        showSnack(context, pasteResult.message ?? '读取剪贴板失败');
        return;
      }
      content = pasteResult.data;
    } else {
      final fileResult = await ExportFileUtils.importText(
        exts: const <String>[_fileExt, 'json'],
        dialogTitle: '选择角色卡文件',
      );
      if (!mounted) return;
      if (!fileResult.success) {
        showSnack(context, fileResult.message ?? '读取文件失败');
        return;
      }
      if (fileResult.data == null) return; // 用户取消
      content = fileResult.data;
    }

    if (content == null || content.isEmpty) {
      if (!mounted) return;
      showSnack(context, '没有可导入的内容');
      return;
    }

    // 解析导入数据
    final importResult = TaExportImportService.importCharacter(content);

    if (!importResult.success) {
      if (!mounted) return;
      showSnack(context, importResult.message ?? '导入失败');
      return;
    }

    final importedTA = importResult.data!.ta;

    // 检查ID冲突：永不覆盖，命中则自动改用新 ID 导入为新角色。
    // 社区模式没有本地库，不存在冲突，直接用它自己的 id。
    TA taToImport = importedTA;
    // 表单不写本地库，也就没有「id 冲突」这回事（外壳若要落库自己处理）。
    const Object? existingTA = null;
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
    await _importWithImages(taToImport, {}, content);
  }

  Future<void> _importWithImages(
    TA ta,
    Map<String, String> existingImages,
    String content,
  ) async {
    showSnack(context, '正在导入图片...');

    final Map<String, String> newImages = {};

    // 从导出包中恢复图片（仅本应用格式内嵌图片；酒馆角色卡无此结构，跳过）
    try {
      final decoded = jsonDecode(content);
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

    // 更新TA并保存（originalLink 已在 importCharacter 阶段设置）
    final finalTA = ta.copyWith(images: newImages);
    // 只回填当前表单；要不要落库由外壳在保存时决定。

    if (!mounted) return;

    // 更新当前页面状态
    setState(() {
      _taId = finalTA.id;
      _nameController.text = finalTA.name;
      _gender = finalTA.gender;
      _personaController.text = finalTA.persona;
      _introController.text = finalTA.intro;
      _openingController.text = finalTA.opening;
      _tags = List<String>.from(finalTA.tags);
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
    return ListView(
        padding: AppEditorLayout.bodyPadding(context),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('TA形象', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  FitText(
                    '建议上传全套 3 种比例立绘，分别用于头像、横版名片与全屏背景。',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: ImageSlot(
                          title: '1:1 头像',
                          subtitle: '聊天头像',
                          ref: _images['square'],
                          aspectRatio: 1.0,
                          onTap: () => _pickImage(
                            'square',
                            1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ImageSlot(
                          title: '16:9 背景',
                          subtitle: '横版名片',
                          ref: _images['landscape'],
                          aspectRatio: 16 / 9,
                          onTap: () => _pickImage(
                            'landscape',
                            16 / 9,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ImageSlot(
                          title: '9:16 立绘',
                          subtitle: '全屏背景',
                          ref: _images['portrait'],
                          aspectRatio: 9 / 16,
                          onTap: () => _pickImage(
                            'portrait',
                            9 / 16,
                          ),
                        ),
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
                children: <Widget>[
                  FitText('人设栏目', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '名字 *',
                      hintText: '例如：艾莲娜、卡特',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    decoration: const InputDecoration(
                      labelText: '性别',
                      border: OutlineInputBorder(),
                    ),
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
                    minLines: 4,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: '设定（角色人设，发送给 AI）*',
                      hintText: '描述 TA 的性格、身世背景、内在原则、核心能力与说话口吻等（作为核心系统提示词注入）',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _introController,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      labelText: '介绍（卡片简介，仅对外展示）',
                      hintText: '在角色列表和名片上对外展示的简短一句话介绍',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdaptiveTextField(
                    controller: _openingController,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '开场白（可选）',
                      hintText: '初次开启会话时 TA 发送的第一条打招呼消息',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: const FitText('对话风格（语气范例）'),
                    subtitle: FitText(
                      _dialogueStyle.isEmpty
                          ? '提供几句问答示例，教 AI 模仿特定的说话习惯'
                          : '已配置 ${_dialogueStyle.length} 组问答示例',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final TA current = _buildCurrentTA();
                      // 子页保存后会把改好的 TA pop 回来；社区模式没有本地库可回查，
                      // 所以优先用它，其次才回查本地库。
                      final TA? result = await Navigator.of(context).push<TA>(
                        MaterialPageRoute<TA>(
                          builder: (BuildContext context) => DialogueStylePage(
                            ta: current,
                            onSave: (TA updated) async {
                              setState(() {
                                _dialogueStyle =
                                    List<DialogueTurn>.from(updated.dialogueStyle);
                              });
                            },
                          ),
                        ),
                      );
                      if (!mounted) {
                        return;
                      }
                      final TA? updated = result;
                      setState(() {
                        _dialogueStyle = List<DialogueTurn>.from(
                          updated?.dialogueStyle ?? _dialogueStyle,
                        );
                      });
                    },
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
                      const SizedBox(height: 8),
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
                        minLines: 2,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: '作者注释（可选）',
                          hintText: '该角色始终希望强调的内容，按间隔深度注入对话。留空则不注入。',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _authorIntervalController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '注入间隔（每多少条历史消息注入一次）',
                          hintText: '0 表示禁用',
                          border: OutlineInputBorder(),
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
          // 背景音乐是纯本地功能（不随角色卡导出），存在本机，所有宿主都能用。
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('背景音乐', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  FitText(
                    '进入聊天时循环播放该角色的背景音乐。音乐仅保存在本机，'
                    '不会随角色卡导出/分享。默认上限 10MB（可在设置中解锁）。',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _musicPath == null
                            ? FitText('未设置背景音乐',
                                style: TextStyle(color: Theme.of(context).colorScheme.outline))
                            : FitText(
                                path.basename(_musicPath!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      IconButton(
                        tooltip: '选择背景音乐',
                        onPressed: _pickMusic,
                        icon: const Icon(Icons.music_note),
                      ),
                      if (_musicPath != null)
                        IconButton(
                          tooltip: '清除背景音乐',
                          onPressed: _clearMusic,
                          icon: const Icon(Icons.delete_outline),
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
                children: <Widget>[
                  FitText('标签', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TagInput(
                    tags: _tags,
                    hintText: '例如：治愈, 暖心, 励志（回车或逗号添加）',
                    onChanged: (List<String> next) => setState(() {
                      _tags = next;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
    );
  }
}


