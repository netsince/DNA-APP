import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/widgets/card_crop_page.dart';

/// 角色卡图片槽位。
const List<(String, String, IconData, CropAspect)> _imageSlots =
    <(String, String, IconData, CropAspect)>[
  ('square', '1:1 形象', Icons.crop_square, CropAspect.square),
  ('landscape', '16:9 形象（头图）', Icons.landscape_outlined,
      CropAspect.landscape),
  ('portrait', '9:16 形象', Icons.portrait_outlined, CropAspect.portrait),
];

const List<String> _genders = <String>['男', '女', '无性', '其他'];

/// 发布/编辑角色卡页：正文各字段 + 三槽位图片（按比例裁剪）+ 对话风格 + 标签 + 作者注释。
///
/// 支持两种用途：
/// - 新建发布（[editCardId] 为空）：提交 `publishCard`；
/// - 编辑我的角色卡（[editCardId] 非空）：从详情预填并提交 `editCard`。
/// 也支持从导出的 JSON 导入预填（[parseCardImport]）。
class CardPublishPage extends StatefulWidget {
  const CardPublishPage({super.key, this.editCardId, this.prefill});

  /// 编辑模式：目标卡 id；为空表示新建。
  final String? editCardId;

  /// 初始预填（新建 + 从 JSON 解析后也会走这里）。
  final Map<String, dynamic>? prefill;

  @override
  State<CardPublishPage> createState() => _CardPublishPageState();
}

