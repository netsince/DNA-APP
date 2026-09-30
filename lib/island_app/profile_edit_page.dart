import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/widgets/avatar.dart';
import 'package:dna/island_app/widgets/card_crop_page.dart';

/// 个人资料编辑页：昵称 / 简介 / 所在地 / 网站 / 生日 / 点赞通知开关 + 头像上传/移除。
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nickname;
  late final TextEditingController _bio;
  late final TextEditingController _location;
  late final TextEditingController _website;
  late final TextEditingController _birthday;
  late bool _notifyLike;
  late String _existingAvatar;

  /// 裁剪后的头像（PNG 字节）；非空表示已选新头像。
  Uint8List? _croppedAvatar;
  bool _removeAvatar = false;
  bool _loading = true;
  bool _submitting = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController();
    _bio = TextEditingController();
    _location = TextEditingController();
    _website = TextEditingController();
    _birthday = TextEditingController();
    _notifyLike = true;
    _existingAvatar = '';
    _load();
  }

  @override
  void dispose() {
    _nickname.dispose();
    _bio.dispose();
    _location.dispose();
    _website.dispose();
    _birthday.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await ApiClient.instance.getMyProfile();
      if (!mounted) return;
      setState(() {
        _nickname.text = (p['nickname'] ?? '').toString();
        _bio.text = (p['bio'] ?? '').toString();
        _location.text = (p['location'] ?? '').toString();
        _website.text = (p['website'] ?? '').toString();
        final bd = (p['birthday'] ?? '').toString();
        _birthday.text = bd.isEmpty ? '' : bd.split('T').first;
        _notifyLike = p['notify_like'] == true;
        _existingAvatar = (p['avatar'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('加载资料失败：$e');
    }
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      // 对齐网页版：头像强制按 1:1 方形裁剪。
      final cropped = await openCropPage(
        context,
        sourceBytes: bytes,
        aspect: CropAspect.square,
      );
      if (cropped == null || !mounted) return;
      setState(() {
        _croppedAvatar = cropped;
        _removeAvatar = false;
      });
    } catch (_) {
      if (!mounted) return;
      _snack('选择头像失败');
    }
  }

  Future<String?> _readAvatarDataUrl() async {
    final bytes = _croppedAvatar;
    if (bytes == null || bytes.isEmpty) return null;
    try {
      // 裁剪页输出恒为 PNG。
      return 'data:image/png;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final payload = <String, dynamic>{
        'nickname': _nickname.text.trim(),
        'bio': _bio.text.trim(),
        'location': _location.text.trim(),
        'website': _website.text.trim(),
        'birthday': _birthday.text.trim(),
        'notify_like': _notifyLike,
      };
      if (_removeAvatar) {
        payload['remove_avatar'] = true;
      } else {
        final avatar = await _readAvatarDataUrl();
        if (avatar != null) payload['avatar_data_url'] = avatar;
      }
      await ApiClient.instance.updateMyProfile(payload);
      if (!mounted) return;
      _snack('已保存');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑资料'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _submitting
                ? const Center(child: CircularProgressIndicator())
                : FilledButton(onPressed: _submit, child: const Text('保存')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  _avatarSection(context),
                  const SizedBox(height: 20),
                  _label('昵称'),
                  TextFormField(
                    controller: _nickname,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入昵称' : null,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('简介'),
                  TextFormField(
                    controller: _bio,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '一句话介绍自己',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('所在地'),
                  TextFormField(
                    controller: _location,
                    decoration: const InputDecoration(
                      hintText: '城市 / 地区',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('网站'),
                  TextFormField(
                    controller: _website,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://…',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('生日'),
                  TextFormField(
                    controller: _birthday,
                    readOnly: true,
                    onTap: () => _pickBirthday(context),
                    decoration: const InputDecoration(
                      hintText: '点击选择日期',
                      isDense: true,
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('收到点赞通知'),
                    value: _notifyLike,
                    onChanged: (v) => setState(() => _notifyLike = v),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _avatarSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget? preview;
    if (_removeAvatar) {
      preview = Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.person_off_outlined,
            color: scheme.onSurfaceVariant, size: 32),
      );
    } else if (_croppedAvatar != null) {
      preview = ClipOval(
        child: Image.memory(_croppedAvatar!,
            width: 80, height: 80, fit: BoxFit.cover),
      );
    } else if (_existingAvatar.isNotEmpty) {
      preview = Avatar(avatar: _existingAvatar, radius: 40);
    } else {
      preview = CircleAvatar(
        radius: 40,
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(Icons.person, size: 32, color: scheme.onSurfaceVariant),
      );
    }
    return Row(
      children: <Widget>[
        preview,
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextButton.icon(
              onPressed: _pickAvatar,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('选择头像'),
            ),
            if (_existingAvatar.isNotEmpty || _croppedAvatar != null)
              TextButton(
                onPressed: () => setState(() {
                  _removeAvatar = true;
                  _croppedAvatar = null;
                }),
                child: const Text('移除头像'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickBirthday(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _birthday.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
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
