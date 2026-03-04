import 'package:flutter/material.dart';

import '../models/world.dart';
import '../state/app_controller.dart';
import '../utils/id_utils.dart';

class WorldEditorPage extends StatefulWidget {
  const WorldEditorPage({super.key, required this.controller, this.world});

  final AppController controller;
  final World? world;

  @override
  State<WorldEditorPage> createState() => _WorldEditorPageState();
}

class _WorldEditorPageState extends State<WorldEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _summaryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagsController;
  late final TextEditingController _forbiddenWordsController;

  late String _worldId;

  @override
  void initState() {
    super.initState();
    final World? world = widget.world;
    _worldId = world?.id ?? newId();
    _nameController = TextEditingController(text: world?.name ?? '');
    _summaryController = TextEditingController(text: world?.summary ?? '');
    _descriptionController = TextEditingController(text: world?.description ?? '');
    _tagsController = TextEditingController(text: (world?.tags ?? <String>[]).join(', '));
    _forbiddenWordsController = TextEditingController(
      text: (world?.forbiddenWords ?? <String>[]).join(', '),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _summaryController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _forbiddenWordsController.dispose();
    super.dispose();
  }

  List<String> _parseTags(String raw) {
    return raw
        .split(',')
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList();
  }

  List<String> _parseForbiddenWords(String raw) {
    return raw
        .split(RegExp(r'[,，\n]'))
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _save() async {
    final World world = World(
      id: _worldId,
      name: _nameController.text.trim(),
      summary: _summaryController.text.trim(),
      description: _descriptionController.text.trim(),
      tags: _parseTags(_tagsController.text),
      forbiddenWords: _parseForbiddenWords(_forbiddenWordsController.text),
    );
    await widget.controller.upsertWorld(world);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.world == null ? '创建世界' : '编辑世界'),
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
                  Text('世界背景信息', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: '世界名称'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _summaryController,
                    decoration: const InputDecoration(labelText: '简介'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: '世界背景'),
                    maxLines: 6,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: '标签（逗号分隔）',
                      hintText: '例如：赛博朋克, 魔法, 都市',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _forbiddenWordsController,
                    decoration: const InputDecoration(
                      labelText: '禁止输出词语',
                      hintText: '多个词用逗号或换行分隔，例如：桃花树, 林黛玉',
                    ),
                    maxLines: 3,
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
        label: const Text('保存世界'),
      ),
    );
  }
}
