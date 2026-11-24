import 'dart:convert';
import '../../models/prompt_strategy.dart';
import '../settings/widgets/strategy_override_editor.dart';

import 'package:material_ui/material_ui.dart';

import 'package:dna/theme/tokens.dart';

import '../../models/world.dart';
import '../../utils/id_utils.dart';
import '../../widgets/adaptive_text_field.dart';
import '../../widgets/app_editor_frame.dart';
import '../../widgets/fit_text.dart';
import '../../widgets/form_dirty_baseline.dart';
import '../../widgets/setting_section.dart';
import '../../widgets/form_draft.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/tag_input.dart';

/// 世界观表单的句柄：外壳用它取值、回填、判断是否有未保存改动。
///
/// 它只是**句柄**，不持有字段状态 —— 状态仍在 [WorldEditorForm] 自己的 State 里。
/// 表单内部那一大堆 TextEditingController 的生命周期不外泄，外壳也只能
/// current() / reset()，碰不到「怎么存」。
class WorldFormController extends ChangeNotifier {
  _WorldEditorFormState? _state;

  void _attach(_WorldEditorFormState state) => _state = state;

  void _detach(_WorldEditorFormState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  /// 当前表单内容（外壳点保存时取）。
  World current() {
    final _WorldEditorFormState? state = _state;
    if (state == null) {
      throw StateError('表单尚未挂载：请把 formController 传给 WorldEditorForm');
    }
    return state._buildCurrentWorld();
  }

  /// 是否有未保存改动。
  bool get isDirty => _state?._isDirty ?? false;

  /// 用一份新数据回填表单（导入、切换编辑对象）。
  void reset(World world) => _state?._applyWorld(world);
}

/// 世界观**表单**：只有字段与词条编辑，没有顶栏 / 底栏 / 保存按钮。
///
/// 外壳（本体、社区发布、以后的其它宿主）各自持有 [WorldFormController]，
/// 通过 `current()` 取值、`reset()` 回填。存本地还是发社区、按钮叫什么、
/// 要不要校验，全归外壳决定 —— 表单不再知道这些。
///
/// 布局沿用原来的「渐进式分层设计」：
/// 1. 核心必填信息（世界名称、世界背景）置顶突出；
/// 2. 高级选项（简介、标签、违禁词）默认折叠；
/// 3. 子词条管理为「卡片列表 + 独立弹窗编辑」，区分基础触发与高级规则。
class WorldEditorForm extends StatefulWidget {
  const WorldEditorForm({
    super.key,
    this.world,
    required this.formController,
    this.tagSuggestions = const <String>[],
    this.nameError,
    this.onNameChanged,
  });

  /// 初始数据；为空表示新建。
  final World? world;

  /// 外壳持有的句柄。
  final WorldFormController formController;

  /// 标签候选（热门标签），由外壳注入 —— 表单自己不拉社区接口。
  final List<String> tagSuggestions;

  /// 「世界名称」的字段级错误（由外壳校验后注入）。
  ///
  /// 表单本身不判断必填：哪个字段必填、必填到什么程度是宿主决定的事
  /// （发布要求名称，本地保存也要求，但社区编辑可能另有一套）。
  final String? nameError;

  /// 名称被编辑时通知外壳 —— 外壳据此清掉上一次的校验错误。
  final VoidCallback? onNameChanged;

  @override
  State<WorldEditorForm> createState() => _WorldEditorFormState();
}

class _WorldEditorFormState extends State<WorldEditorForm> {
  late TextEditingController _nameController;
  late TextEditingController _summaryController;
  late TextEditingController _descriptionController;
  late TextEditingController _forbiddenWordsController;

  /// 标签用 chips 编辑（与角色卡编辑器、社区发布页共用 TagInput）。
  late List<String> _tags;

  late String _worldId;
  late List<WorldEntry> _entries;

  /// 该世界的「叙事策略」覆盖；null 表示全部继承全局。
  StrategyDetails? _strategyOverride;

