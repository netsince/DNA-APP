// ignore_for_file: deprecated_member_use
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
  late final TextEditingController _entryNameController;
  late final TextEditingController _entryDescriptionController;
  late final TextEditingController _entryAgeController;
  late final TextEditingController _entryRelationController;

  late String _worldId;
  late List<WorldEntry> _entries;
  WorldEntryType _entryType = WorldEntryType.noun;
  WorldPersonGender _entryGender = WorldPersonGender.other;
  WorldPersonStatus _entryStatus = WorldPersonStatus.normal;
  String? _relationTargetId;

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
    _entries = List<WorldEntry>.from(world?.entries ?? <WorldEntry>[]);
    _entryNameController = TextEditingController();
    _entryDescriptionController = TextEditingController();
    _entryAgeController = TextEditingController();
    _entryRelationController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _summaryController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _forbiddenWordsController.dispose();
    _entryNameController.dispose();
    _entryDescriptionController.dispose();
    _entryAgeController.dispose();
    _entryRelationController.dispose();
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

  String _typeLabel(WorldEntryType type) {
    switch (type) {
      case WorldEntryType.noun:
        return '名词';
      case WorldEntryType.person:
        return '人物';
    }
  }

  String _genderLabel(WorldPersonGender gender) {
    switch (gender) {
      case WorldPersonGender.male:
        return '男';
      case WorldPersonGender.female:
        return '女';
      case WorldPersonGender.other:
        return '其他';
    }
  }

  String _statusLabel(WorldPersonStatus status) {
    switch (status) {
      case WorldPersonStatus.normal:
        return '正常';
      case WorldPersonStatus.dead:
        return '死亡';
    }
  }

  String _entryNameById(String id) {
    for (final WorldEntry entry in _entries) {
      if (entry.id == id) {
        return entry.name.isEmpty ? '未命名词条' : entry.name;
      }
    }
    return '未知词条';
  }

  WorldEntry _withoutRelationTarget(WorldEntry entry, String targetId) {
    if (entry.relation?.targetId != targetId) {
      return entry;
    }
    return WorldEntry(
      id: entry.id,
      name: entry.name,
      description: entry.description,
      type: entry.type,
      gender: entry.gender,
      age: entry.age,
      status: entry.status,
      relation: null,
    );
  }

  void _addEntry() {
    final String name = _entryNameController.text.trim();
    final String description = _entryDescriptionController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写词条名称。')),
      );
      return;
    }

    final String relationText = _entryRelationController.text.trim();
    if (_entryType == WorldEntryType.person) {
      final bool hasTarget = _relationTargetId != null && _relationTargetId!.isNotEmpty;
      final bool hasText = relationText.isNotEmpty;
      if (hasTarget != hasText) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('关联需要同时选择条目并填写内容。')),
        );
        return;
      }
    }

    final WorldEntryRelation? relation = _entryType == WorldEntryType.person &&
            _relationTargetId != null &&
            relationText.isNotEmpty
        ? WorldEntryRelation(targetId: _relationTargetId!, content: relationText)
        : null;

    final WorldEntry entry = WorldEntry(
      id: newId(),
      name: name,
      description: description,
      type: _entryType,
      gender: _entryType == WorldEntryType.person ? _entryGender : null,
      age: _entryType == WorldEntryType.person ? _entryAgeController.text.trim() : null,
      status: _entryType == WorldEntryType.person ? _entryStatus : null,
      relation: relation,
    );

    setState(() {
      _entries = <WorldEntry>[..._entries, entry];
      _entryNameController.clear();
      _entryDescriptionController.clear();
      _entryAgeController.clear();
      _entryRelationController.clear();
      _relationTargetId = null;
      _entryType = WorldEntryType.noun;
      _entryGender = WorldPersonGender.other;
      _entryStatus = WorldPersonStatus.normal;
    });
  }

  void _removeEntry(WorldEntry entry) {
    setState(() {
      _entries = _entries.where((WorldEntry item) => item.id != entry.id).toList();
      _entries = _entries
          .map((WorldEntry item) => _withoutRelationTarget(item, entry.id))
          .toList();
      if (_relationTargetId == entry.id) {
        _relationTargetId = null;
      }
    });
  }

  Future<void> _save() async {
    final World world = World(
      id: _worldId,
      name: _nameController.text.trim(),
      summary: _summaryController.text.trim(),
      description: _descriptionController.text.trim(),
      tags: _parseTags(_tagsController.text),
      forbiddenWords: _parseForbiddenWords(_forbiddenWordsController.text),
      entries: _entries,
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
                  _AdaptiveTextField(
                    controller: _summaryController,
                    decoration: const InputDecoration(labelText: '简介'),
                  ),
                  const SizedBox(height: 12),
                  _AdaptiveTextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: '世界背景'),
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
                  _AdaptiveTextField(
                    controller: _forbiddenWordsController,
                    decoration: const InputDecoration(
                      labelText: '禁止输出词语',
                      hintText: '多个词用逗号或换行分隔，例如：桃花树, 林黛玉',
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
                  Text('世界观子词条', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _entryNameController,
                    decoration: const InputDecoration(labelText: '词条名称'),
                  ),
                  const SizedBox(height: 12),
                  _AdaptiveTextField(
                    controller: _entryDescriptionController,
                    decoration: const InputDecoration(labelText: '描述'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<WorldEntryType>(
                    value: _entryType,
                    items: const <DropdownMenuItem<WorldEntryType>>[
                      DropdownMenuItem(
                        value: WorldEntryType.noun,
                        child: Text('名词'),
                      ),
                      DropdownMenuItem(
                        value: WorldEntryType.person,
                        child: Text('人物'),
                      ),
                    ],
                    onChanged: (WorldEntryType? value) {
                      setState(() {
                        _entryType = value ?? WorldEntryType.noun;
                        if (_entryType == WorldEntryType.noun) {
                          _relationTargetId = null;
                          _entryRelationController.clear();
                          _entryAgeController.clear();
                        }
                      });
                    },
                    decoration: const InputDecoration(labelText: '类型'),
                  ),
                  if (_entryType == WorldEntryType.person) ...<Widget>[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<WorldPersonGender>(
                      value: _entryGender,
                      items: const <DropdownMenuItem<WorldPersonGender>>[
                        DropdownMenuItem(
                          value: WorldPersonGender.male,
                          child: Text('男'),
                        ),
                        DropdownMenuItem(
                          value: WorldPersonGender.female,
                          child: Text('女'),
                        ),
                        DropdownMenuItem(
                          value: WorldPersonGender.other,
                          child: Text('其他'),
                        ),
                      ],
                      onChanged: (WorldPersonGender? value) {
                        setState(() {
                          _entryGender = value ?? WorldPersonGender.other;
                        });
                      },
                      decoration: const InputDecoration(labelText: '性别'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _entryAgeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '年龄'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<WorldPersonStatus>(
                      value: _entryStatus,
                      items: const <DropdownMenuItem<WorldPersonStatus>>[
                        DropdownMenuItem(
                          value: WorldPersonStatus.normal,
                          child: Text('正常'),
                        ),
                        DropdownMenuItem(
                          value: WorldPersonStatus.dead,
                          child: Text('死亡'),
                        ),
                      ],
                      onChanged: (WorldPersonStatus? value) {
                        setState(() {
                          _entryStatus = value ?? WorldPersonStatus.normal;
                        });
                      },
                      decoration: const InputDecoration(labelText: '状态'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _relationTargetId,
                      items: _entries
                          .map(
                            (WorldEntry entry) => DropdownMenuItem<String>(
                              value: entry.id,
                              child: Text(entry.name.isEmpty ? '未命名词条' : entry.name),
                            ),
                          )
                          .toList(),
                      onChanged: _entries.isEmpty
                          ? null
                          : (String? value) {
                              setState(() {
                                _relationTargetId = value;
                              });
                            },
                      decoration: const InputDecoration(labelText: '关联条目'),
                    ),
                    const SizedBox(height: 12),
                    _AdaptiveTextField(
                      controller: _entryRelationController,
                      decoration: const InputDecoration(labelText: '关联内容'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _addEntry,
                    icon: const Icon(Icons.add),
                    label: const Text('保存词条'),
                  ),
                  const SizedBox(height: 16),
                  if (_entries.isEmpty)
                    const Text('暂无子词条')
                  else
                    Column(
                      children: _entries
                          .map(
                            (WorldEntry entry) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                entry.name.isEmpty ? '未命名词条' : entry.name,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  if (entry.description.isNotEmpty)
                                    Text(entry.description),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: <Widget>[
                                      Chip(label: Text(_typeLabel(entry.type))),
                                      if (entry.type == WorldEntryType.person &&
                                          entry.gender != null)
                                        Chip(label: Text(_genderLabel(entry.gender!))),
                                      if (entry.type == WorldEntryType.person &&
                                          (entry.age ?? '').isNotEmpty)
                                        Chip(label: Text('年龄 ${entry.age}')),
                                      if (entry.type == WorldEntryType.person &&
                                          entry.status != null)
                                        Chip(label: Text(_statusLabel(entry.status!))),
                                    ],
                                  ),
                                  if (entry.relation != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '关联：${_entryNameById(entry.relation!.targetId)} · ${entry.relation!.content}',
                                      ),
                                    ),
                                ],
                              ),
                              trailing: IconButton(
                                onPressed: () => _removeEntry(entry),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: '删除',
                              ),
                            ),
                          )
                          .toList(),
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
