import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../models/ta.dart';
import '../models/dialogue_style.dart';
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

  Future<void> _save() async {
    final TA ta = TA(
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
    await widget.controller.upsertTa(ta);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ta == null ? '创建TA' : '编辑TA'),
        actions: <Widget>[
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
                      final TA current = TA(
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
                  TextField(
                    controller: _personaController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '设定',
                      hintText: '决定了TA的内在',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _introController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '介绍',
                      hintText: '仅对外展示',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _openingController,
                    maxLines: 3,
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
                children: <Widget>[
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