  /// 初始快照：用来回答「有没有未保存的改动」。
  final FormDirtyBaseline _dirty = FormDirtyBaseline();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _summaryController = TextEditingController();
    _descriptionController = TextEditingController();
    _forbiddenWordsController = TextEditingController();
    _applyWorld(widget.world);
    widget.formController._attach(this);
  }

  /// 用一份数据回填表单：初始化、导入、切换编辑对象都走这里。
  void _applyWorld(World? world) {
    // id 可能是空串（手写 JSON / 第三方转换），空就生成一个新的。
    final String incomingId = world?.id ?? '';
    _worldId = incomingId.isEmpty ? newId() : incomingId;
    _nameController.text = world?.name ?? '';
    _summaryController.text = world?.summary ?? '';
    _descriptionController.text = world?.description ?? '';
    _tags = List<String>.from(world?.tags ?? const <String>[]);
    _forbiddenWordsController.text =
        (world?.forbiddenWords ?? <String>[]).join(', ');
    _entries = List<WorldEntry>.from(world?.entries ?? <WorldEntry>[]);
    _strategyOverride = world?.strategyOverride;
    _dirty.capture(jsonEncode(_buildCurrentWorld().toJson()));
    if (mounted) {
      setState(() {});
    }
  }

  /// 是否有未保存改动（外壳用来做「返回时确认」）。
  bool get _isDirty =>
      _dirty.hasChanged(jsonEncode(_buildCurrentWorld().toJson()));

