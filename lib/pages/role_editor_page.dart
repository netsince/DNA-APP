import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../models/role.dart';
import '../models/dialogue_style.dart';
import '../state/app_controller.dart';
import 'dialogue_style_page.dart';

class RoleEditorPage extends StatefulWidget {
  const RoleEditorPage({super.key, required this.controller, this.role});

  final AppController controller;
  final Role? role;

  @override
  State<RoleEditorPage> createState() => _RoleEditorPageState();
}

class _RoleEditorPageState extends State<RoleEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _personaController;
  late final TextEditingController _introController;
  late final TextEditingController _openingController;
  late final TextEditingController _tagsController;

  late String _gender;
  late String _roleId;
  Map<String, String> _images = <String, String>{};
  List<DialogueTurn> _dialogueStyle = <DialogueTurn>[];

  @override
  void initState() {
    super.initState();
    final Role? role = widget.role;
    _roleId = role?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    _nameController = TextEditingController(text: role?.name ?? '');
    _personaController = TextEditingController(text: role?.persona ?? '');
    _introController = TextEditingController(text: role?.intro ?? '');
    _openingController = TextEditingController(text: role?.opening ?? '');
    _tagsController = TextEditingController(text: (role?.tags ?? <String>[]).join(', '));
    _gender = role?.gender ?? '无性';
    _images = Map<String, String>.from(role?.images ?? <String, String>{});
    _dialogueStyle = List<DialogueTurn>.from(role?.dialogueStyle ?? <DialogueTurn>[]);
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
      }
    }

    if (cropped == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前平台不支持裁剪，已直接使用原图。')),
      );
    }

    final String storedPath = await widget.controller.storeRoleImage(
      roleId: _roleId,
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
    final Role role = Role(
      id: _roleId,
      name: _nameController.text.trim(),
      gender: _gender,
      persona: _personaController.text.trim(),
      intro: _introController.text.trim(),
      opening: _openingController.text.trim(),
      tags: _parseTags(_tagsController.text),
      images: _images,
      dialogueStyle: _dialogueStyle,
    );
    await widget.controller.upsertRole(role);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.role == null ? '创建角色' : '编辑角色'),
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
                  Text('角色形象', style: Theme.of(context).textTheme.titleLarge),
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
                      final Role current = Role(
                        id: _roleId,
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
                            role: current,
                          ),
                        ),
                      );
                      if (!mounted) {
                        return;
                      }
                      final Role? updated = widget.controller.getRoleById(_roleId);
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
                      hintText: '决定了角色的内在',
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
        label: const Text('保存角色'),
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
