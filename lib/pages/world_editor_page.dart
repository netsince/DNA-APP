// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models/world.dart';
import '../services/world_export_import_service.dart';
import '../state/app_controller.dart';
import '../utils/id_utils.dart';
import '../widgets/adaptive_text_field.dart';
import 'package:dna/widgets/fit_text.dart';

/// 世界编辑与创建页面。
///
/// 采用「渐进式分层设计」：
/// 1. 核心必填信息（世界名称、世界背景）置顶突出；
/// 2. 高级选项（简介、标签、违禁词）默认折叠；
/// 3. 子词条管理改为「卡片列表 + 独立弹窗编辑」，区分基础触发与高级规则。
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
  late List<WorldEntry> _entries;

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

  void _removeEntry(WorldEntry entry) {
    setState(() {
      _entries = _entries.where((WorldEntry item) => item.id != entry.id).toList();
      _entries = _entries
          .map((WorldEntry item) => _withoutRelationTarget(item, entry.id))
          .toList();
    });
  }

  World _buildCurrentWorld() {
    return World(
      id: _worldId,
      name: _nameController.text.trim(),
      summary: _summaryController.text.trim(),
      description: _descriptionController.text.trim(),
      tags: _parseTags(_tagsController.text),
      forbiddenWords: _parseForbiddenWords(_forbiddenWordsController.text),
      entries: _entries,
    );
  }

  Future<void> _save() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: FitText('请填写世界名称')),
      );
      return;
    }
    final World world = _buildCurrentWorld();
    await widget.controller.upsertWorld(world);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 复制到剪贴板
  Future<void> _copyToClipboard() async {
    final String worldName = _nameController.text.trim();
    if (worldName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: FitText('请先填写世界名称再复制。')),
      );
      return;
    }
    final ExportImportResult<String> result =
        WorldExportImportService.exportWorld(_buildCurrentWorld());
    if (!mounted) return;
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText(result.message ?? '导出失败')),
      );
      return;
    }
    final ExportImportResult<void> copyResult =
        await WorldExportImportService.copyToClipboard(result.data!);
    if (!mounted) return;
    if (copyResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: FitText('已复制到剪贴板，可以粘贴分享'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText(copyResult.message ?? '复制到剪贴板失败')),
      );
    }
  }

  /// 从剪贴板导入
  Future<void> _importFromClipboard() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const FitText('导入世界观'),
        content: const FitText('将从剪贴板读取世界观数据并导入。'),
        actions: <Widget>[
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

    final ExportImportResult<String> pasteResult =
        await WorldExportImportService.pasteFromClipboard();
    if (!mounted) return;
    if (!pasteResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText(pasteResult.message ?? '读取剪贴板失败')),
      );
      return;
    }

    final ExportImportResult<World> importResult =
        WorldExportImportService.importWorld(pasteResult.data!);
    if (!mounted) return;
    if (!importResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText(importResult.message ?? '导入失败')),
      );
      return;
    }

    World worldToImport = importResult.data!;
    final World? existing = widget.controller.getWorldById(worldToImport.id);
    if (existing != null) {
      worldToImport = worldToImport.copyWith(id: newId());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: FitText('ID 与已有世界冲突，已自动创建为新世界')),
      );
    }

    await widget.controller.upsertWorld(worldToImport);
    if (!mounted) return;

    setState(() {
      _worldId = worldToImport.id;
      _nameController.text = worldToImport.name;
      _summaryController.text = worldToImport.summary;
      _descriptionController.text = worldToImport.description;
      _tagsController.text = worldToImport.tags.join(', ');
      _forbiddenWordsController.text = worldToImport.forbiddenWords.join(', ');
      _entries = List<WorldEntry>.from(worldToImport.entries);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: FitText('导入成功')),
    );
  }

  /// 弹出词条创建/编辑弹窗
  void _openEntryEditor({WorldEntry? entryToEdit, int? editIndex}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        return _WorldEntryModal(
          initialEntry: entryToEdit,
          availableEntries: _entries,
          onSave: (WorldEntry savedEntry) {
            setState(() {
              if (editIndex != null && editIndex >= 0 && editIndex < _entries.length) {
                _entries[editIndex] = savedEntry;
              } else {
                _entries.add(savedEntry);
              }
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isNew = widget.world == null;

    return Scaffold(
      appBar: AppBar(
        title: FitText(isNew ? '创建世界' : '编辑世界'),
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
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'copy',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.content_copy_outlined),
                    SizedBox(width: 8),
                    FitText('复制到剪贴板'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
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
            icon: const Icon(Icons.check),
            tooltip: '保存世界',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: <Widget>[
          // ===== 1. 世界核心信息卡片 =====
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.public, color: theme.colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('世界核心设定', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '设定该世界的名称与通用规则，对话时将作为基础背景注入。',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: '世界名称 *',
                      hintText: '例如：赛博朋克2077、提瓦特大陆、暗夜修道院',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.badge_outlined),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdaptiveTextField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: '世界背景 / 通用法则',
                      hintText: '描述该世界的时代背景、地理风貌、核心力量法则或全局设定...',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.auto_stories_outlined),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 高级与展示选项（折叠）
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: FitText(
                        '展示备注与违禁词（选填）',
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                      ),
                      leading: Icon(Icons.tune, color: theme.colorScheme.primary, size: 18),
                      childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
                      children: <Widget>[
                        TextField(
                          controller: _summaryController,
                          decoration: InputDecoration(
                            labelText: '简介 / 备注',
                            hintText: '用于在世界列表中展示的简短一句话介绍',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _tagsController,
                          decoration: InputDecoration(
                            labelText: '分类标签（逗号分隔）',
                            hintText: '例如：科幻, 废土, 魔法',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        AdaptiveTextField(
                          controller: _forbiddenWordsController,
                          decoration: InputDecoration(
                            labelText: '禁止输出词语',
                            hintText: '强制要求 AI 绝不提及的词汇，用逗号或换行分隔',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 2. 动态词条库 (World Entries) =====
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.library_books_outlined, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  FitText('动态词条库', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: FitText(
                      '${_entries.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openEntryEditor(),
                icon: const Icon(Icons.add, size: 18),
                label: const FitText('添加词条'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FitText(
            '当对话中提到词条名称或别名时，会自动向 AI 注入对应设定。',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 12),

          if (_entries.isEmpty)
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                  style: BorderStyle.solid,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                child: Column(
                  children: <Widget>[
                    Icon(Icons.menu_book_outlined, size: 40, color: theme.colorScheme.outline.withOpacity(0.5)),
                    const SizedBox(height: 8),
                    FitText('暂无词条', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.outline)),
                    const SizedBox(height: 4),
                    FitText(
                      '点击下方按钮添加地点、物品、人物或专有名词设定',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => _openEntryEditor(),
                      icon: const Icon(Icons.add),
                      label: const FitText('创建第一个词条'),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _entries.length,
              separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final WorldEntry entry = _entries[index];
                return _WorldEntryCard(
                  entry: entry,
                  relationTargetName: entry.relation != null ? _entryNameById(entry.relation!.targetId) : null,
                  onEdit: () => _openEntryEditor(entryToEdit: entry, editIndex: index),
                  onDelete: () => _removeEntry(entry),
                );
              },
            ),

          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.check),
        label: const FitText('保存世界'),
      ),
    );
  }
}

/// 词条卡片
class _WorldEntryCard extends StatelessWidget {
  const _WorldEntryCard({
    required this.entry,
    this.relationTargetName,
    required this.onEdit,
    required this.onDelete,
  });

  final WorldEntry entry;
  final String? relationTargetName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isPerson = entry.type == WorldEntryType.person;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    isPerson ? Icons.person_outline : Icons.bookmark_outline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FitText(
                      entry.name.isEmpty ? '未命名词条' : entry.name,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: onEdit,
                    tooltip: '编辑',
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: onDelete,
                    tooltip: '删除',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (entry.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                FitText(
                  entry.description,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  _BadgeChip(label: isPerson ? '人物' : '名词'),
                  if (isPerson && entry.gender != null)
                    _BadgeChip(
                      label: entry.gender == WorldPersonGender.male
                          ? '男'
                          : entry.gender == WorldPersonGender.female
                              ? '女'
                              : '其他',
                    ),
                  if (isPerson && (entry.age ?? '').isNotEmpty)
                    _BadgeChip(label: '${entry.age}岁'),
                  if (entry.keys.isNotEmpty)
                    _BadgeChip(
                      label: '${entry.keys.length}个别名',
                      color: theme.colorScheme.secondaryContainer,
                      textColor: theme.colorScheme.onSecondaryContainer,
                    ),
                  if ((entry.keyRegex ?? '').isNotEmpty)
                    _BadgeChip(label: '正则匹配', color: theme.colorScheme.tertiaryContainer),
                  if (entry.recursive)
                    const _BadgeChip(label: '递归扫描'),
                  if (entry.cooldownRounds > 0)
                    _BadgeChip(label: '冷却${entry.cooldownRounds}轮'),
                  if (entry.delayRounds > 0)
                    _BadgeChip(label: '延迟${entry.delayRounds}轮'),
                  if (entry.decorator == 'activate')
                    const _BadgeChip(label: '强制激活'),
                  if (entry.decorator == 'dont_activate')
                    const _BadgeChip(label: '禁止激活'),
                ],
              ),
              if (entry.relation != null && relationTargetName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.link, size: 14, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: FitText(
                          '关联: $relationTargetName · ${entry.relation!.content}',
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, this.color, this.textColor});

  final String label;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: FitText(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 10,
          color: textColor ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 词条编辑弹窗（底部抽屉）
class _WorldEntryModal extends StatefulWidget {
  const _WorldEntryModal({
    this.initialEntry,
    required this.availableEntries,
    required this.onSave,
  });

  final WorldEntry? initialEntry;
  final List<WorldEntry> availableEntries;
  final ValueChanged<WorldEntry> onSave;

  @override
  State<_WorldEntryModal> createState() => _WorldEntryModalState();
}

class _WorldEntryModalState extends State<_WorldEntryModal> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _keysController;
  late final TextEditingController _regexController;
  late final TextEditingController _ageController;
  late final TextEditingController _relationController;
  late final TextEditingController _cooldownController;
  late final TextEditingController _delayController;

  late WorldEntryType _type;
  late WorldPersonGender _gender;
  late WorldPersonStatus _status;
  String? _relationTargetId;
  late bool _caseSensitive;
  late bool _matchWholeWords;
  late bool _recursive;
  late String _decorator;

  @override
  void initState() {
    super.initState();
    final WorldEntry? e = widget.initialEntry;
    _nameController = TextEditingController(text: e?.name ?? '');
    _descriptionController = TextEditingController(text: e?.description ?? '');
    _keysController = TextEditingController(text: (e?.keys ?? <String>[]).join(', '));
    _regexController = TextEditingController(text: e?.keyRegex ?? '');
    _ageController = TextEditingController(text: e?.age ?? '');
    _relationController = TextEditingController(text: e?.relation?.content ?? '');
    _cooldownController = TextEditingController(
      text: (e?.cooldownRounds ?? 0) > 0 ? '${e!.cooldownRounds}' : '',
    );
    _delayController = TextEditingController(
      text: (e?.delayRounds ?? 0) > 0 ? '${e!.delayRounds}' : '',
    );

    _type = e?.type ?? WorldEntryType.noun;
    _gender = e?.gender ?? WorldPersonGender.other;
    _status = e?.status ?? WorldPersonStatus.normal;
    _relationTargetId = e?.relation?.targetId;
    _caseSensitive = e?.caseSensitive ?? false;
    _matchWholeWords = e?.matchWholeWords ?? false;
    _recursive = e?.recursive ?? false;
    _decorator = e?.decorator ?? 'none';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _keysController.dispose();
    _regexController.dispose();
    _ageController.dispose();
    _relationController.dispose();
    _cooldownController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  List<String> _parseKeys(String raw) {
    return raw
        .split(RegExp(r'[,，]'))
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList();
  }

  void _submit() {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: FitText('请填写词条名称')),
      );
      return;
    }

    final String relContent = _relationController.text.trim();
    WorldEntryRelation? relation;
    if (_type == WorldEntryType.person && _relationTargetId != null && relContent.isNotEmpty) {
      relation = WorldEntryRelation(targetId: _relationTargetId!, content: relContent);
    }

    final WorldEntry entry = WorldEntry(
      id: widget.initialEntry?.id ?? newId(),
      name: name,
      description: _descriptionController.text.trim(),
      type: _type,
      gender: _type == WorldEntryType.person ? _gender : null,
      age: _type == WorldEntryType.person ? _ageController.text.trim() : null,
      status: _type == WorldEntryType.person ? _status : null,
      relation: relation,
      keys: _parseKeys(_keysController.text),
      keyRegex: _regexController.text.trim().isEmpty ? null : _regexController.text.trim(),
      caseSensitive: _caseSensitive,
      matchWholeWords: _matchWholeWords,
      recursive: _recursive,
      cooldownRounds: (int.tryParse(_cooldownController.text.trim()) ?? 0).clamp(0, 100),
      delayRounds: (int.tryParse(_delayController.text.trim()) ?? 0).clamp(0, 100),
      decorator: _decorator == 'none' ? null : _decorator,
    );

    widget.onSave(entry);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isEditing = widget.initialEntry != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 顶部把手与标题
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              FitText(
                isEditing ? '编辑词条' : '新建词条',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 词条类型选择
                  SegmentedButton<WorldEntryType>(
                    segments: const <ButtonSegment<WorldEntryType>>[
                      ButtonSegment<WorldEntryType>(
                        value: WorldEntryType.noun,
                        label: FitText('名词 / 地点 / 物品'),
                        icon: Icon(Icons.bookmark_outline),
                      ),
                      ButtonSegment<WorldEntryType>(
                        value: WorldEntryType.person,
                        label: FitText('人物 / 角色'),
                        icon: Icon(Icons.person_outline),
                      ),
                    ],
                    selected: <WorldEntryType>{_type},
                    onSelectionChanged: (Set<WorldEntryType> val) {
                      setState(() => _type = val.first);
                    },
                  ),
                  const SizedBox(height: 12),

                  // 词条名称
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '词条名称（主触发词）*',
                      hintText: '例如：圣剑·誓约、帝国第一军校、艾莲娜',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 词条描述
                  AdaptiveTextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: '设定描述 / 内容 *',
                      hintText: '输入该词条的背景、功能、来历或人物特征...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.notes),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 附加别名
                  TextField(
                    controller: _keysController,
                    decoration: const InputDecoration(
                      labelText: '附加触发词 / 别名（逗号分隔）',
                      hintText: '例如：黄金圣剑, 圣剑（提到这些词也会激活本条目）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),

                  // 人物专属字段
                  if (_type == WorldEntryType.person) ...<Widget>[
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: DropdownButtonFormField<WorldPersonGender>(
                            value: _gender,
                            items: const <DropdownMenuItem<WorldPersonGender>>[
                              DropdownMenuItem(value: WorldPersonGender.male, child: FitText('男')),
                              DropdownMenuItem(value: WorldPersonGender.female, child: FitText('女')),
                              DropdownMenuItem(value: WorldPersonGender.other, child: FitText('其他')),
                            ],
                            onChanged: (v) => setState(() => _gender = v ?? WorldPersonGender.other),
                            decoration: const InputDecoration(labelText: '性别', border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _ageController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '年龄', hintText: '例如：24', border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<WorldPersonStatus>(
                            value: _status,
                            items: const <DropdownMenuItem<WorldPersonStatus>>[
                              DropdownMenuItem(value: WorldPersonStatus.normal, child: FitText('正常')),
                              DropdownMenuItem(value: WorldPersonStatus.dead, child: FitText('死亡')),
                            ],
                            onChanged: (v) => setState(() => _status = v ?? WorldPersonStatus.normal),
                            decoration: const InputDecoration(labelText: '状态', border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _relationTargetId,
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(value: null, child: FitText('无人物关联')),
                        ...widget.availableEntries
                            .where((WorldEntry e) => e.id != widget.initialEntry?.id)
                            .map(
                              (WorldEntry e) => DropdownMenuItem<String>(
                                value: e.id,
                                child: FitText(e.name.isEmpty ? '未命名词条' : e.name),
                              ),
                            ),
                      ],
                      onChanged: (String? v) => setState(() => _relationTargetId = v),
                      decoration: const InputDecoration(labelText: '关联其他词条', border: OutlineInputBorder(), isDense: true),
                    ),
                    if (_relationTargetId != null) ...<Widget>[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _relationController,
                        decoration: const InputDecoration(
                          labelText: '关联关系描述',
                          hintText: '例如：导师、宿敌、挚友',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 8),

                  // 进阶触发规则（折叠）
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: FitText(
                        '高级触发规则（进阶选项）',
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                      ),
                      leading: Icon(Icons.settings_suggest_outlined, color: theme.colorScheme.primary, size: 18),
                      childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
                      children: <Widget>[
                        TextField(
                          controller: _regexController,
                          decoration: const InputDecoration(
                            labelText: '正则匹配规则（可选）',
                            hintText: '例如：\\b雨夜\\b',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            FilterChip(
                              label: const FitText('大小写敏感'),
                              selected: _caseSensitive,
                              onSelected: (v) => setState(() => _caseSensitive = v),
                            ),
                            FilterChip(
                              label: const FitText('全词匹配'),
                              selected: _matchWholeWords,
                              onSelected: (v) => setState(() => _matchWholeWords = v),
                            ),
                            FilterChip(
                              label: const FitText('递归联动扫描'),
                              selected: _recursive,
                              onSelected: (v) => setState(() => _recursive = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                controller: _cooldownController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '冷却轮数',
                                  hintText: '触发后静默轮数',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _delayController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '延迟轮数',
                                  hintText: '提及后延迟触发',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _decorator,
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(value: 'none', child: FitText('正常激活')),
                            DropdownMenuItem<String>(value: 'activate', child: FitText('强制常驻激活（跳过冷却）')),
                            DropdownMenuItem<String>(value: 'dont_activate', child: FitText('禁止激活')),
                          ],
                          onChanged: (String? v) => setState(() => _decorator = v ?? 'none'),
                          decoration: const InputDecoration(
                            labelText: '激活装饰符',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.check),
                      label: FitText(isEditing ? '保存修改' : '添加词条'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
