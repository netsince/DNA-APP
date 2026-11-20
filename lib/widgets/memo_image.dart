import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 有上限的 ImageProvider 复用缓存。
///
/// 为什么需要它：`Image.memory(base64Decode(s))` 如果写在 `build()` 里，每次
/// 重建都会造出一个**全新的 Uint8List**，而 Flutter 的 ImageCache 是按字节对象
/// 认图片的 —— 于是同一张头像被反复解码成互不相等的新缓存条目，旧条目既命中不
/// 了也淘汰不掉。社区卡片头像、评论配图、工单截图都是这个写法。
///
/// 这里按「来源 + 目标宽度」复用同一个 provider：
/// * 同一张图只解码一次；
/// * 按目标宽度解码，不把 1080p 的图解进 40px 的头像里；
/// * 条目数有上限（FIFO 淘汰），不会变成新的泄漏源。
class MemoImage {
  MemoImage._();

  static const int _maxEntries = 256;
  static final Map<String, ImageProvider> _cache = <String, ImageProvider>{};

  /// data URL（`data:image/png;base64,...`）→ 按宽的 provider。
  static ImageProvider? dataUrl(String dataUrl, {int? cacheWidth}) {
    final int comma = dataUrl.indexOf(',');
    final String key = 'd|${cacheWidth ?? 0}|${dataUrl.length}|'

        '${dataUrl.hashCode}';
    final ImageProvider? hit = _cache[key];
    if (hit != null) return hit;
    final String b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
    final Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return null;
    }
    return _store(
      key,
      cacheWidth == null
          ? MemoryImage(bytes)
          : ResizeImage(MemoryImage(bytes), width: cacheWidth),
    );
  }

  /// 网络图 → 按宽的 provider（ResizeImage 让解码就按目标尺寸来）。
  static ImageProvider network(String url, {int? cacheWidth}) {
    final String key = 'n|${cacheWidth ?? 0}|$url';
    final ImageProvider? hit = _cache[key];
    if (hit != null) return hit;
    final ImageProvider base = NetworkImage(url);
    return _store(
      key,
      cacheWidth == null
          ? base
          : ResizeImage(base, width: cacheWidth),
    );
  }

  static ImageProvider _store(String key, ImageProvider provider) {
    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = provider;
    return provider;
  }

  /// 测试与「清内存」入口。
  static void clear() => _cache.clear();

  @visibleForTesting
  static int get debugEntryCount => _cache.length;
}