class _CardPublishPageState extends State<CardPublishPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late String _gender;
  late final TextEditingController _persona;
  late final TextEditingController _intro;
  late final TextEditingController _opening;
  late final TextEditingController _originalLink;
  final List<String> _tags = <String>[];
  late final TextEditingController _tagInput;
  late final TextEditingController _authorNote;
  late final TextEditingController _authorNoteInterval;
  late final TextEditingController _seed;

  final List<({String user, String assistant})> _dialogue =
      <({String user, String assistant})>[];

  /// 各槽位：已裁剪的图片字节（新选的）或空。
  final Map<String, Uint8List?> _images = <String, Uint8List?>{};
  final Map<String, String> _existingImages = <String, String>{};
  String _coverFocus = '50,50';

  bool _submitting = false;
  bool _loadingDetail = false;
  final ImagePicker _picker = ImagePicker();

  bool get _editing => widget.editCardId != null;
  bool get _loggedIn => AuthSession.instance.isLoggedIn;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _gender = '无性';
    _persona = TextEditingController();
    _intro = TextEditingController();
    _opening = TextEditingController();
    _originalLink = TextEditingController();
    _tagInput = TextEditingController();
    _authorNote = TextEditingController();
    _authorNoteInterval = TextEditingController();
    _seed = TextEditingController();
    if (widget.prefill != null) {
      _applyPrefill(widget.prefill!);
    } else if (_editing) {
      // 编辑模式：从详情接口拉取当前内容预填。
      _loadDetail();
    }
  }

  Future<void> _loadDetail() async {
    setState(() => _loadingDetail = true);
    try {
      final d = await ApiClient.instance.getCardDetail(widget.editCardId!);
      if (!mounted) return;
      _applyPrefill(d);
    } catch (_) {
      // 拉取失败不阻塞表单，用户仍可手动填写后提交。
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _persona.dispose();
    _intro.dispose();
    _opening.dispose();
    _originalLink.dispose();
    _tagInput.dispose();
    _authorNote.dispose();
    _authorNoteInterval.dispose();
    _seed.dispose();
    super.dispose();
  }

  void _applyPrefill(Map<String, dynamic> p) {
    _name.text = (p['name'] ?? '').toString();
    final g = (p['gender'] ?? '').toString();
    _gender = _genders.contains(g) ? g : (g.isEmpty ? '无性' : g);
    _persona.text = (p['persona'] ?? '').toString();
    _intro.text = (p['intro'] ?? '').toString();
    _opening.text = (p['opening'] ?? '').toString();
    _originalLink.text = (p['original_link'] ?? '').toString();
    _authorNote.text = (p['author_note'] ?? '').toString();
    _authorNoteInterval.text = (p['author_note_interval'] ?? '').toString();
    _seed.text = (p['seed'] ?? '').toString();
    if (p['cover_focus'] != null) {
      _coverFocus = (p['cover_focus'] ?? '50,50').toString();
    }

    _tags.clear();
    final tags = p['tags'];
    if (tags is List) {
      _tags.addAll(tags.map((t) => t.toString().trim()).where((t) => t.isNotEmpty));
    }
    final ds = p['dialogue_style'];
    if (ds is List) {
      _dialogue.clear();
      for (final turn in ds) {
        if (turn is Map) {
          _dialogue.add((
            user: (turn['user'] ?? '').toString(),
            assistant: (turn['assistant'] ?? '').toString(),
          ));
        }
      }
    }
    final imgs = p['images'];
    if (imgs is Map) {
      _existingImages.clear();
      imgs.forEach((k, v) {
        if (v != null) _existingImages[k.toString()] = v.toString();
      });
    }
    setState(() {});
  }

  /// 选择图片后，按槽位比例裁剪。
  Future<void> _pickImage(String slot, CropAspect aspect) async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      // 按槽位要求的比例锁定裁剪：1:1 / 16:9 / 9:16 是展示端的硬约束，不允许自由改比例。
      // 服务端按同一套比例强制校验（app/services/card_publish_service.py）。
      final cropped = await openCropPage(
        context,
        sourceBytes: bytes,
        aspect: aspect,
      );
      if (cropped == null || !mounted) return;
      setState(() {
        _images[slot] = cropped;
        _existingImages.remove(slot);
      });
    } catch (_) {
      if (!mounted) return;
      _snack('选择图片失败');
    }
  }

  Future<String?> _readSlot(String slot) async {
    final bytes = _images[slot];
    if (bytes != null && bytes.isNotEmpty) {
      return 'data:image/png;base64,${base64Encode(bytes)}';
    }
    return _existingImages[slot];
  }

  void _removeImage(String slot) {
    setState(() {
      _images[slot] = null;
      _existingImages.remove(slot);
    });
  }

  Future<Map<String, dynamic>> _buildPayload() async {
    final images = <String, String>{};
    for (final (slot, _, _, _) in _imageSlots) {
      final data = await _readSlot(slot);
      if (data != null && data.isNotEmpty) images[slot] = data;
    }
    return <String, dynamic>{
      'name': _name.text.trim(),
      'gender': _gender,
      'persona': _persona.text,
      'intro': _intro.text,
      'opening': _opening.text,
      'original_link': _originalLink.text.trim(),
      'cover_focus': _coverFocus,
      'seed': _seed.text.trim(),
      'author_note': _authorNote.text.trim(),
      'author_note_interval':
          int.tryParse(_authorNoteInterval.text.trim()) ?? 0,
      'tags': List<String>.from(_tags),
      'dialogue_style': _dialogue
          .map((d) => <String, String>{'user': d.user, 'assistant': d.assistant})
          .toList(),
      'images': images,
    };
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_loggedIn) {
      _snack('请先登录后再发布');
      return;
    }
    setState(() => _submitting = true);
    try {
      final payload = await _buildPayload();
      // 网页版对齐：网络失败自动重试一次，且服务端按内容指纹幂等去重，不会产生重复卡片。
      try {
        await _publishOrEdit(payload);
      } catch (_) {
        // 仅网络类失败重试一次；本地校验错误不上抛。
        await _publishOrEdit(payload);
      }
      if (!mounted) return;
      _snack(_editing ? '已保存并重新提审' : '已提交，等待审核');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack('提交失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _publishOrEdit(Map<String, dynamic> payload) async {
    if (_editing) {
      await ApiClient.instance.editCard(widget.editCardId!, payload);
    } else {
      await ApiClient.instance.publishCard(payload);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---- 标签 chips ----
  void _addTags(String raw) {
    final parts = raw
        .split(RegExp(r'[,，]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    var changed = false;
    for (final t in parts) {
      if (!_tags.contains(t)) {
        _tags.add(t);
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  void _removeTag(int index) {
    setState(() => _tags.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '编辑角色卡' : '上传角色卡'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _submitting
                ? const Center(child: CircularProgressIndicator())
                : FilledButton(onPressed: _submit, child: const Text('提交')),
          ),
        ],
      ),
      body: _loadingDetail
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  _label('名称 *'),
                  TextFormField(
                    controller: _name,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入名称' : null,
                    decoration: const InputDecoration(
                      hintText: '角色卡名称',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('性别'),
                  DropdownButtonFormField<String>(
                    initialValue: _genders.contains(_gender) ? _gender : '无性',
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: _genders
                        .map((g) => DropdownMenuItem<String>(
                            value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _gender = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  _label('人设'),
                  TextFormField(
                    controller: _persona,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '人物设定（persona）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('简介'),
                  TextFormField(
                    controller: _intro,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: '一句话简介',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('开场白'),
                  TextFormField(
                    controller: _opening,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: '首次对话开场白',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('原创链接'),
                  TextFormField(
                    controller: _originalLink,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://…（可选）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('标签'),
                  _TagInput(
                    controller: _tagInput,
                    tags: _tags,
                    onAdd: () {
                      _addTags(_tagInput.text);
                      _tagInput.clear();
                    },
                    onRemove: _removeTag,
                  ),
                  const SizedBox(height: 16),
                  _label('对话风格（可选）'),
                  _DialogueEditor(
                    dialogue: _dialogue,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  _label('图片（可选）'),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('选择图片后按对应比例裁剪确认',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  ..._imageSlots.map((s) => _ImageSlotPicker(
                        slot: s.$1,
                        label: s.$2,
                        icon: s.$3,
                        aspect: s.$4,
                        bytes: _images[s.$1],
                        existingPath: _existingImages[s.$1],
                        onPick: () => _pickImage(s.$1, s.$4),
                        onRemove: () => _removeImage(s.$1),
                        showFocusPicker: s.$1 == 'landscape',
                        focus: _coverFocus,
                        onFocusTap: (f) => setState(() => _coverFocus = f),
                      )),
                  const SizedBox(height: 8),
                  // ---- 更多选项 ----
                  ExpansionTile(
                    title: const Text('更多选项'),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    children: <Widget>[
                      _label('语音 Seed（可选）'),
                      TextFormField(
                        controller: _seed,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '留空则由客户端决定音色',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _label('作者注释（可选）'),
                      TextFormField(
                        controller: _authorNote,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: '希望模型始终记住/强调的内容',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _label('作者注释注入间隔'),
                      TextFormField(
                        controller: _authorNoteInterval,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '每 N 条注入（0 表示禁用）',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w500)),
      );
}

/// 标签输入：输入后回车/逗号添加成可移除的 chips。
class _TagInput extends StatelessWidget {
  const _TagInput({
    required this.controller,
    required this.tags,
    required this.onAdd,
    required this.onRemove,
  });

  final TextEditingController controller;
  final List<String> tags;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (tags.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (var i = 0; i < tags.length; i++)
                InputChip(
                  label: Text(tags[i]),
                  onDeleted: () => onRemove(i),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: '输入标签后按回车或逗号添加，中英文逗号均可',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => onAdd(),
          onChanged: (v) {
            // 输入中英文逗号时直接落为标签。
            if (v.contains(',') || v.contains('，')) {
              onAdd();
            }
          },
          onTapOutside: (_) => onAdd(),
        ),
        const SizedBox(height: 4),
        Text('点击标签上的 × 可移除',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

/// 对话风格编辑：一问一答列表，可增删。
class _DialogueEditor extends StatelessWidget {
  const _DialogueEditor({required this.dialogue, required this.onChanged});

  final List<({String user, String assistant})> dialogue;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (var i = 0; i < dialogue.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '用户问',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) =>
                        dialogue[i] = (user: v, assistant: dialogue[i].assistant),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'AI 答',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => dialogue[i] =
                        (user: dialogue[i].user, assistant: v),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    dialogue.removeAt(i);
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('添加对话'),
            onPressed: () {
              dialogue.add((user: '', assistant: ''));
              onChanged();
            },
          ),
        ),
      ],
    );
  }
}

/// 单槽位图片选择器：选图后展示裁剪结果；横版头图支持点击设定封面焦点。
class _ImageSlotPicker extends StatelessWidget {
  const _ImageSlotPicker({
    required this.slot,
    required this.label,
    required this.icon,
    required this.aspect,
    required this.bytes,
    required this.existingPath,
    required this.onPick,
    required this.onRemove,
    required this.showFocusPicker,
    required this.focus,
    required this.onFocusTap,
  });

  final String slot;
  final String label;
  final IconData icon;
  final CropAspect aspect;
  final Uint8List? bytes;
  final String? existingPath;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final bool showFocusPicker;
  final String focus;
  final ValueChanged<String> onFocusTap;

  Widget? _buildPreview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (bytes != null) {
      return Image.memory(bytes!,
          height: 160, fit: BoxFit.cover, width: double.infinity);
    }
    if (existingPath != null && existingPath!.startsWith('data:')) {
      return Image.memory(
        base64Decode(existingPath!.split(',').last),
        height: 160,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => const SizedBox(height: 160),
      );
    }
    if (existingPath != null && existingPath!.isNotEmpty) {
      // 相对路径：无法直接预览，仅显示占位，可重新选择或移除。
      return Container(
        height: 160,
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Icon(icon, size: 28, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _buildPreview(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            width: double.infinity,
            child: Stack(
              children: <Widget>[
                if (preview != null)
                  preview
                else
                  InkWell(
                    onTap: onPick,
                    child: SizedBox(
                      height: 160,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(icon,
                                size: 32, color: scheme.onSurfaceVariant),
                            const SizedBox(height: 6),
                            Text('点击选择图片',
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                // 横版头图：点击设定封面焦点（覆盖在预览图上方）。
                if (showFocusPicker && preview != null)
                  Positioned.fill(
                    child: _FocusLayer(
                      focus: focus,
                      onChanged: onFocusTap,
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: <Widget>[
              TextButton(onPressed: onPick, child: const Text('选择')),
              if (preview != null)
                TextButton(onPressed: onRemove, child: const Text('移除')),
            ],
          ),
          if (showFocusPicker && preview != null)
            Text('点击头图设定封面焦点（脸部位置）；留空则居中显示',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

/// 横版头图焦点选择层：把点击位置映射成 x,y 百分比并显示焦点标记。
class _FocusLayer extends StatefulWidget {
  const _FocusLayer({required this.focus, required this.onChanged});

  final String focus;
  final ValueChanged<String> onChanged;

  @override
  State<_FocusLayer> createState() => _FocusLayerState();
}

class _FocusLayerState extends State<_FocusLayer> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final parts = widget.focus.split(',');
        final fx = parts.isNotEmpty ? double.tryParse(parts[0]) : null;
        final fy = parts.length > 1 ? double.tryParse(parts[1]) : null;
        return GestureDetector(
          onTapDown: (d) {
            final x = (d.localPosition.dx / w * 100).clamp(0, 100);
            final y = (d.localPosition.dy / h * 100).clamp(0, 100);
            widget.onChanged('${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}');
          },
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: <Widget>[
              if (fx != null && fy != null)
                Positioned(
                  left: fx / 100 * w - 10,
                  top: fy / 100 * h - 10,
                  child: IgnorePointer(
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.5),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
