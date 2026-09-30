import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/widgets/sticker_text.dart';

/// 发帖页：正文 + 可选单图 + 可选话题 + 可选关联角色卡。
///
/// 通过 [presetCardId]/[presetCardName] 支持从卡片详情「引用到茶馆」直接带卡。
class TeahouseComposePage extends StatefulWidget {
  const TeahouseComposePage({super.key, this.presetCardId, this.presetCardName});

  final String? presetCardId;
  final String? presetCardName;

  @override
  State<TeahouseComposePage> createState() => _TeahouseComposePageState();
}

class _TeahouseComposePageState extends State<TeahouseComposePage> {
  static const int _maxContentLen = 280;

  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();

  XFile? _image;
  bool _pickingImage = false;

  String? _linkedCardId;
  String? _linkedCardName;

  bool _submitting = false;
  bool _searched = false;
  List<Map<String, dynamic>> _cardResults = const <Map<String, dynamic>>[];

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _linkedCardId = widget.presetCardId;
    _linkedCardName = widget.presetCardName;
  }

  @override
  void dispose() {
    _contentController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  bool get _loggedIn => AuthSession.instance.isLoggedIn;

  Future<void> _pickImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 82,
      );
      if (!mounted) return;
      setState(() => _image = picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('选择图片失败')),
      );
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  /// 在正文输入框光标处插入表情包标记。
  Future<void> _openStickerPicker() async {
    final token = await showStickerPicker(context);
    if (token == null || !mounted) return;
    final controller = _contentController;
    final value = controller.text;
    final sel = controller.selection;
    final start = sel.isValid ? sel.start : value.length;
    final end = sel.isValid ? sel.end : value.length;
    controller.text = value.replaceRange(start, end, token);
    controller.selection = TextSelection.collapsed(offset: start + token.length);
  }

  /// 读取选中图片为 base64 data URL（与后端约定的 multipart/JSON 数据格式）。
  Future<String?> _readImageData() async {
    final file = _image;
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      // 后端要求 data URL（image/webp 或原格式）。此处按原格式内联，服务端会再压缩为 WebP。
      final ext = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : 'png';
      final mime = _mimeOf(ext);
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  String _mimeOf(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'png':
      default:
        return 'image/png';
    }
  }

  Future<void> _searchCards(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _cardResults = const <Map<String, dynamic>>[];
        _searched = false;
      });
      return;
    }
    try {
      final results = await ApiClient.instance.searchLinkCards(query);
      if (!mounted) return;
      setState(() {
        _cardResults = results;
        _searched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searched = true);
    }
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入正文内容')));
      return;
    }
    if (!_loggedIn) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先登录后再发帖')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final imageData = await _readImageData();
      final topic = _topicController.text.trim();
      final id = await ApiClient.instance.createTeahousePost(
        content: content,
        cardId: _linkedCardId,
        imageData: imageData,
        topic: topic.isEmpty ? null : topic,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('发布成功')));
      Navigator.of(context).pop(id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('发布失败，请重试')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发帖'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _submitting
                ? const Center(child: CircularProgressIndicator())
                : FilledButton(
                    onPressed: _submit,
                    child: const Text('发布'),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // 关联角色卡（可选）。
          if (_linkedCardId != null) ...<Widget>[
            _LinkedCardChip(
              name: _linkedCardName ?? '角色卡',
              onRemove: () => setState(() {
                _linkedCardId = null;
                _linkedCardName = null;
              }),
            ),
            const SizedBox(height: 12),
          ],
          // 正文。
          TextField(
            controller: _contentController,
            maxLines: 6,
            maxLength: _maxContentLen,
            decoration: const InputDecoration(
              hintText: '说点什么…',
              border: OutlineInputBorder(),
            ),
          ),
          // 工具栏：表情包。
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: _openStickerPicker,
              tooltip: '表情包',
              icon: const Icon(Icons.emoji_emotions_outlined),
            ),
          ),
          const SizedBox(height: 4),
          // 关联角色卡搜索。
          Text('关联角色卡（可选）',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  onChanged: _searchCards,
                  decoration: const InputDecoration(
                    hintText: '搜索要关联的角色卡…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          if (_searched && _linkedCardId == null) ...<Widget>[
            const SizedBox(height: 8),
            if (_cardResults.isEmpty)
              const Text('没有找到可关联的角色卡', style: TextStyle(color: Colors.grey))
            else
              ..._cardResults.take(8).map((c) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.badge_outlined),
                    title: Text((c['name'] ?? '').toString()),
                    subtitle: Text((c['intro'] ?? '').toString(),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.add),
                    onTap: () => setState(() {
                      _linkedCardId = (c['id'] ?? '').toString();
                      _linkedCardName = (c['name'] ?? '').toString();
                      _cardResults = const <Map<String, dynamic>>[];
                    }),
                  )),
          ],
          const SizedBox(height: 16),
          // 话题。
          TextField(
            controller: _topicController,
            decoration: const InputDecoration(
              hintText: '话题（可选，如：闲聊）',
              isDense: true,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.local_offer_outlined),
            ),
          ),
          const SizedBox(height: 16),
          // 配图（单图）。
          Row(
            children: <Widget>[
              Text('配图（可选，单图）',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          if (_image == null)
            OutlinedButton.icon(
              onPressed: _pickingImage ? null : _pickImage,
              icon: const Icon(Icons.image_outlined),
              label: Text(_pickingImage ? '选择中…' : '选择图片'),
            )
          else ...<Widget>[
            Stack(
              alignment: Alignment.topRight,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_image!.path),
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                  onPressed: () => setState(() => _image = null),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 已关联角色卡 chip。
class _LinkedCardChip extends StatelessWidget {
  const _LinkedCardChip({required this.name, required this.onRemove});

  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.badge_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
