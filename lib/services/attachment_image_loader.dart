import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import '../models/message_attachment.dart';
import 'attachment_storage.dart';

/// 每次请求最多带几张图。
///
/// 图片走 base64 进请求体，一张 5MB 的图就是 6.7MB 文本；历史里堆十几张会让
/// 请求体直接上几十 MB（弱网/中转必挂）。所以只带最近的若干张。
const int kMaxImagesPerRequest = 4;

/// 把附件里的图片读成 data URL（OpenAI 的 `image_url` 与 Anthropic 的
/// `base64` 块都从它出发）。
///
/// 结果按引用缓存：同一条消息被重试/重发时不重复读盘、不重复编码。
class AttachmentImageLoader {
  AttachmentImageLoader._();

  static final AttachmentImageLoader instance = AttachmentImageLoader._();

  final Map<String, String?> _cache = <String, String?>{};

  /// 收集 [messages] 里最近的若干张图，返回 ref → data URL（读不到的不进结果）。
  Future<Map<String, String>> collectFor(List<ConversationMessage> messages) async {
    final Map<String, String> out = <String, String>{};
    for (final ConversationMessage m in messages.reversed) {
      for (final MessageAttachment a in m.attachments.reversed) {
        if (!a.isImage) continue;
        if (out.length >= kMaxImagesPerRequest) return out;
        final String? url = await _dataUrl(a);
        if (url != null) out[a.ref] = url;
      }
    }
    return out;
  }

  Future<String?> _dataUrl(MessageAttachment a) async {
    if (_cache.containsKey(a.ref)) return _cache[a.ref];
    try {
      final Uint8List? bytes = await AttachmentStore.instance.read(a.ref);
      if (bytes == null) return _cache[a.ref] = null;
      final String mime =
          a.mime.startsWith('image/') ? a.mime : 'image/jpeg';
      return _cache[a.ref] = 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (e) {
      debugPrint('[attachment] 读取图片失败: $e');
      return _cache[a.ref] = null;
    }
  }
}