  @override
  void dispose() {
    widget.formController._detach(this);
    _nameController.dispose();
    _summaryController.dispose();
    _descriptionController.dispose();
    _forbiddenWordsController.dispose();
    super.dispose();
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
      tags: _tags,
      forbiddenWords: _parseForbiddenWords(_forbiddenWordsController.text),
      entries: _entries,
      strategyOverride: _strategyOverride,
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

    return ListView(
        padding: AppEditorLayout.bodyPadding(context),
        children: <Widget>[
          // ===== 1. 世界核心信息 =====
          // 分组头改用共享 SettingSection：它与设置页是同一套「图标 + 标题 +
          // 说明 + 内边距」语序。这里传 padding/margin 为零 —— 编辑器已有自己的
          // bodyPadding 与组间距，再叠一层就会多出留白。
          SettingSection(
            icon: Icons.public,
            title: '世界核心设定',
            description: '设定该世界的名称与通用规则，对话时将作为基础背景注入。',
            collapsible: false,
            padding: EdgeInsets.zero,
            margin: EdgeInsets.zero,
            children: <Widget>[
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => widget.onNameChanged?.call(),
                    decoration: InputDecoration(
                      labelText: '世界名称 *',
                      hintText: '例如：赛博朋克2077、提瓦特大陆、暗夜修道院',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.badge_outlined),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      // 字段级错误：错误跟着字段走，用户知道该改哪个框（审计 3.5）。
                      errorText: widget.nameError,
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
                  const SizedBox(height: 12),
                  // 标签**不再埋在折叠项里**：埋着就没人填，社区筛选条也就永远是空的。
                  FitText('分类标签', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  TagInput(
                    tags: _tags,
                    suggestions: widget.tagSuggestions,
                    hintText: '例如：科幻, 废土, 魔法（回车或逗号添加）',
                    onChanged: (List<String> next) => setState(() => _tags = next),
                  ),
                ],
          ),
          AppSpacing.hXl,

          // ===== 2. 动态词条库 (World Entries) =====
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.library_books_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: AppSize.iconCard,
                  ),
                  const SizedBox(width: 8),
                  FitText(
                    '动态词条库',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: AppWeight.medium,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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
                        fontWeight: AppWeight.medium,
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
                  color: theme.colorScheme.outlineVariant.withValues(alpha: AppAlpha.a40),
                  style: BorderStyle.solid,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                child: Column(
                  children: <Widget>[
                    Icon(Icons.menu_book_outlined, size: 40, color: theme.colorScheme.outline.withValues(alpha: AppAlpha.half)),
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

          const SizedBox(height: 24),

          // ===== 3. 叙事策略 =====
          // 放在最后一屏：它是进阶项，不该挤占「核心信息 → 词条库」的主流程。
          // 任何一项停在「未设置」就继续继承全局，不会因为没填而变成关闭。
          // 无容器分组：拆掉外面那张描边 Card，标题样式与其它分组一致
          // （titleSmall + onSurfaceVariant，审计 3.3 / 4.2）。
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: Icon(
              Icons.auto_stories_outlined,
              color: theme.colorScheme.onSurfaceVariant,
              size: AppSize.iconCard,
            ),
            title: FitText(
              '叙事策略',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: AppWeight.medium,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            subtitle: FitText(
              '结构、节奏、揭示、冲突、环境、配角；不设即继承全局',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            childrenPadding: const EdgeInsets.only(top: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StrategyOverrideEditor(
                scope: StrategyScope.world,
                value: _strategyOverride,
                onChanged: (StrategyDetails? v) {
                  setState(() => _strategyOverride = v);
                },
              ),
            ],
          ),
        ],
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
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: AppAlpha.a35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: AppAlpha.a40)),
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
                  const SizedBox(width: 4),
                  Expanded(
                    child: FitText(
                      entry.name.isEmpty ? '未命名词条' : entry.name,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: AppWeight.medium),
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
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.link, size: 14, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: FitText(
                          '关联: $relationTargetName · ${entry.relation!.content}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: FitText(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
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
  /// 所有文本 / 单选字段都走草稿（控制器与错误落点归 [FormDraft] 管）。
  late final FormDraft _draft;
  final ScrollController _scrollController = ScrollController();

  /// 下拉选项：草稿里存字符串，枚举在 [_submit] / 回填处转换。
  static const List<FormOption> _genderOptions = <FormOption>[
    (value: 'male', label: '男'),
    (value: 'female', label: '女'),
    (value: 'other', label: '其他'),
  ];
  static const List<FormOption> _statusOptions = <FormOption>[
    (value: 'normal', label: '正常'),
    (value: 'dead', label: '死亡'),
  ];
  static const List<FormOption> _decoratorOptions = <FormOption>[
    (value: 'none', label: '正常激活'),
    (value: 'activate', label: '强制常驻激活（跳过冷却）'),
    (value: 'dont_activate', label: '禁止激活'),
  ];

  late WorldEntryType _type;

  /// 三个 FilterChip 的开关：不是「文本 / 实体选择」形态，保持原样。
  late bool _caseSensitive;
  late bool _matchWholeWords;
  late bool _recursive;

  @override
  void initState() {
    super.initState();
    final WorldEntry? e = widget.initialEntry;
    _draft = FormDraft(
      textFields: const <String>[
        'name',
        'description',
        'keys',
        'regex',
        'age',
        'relationContent',
        'cooldown',
        'delay',
        'order',
      ],
    );
    _draft.controller('name').text = e?.name ?? '';
    _draft.controller('description').text = e?.description ?? '';
    _draft.controller('keys').text = (e?.keys ?? <String>[]).join(', ');
    _draft.controller('regex').text = e?.keyRegex ?? '';
    _draft.controller('age').text = e?.age ?? '';
    _draft.controller('relationContent').text = e?.relation?.content ?? '';
    _draft.controller('cooldown').text =
        (e?.cooldownRounds ?? 0) > 0 ? '${e!.cooldownRounds}' : '';
    _draft.controller('delay').text =
        (e?.delayRounds ?? 0) > 0 ? '${e!.delayRounds}' : '';
    // 排序：0 是默认值，显示成空更干净。
    _draft.controller('order').text = (e?.order ?? 0) > 0 ? '${e!.order}' : '';

    _draft.select('gender', (e?.gender ?? WorldPersonGender.other).name);
    _draft.select('status', (e?.status ?? WorldPersonStatus.normal).name);
    _draft.select('relationTarget', e?.relation?.targetId);
    _draft.select('decorator', e?.decorator ?? 'none');

    _type = e?.type ?? WorldEntryType.noun;
    _caseSensitive = e?.caseSensitive ?? false;
    _matchWholeWords = e?.matchWholeWords ?? false;
    _recursive = e?.recursive ?? false;
  }

  @override
  void dispose() {
    _draft.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 把视口带回第一个出错的字段（名称在最上面）。
  void _revealFirstError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  WorldPersonGender _genderValue() {
    final String? raw = _draft.selection('gender');
    for (final WorldPersonGender gender in WorldPersonGender.values) {
      if (gender.name == raw) return gender;
    }
    return WorldPersonGender.other;
  }

  WorldPersonStatus _statusValue() {
    final String? raw = _draft.selection('status');
    for (final WorldPersonStatus status in WorldPersonStatus.values) {
      if (status.name == raw) return status;
    }
    return WorldPersonStatus.normal;
  }

  List<String> _parseKeys(String raw) {
    return raw
        .split(RegExp(r'[,，]'))
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList();
  }

  void _submit() {
    // 名称必填：错误落到字段上（文案与原来的 snackbar 完全一致）。
    final bool ok = _draft.validateRequired(<(String, String)>[
      ('name', '请填写词条名称'),
    ]);
    if (!ok) {
      setState(() {});
      _revealFirstError();
      return;
    }

    final String? relationTarget = _draft.selection('relationTarget');
    final String relContent = _draft.text('relationContent');
    WorldEntryRelation? relation;
    if (_type == WorldEntryType.person &&
        relationTarget != null &&
        relContent.isNotEmpty) {
      relation = WorldEntryRelation(targetId: relationTarget, content: relContent);
    }
    final String decorator = _draft.selection('decorator') ?? 'none';

    final WorldEntry entry = WorldEntry(
      id: widget.initialEntry?.id ?? newId(),
      name: _draft.text('name'),
      description: _draft.text('description'),
      type: _type,
      gender: _type == WorldEntryType.person ? _genderValue() : null,
      age: _type == WorldEntryType.person ? _draft.text('age') : null,
      status: _type == WorldEntryType.person ? _statusValue() : null,
      relation: relation,
      keys: _parseKeys(_draft.rawText('keys')),
      keyRegex: _draft.text('regex').isEmpty ? null : _draft.text('regex'),
      caseSensitive: _caseSensitive,
      matchWholeWords: _matchWholeWords,
      recursive: _recursive,
      // 排序：预算裁剪时按 order 升序注入，越小越靠前。
      order: (int.tryParse(_draft.text('order')) ?? 0).clamp(0, 9999),
      cooldownRounds: (int.tryParse(_draft.text('cooldown')) ?? 0).clamp(0, 100),
      delayRounds: (int.tryParse(_draft.text('delay')) ?? 0).clamp(0, 100),
      decorator: decorator == 'none' ? null : decorator,
    );

    widget.onSave(entry);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isEditing = widget.initialEntry != null;
    // 关联候选：排除自己（与旧下拉的过滤一致）。
    final List<FormOption> relationOptions = <FormOption>[
      for (final WorldEntry entry in widget.availableEntries)
        if (entry.id != widget.initialEntry?.id)
          (
            value: entry.id,
            label: entry.name.isEmpty ? '未命名词条' : entry.name,
          ),
    ];

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
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: AppWeight.medium),
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
              controller: _scrollController,
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

                  FormSection(
                    title: '词条内容',
                    children: <Widget>[
                      FormTextField(
                        draft: _draft,
                        id: 'name',
                        label: '词条名称（主触发词）*',
                        hint: '例如：圣剑·誓约、帝国第一军校、艾莲娜',
                        // 原实现是描边输入框 + 标题图标，按原样补回观感。
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.title),
                        // 名称必填：错误落在字段上，输入即清（原来是一句 snackbar）。
                        onChanged: (_) => setState(() {}),
                      ),
                      AppSpacing.hMd,
                      // 例外：原实现用 AdaptiveTextField（按内容行数自适应高度），
                      // 共享层的 FormTextField 只能固定行数，硬套会改掉输入体验，
                      // 所以这里保留原构件；控制器仍取自草稿，取值逻辑不变。
                      AdaptiveTextField(
                        controller: _draft.controller('description'),
                        decoration: const InputDecoration(
                          labelText: '设定描述 / 内容 *',
                          hintText: '输入该词条的背景、功能、来历或人物特征...',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.notes),
                        ),
                      ),
                      AppSpacing.hMd,
                      FormTextField(
                        draft: _draft,
                        id: 'keys',
                        label: '附加触发词 / 别名（逗号分隔）',
                        hint: '例如：黄金圣剑, 圣剑（提到这些词也会激活本条目）',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ],
                  ),

                  // 人物专属字段：type == person 才出现（5 个条件字段）
                  if (_type == WorldEntryType.person)
                    FormSection(
                      title: '人物设定',
                      children: <Widget>[
                        // 原实现把「性别 / 年龄 / 状态」排成一行三列，
                        // 这里保持同一排布（窄屏靠 Expanded 等分，不换行）。
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: FormEntitySelect(
                                draft: _draft,
                                id: 'gender',
                                label: '性别',
                                options: _genderOptions,
                                border: const OutlineInputBorder(),
                                isDense: true,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FormTextField(
                                draft: _draft,
                                id: 'age',
                                label: '年龄',
                                hint: '例如：24',
                                keyboardType: TextInputType.number,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FormEntitySelect(
                                draft: _draft,
                                id: 'status',
                                label: '状态',
                                options: _statusOptions,
                                border: const OutlineInputBorder(),
                                isDense: true,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        AppSpacing.hMd,
                        FormEntitySelect(
                          draft: _draft,
                          id: 'relationTarget',
                          label: '关联其他词条',
                          allowNone: true,
                          noneLabel: '无人物关联',
                          // 原下拉里「无人物关联」是初始选中项，不只是备选项。
                          selectNoneInitially: true,
                          border: const OutlineInputBorder(),
                          isDense: true,
                          options: relationOptions,
                          onChanged: (_) => setState(() {}),
                        ),
                        // 二级条件：选了关联词条才需要填关系描述。
                        if (_draft.selection('relationTarget') != null) ...<Widget>[
                          AppSpacing.hMd,
                          FormTextField(
                            draft: _draft,
                            id: 'relationContent',
                            label: '关联关系描述',
                            hint: '例如：导师、宿敌、挚友',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ],
                      ],
                    ),

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
                        FormSection(
                          title: '匹配规则',
                          children: <Widget>[
                            FormTextField(
                              draft: _draft,
                              id: 'regex',
                              label: '正则匹配规则（可选）',
                              hint: '例如：\\b雨夜\\b',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            AppSpacing.hMd,
                            // 三个布尔开关是 chip 形态（不是文本 / 实体选择），
                            // 共享层没有对应构件，保持原样。
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
                          ],
                        ),
                        FormSection(
                          title: '触发节奏',
                          children: <Widget>[
                            // 三个数字字段仍是一行三列（layout 不变），clamp 在 _submit 里。
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: FormTextField(
                                    draft: _draft,
                                    id: 'order',
                                    label: '排序',
                                    hint: '越小越靠前',
                                    keyboardType: TextInputType.number,
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                                AppSpacing.wSm,
                                Expanded(
                                  child: FormTextField(
                                    draft: _draft,
                                    id: 'cooldown',
                                    label: '冷却轮数',
                                    hint: '触发后静默轮数',
                                    keyboardType: TextInputType.number,
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                                AppSpacing.wSm,
                                Expanded(
                                  child: FormTextField(
                                    draft: _draft,
                                    id: 'delay',
                                    label: '延迟轮数',
                                    hint: '提及后延迟触发',
                                    keyboardType: TextInputType.number,
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ],
                            ),
                            AppSpacing.hMd,
                            FormEntitySelect(
                              draft: _draft,
                              id: 'decorator',
                              label: '激活装饰符',
                              options: _decoratorOptions,
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
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
