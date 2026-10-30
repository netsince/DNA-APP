import 'dart:convert';
import 'dart:typed_data';

import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/services/image_storage.dart';
import 'package:dna/utils/id_utils.dart';

/// 角色卡：本地 TA ↔ 社区发布 payload。
///
/// 社区接口的字段是扁平的（name / gender / persona / … / images），TA 是另一套
/// 模型；这层映射原来长在 CardPublishPage 的表单里。现在发布页不再自己拼表单
/// （统一用软件本体的角色编辑器），映射只留这一处，发布与编辑共用。

/// TA → 发布 payload。图片由调用方传「槽位 → data URL」。
Map<String, dynamic> taToPublishPayload(
  TA ta, {
  Map<String, String> images = const <String, String>{},
  String coverFocus = '50,50',
}) {
  return <String, dynamic>{
    'name': ta.name.trim(),
    'gender': ta.gender,
    'persona': ta.persona,
    'intro': ta.intro,
    'opening': ta.opening,
    'original_link': (ta.originalLink ?? '').trim(),
    // TA 模型没有封面焦点，统一给居中；服务端按它裁封面。
    'cover_focus': coverFocus,
    'seed': ta.voiceSeed?.toString() ?? '',
    'author_note': (ta.authorNote ?? '').trim(),
    'author_note_interval': ta.authorNoteInterval,
    'tags': List<String>.from(ta.tags),
    'dialogue_style': ta.dialogueStyle
        .map(
          (DialogueTurn d) => <String, String>{
            'user': d.user,
            'assistant': d.assistant,
          },
        )
        .toList(),
    'images': images,
  };
}

/// TA 各槽位图片 → data URL（发布用）。
Future<Map<String, String>> taImageDataUrls(TA ta) async {
  final Map<String, String> out = <String, String>{};
  for (final MapEntry<String, String> e in ta.images.entries) {
    final Uint8List? bytes = await ImageStorage.instance.readBytes(e.value);
    if (bytes == null || bytes.isEmpty) continue;
    out[e.key] = 'data:${_mimeOf(e.value)};base64,${base64Encode(bytes)}';
  }
  return out;
}

/// 社区详情 → TA（编辑已发布卡用）。内嵌图片会落到本地存储，改完再按原样发回去。
Future<TA> taFromCardDetail(Map<String, dynamic> detail) async {
  final String taId = newId();
  final Map<String, String> images = <String, String>{};

  final Object? rawImages = detail['images'];
  if (rawImages is Map) {
    for (final MapEntry<dynamic, dynamic> e in rawImages.entries) {
      final String dataUrl = (e.value ?? '').toString();
      final Uint8List? bytes = _decodeDataUrl(dataUrl);
      if (bytes == null) continue;
      final String slot = e.key.toString();
      images[slot] = await ImageStorage.instance.saveBytes(
        taId: taId,
        slot: slot,
        bytes: bytes,
        ext: _extOfDataUrl(dataUrl),
      );
    }
  }

  final Object? rawDialogue = detail['dialogue'];
  final List<DialogueTurn> dialogue = rawDialogue is List
      ? rawDialogue.whereType<Map>().map((Map e) {
          return DialogueTurn(
            user: (e['user'] ?? '').toString(),
            assistant: (e['assistant'] ?? '').toString(),
          );
        }).toList()
      : <DialogueTurn>[];

  final String authorNote = (detail['authorNote'] ?? '').toString().trim();
  final String originalLink = (detail['original_link'] ?? '').toString().trim();

  return TA(
    id: taId,
    name: (detail['name'] ?? '').toString(),
    gender: (detail['gender'] ?? '无性').toString(),
    persona: (detail['persona'] ?? '').toString(),
    intro: (detail['intro'] ?? '').toString(),
    opening: (detail['opening'] ?? '').toString(),
    tags:
        (detail['tags'] as List?)?.whereType<String>().toList() ??
        const <String>[],
    images: images,
    dialogueStyle: dialogue,
    originalLink: originalLink.isEmpty ? null : originalLink,
    voiceSeed: int.tryParse((detail['seed'] ?? '').toString()),
    authorNote: authorNote.isEmpty ? null : authorNote,
    authorNoteInterval: detail['authorNoteInterval'] is num
        ? (detail['authorNoteInterval'] as num).toInt()
        : 0,
  );
}

String _mimeOf(String ref) {
  final String lower = ref.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

String _extOfDataUrl(String url) {
  if (url.startsWith('data:image/png')) return 'png';
  if (url.startsWith('data:image/webp')) return 'webp';
  if (url.startsWith('data:image/gif')) return 'gif';
  return 'jpg';
}

Uint8List? _decodeDataUrl(String url) {
  final int comma = url.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(url.substring(comma + 1));
  } catch (_) {
    return null;
  }
}
