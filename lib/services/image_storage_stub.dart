import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/ta.dart';

/// TA 图片存储（Web 平台实现）。
///
/// 图片字节存于 IndexedDB（Hive box），TA.images 中保存逻辑文件名
/// `<taId>_<slot>.<ext>`（与备份 ZIP 内 `images/` 的相对名一致），
/// 从而保证手机 ↔ Web 导出的备份可双向互导。
class ImageStorage {
  ImageStorage._();

  static final ImageStorage instance = ImageStorage._();

  static const String _boxName = 'ta_images';

  Future<Box<Uint8List>> _box() => Hive.openBox<Uint8List>(_boxName);

  /// 从引用（逻辑文件名）读取图片字节；无此图返回 null。
  Future<Uint8List?> readBytes(String ref) async {
    if (ref.isEmpty) return null;
    final Box<Uint8List> box = await _box();
    final Uint8List? bytes = box.get(ref);
    return bytes;
  }

  /// 保存图片字节，引用 = 逻辑文件名 `<taId>_<slot>.<ext>`。
  Future<String> saveBytes({
    required String taId,
    required String slot,
    required Uint8List bytes,
    String? ext,
  }) async {
    final String e = _normalizeExt(ext);
    final String ref = '${taId}_$slot$e';
    final Box<Uint8List> box = await _box();
    await box.put(ref, bytes);
    return ref;
  }

  /// 删除引用对应的图片（幂等）。
  Future<void> delete(String ref) async {
    if (ref.isEmpty) return;
    final Box<Uint8List> box = await _box();
    await box.delete(ref);
  }

  /// 清空全部 TA 图片（清空 IndexedDB 图片 box）。
  Future<void> clearAll() async {
    final Box<Uint8List> box = await _box();
    await box.clear();
  }

  /// 返回 TA 指定槽位的可显示 ImageProvider；无图返回 null。
  /// 通过自定义 ImageProvider 异步从 IndexedDB 读取字节。
  ImageProvider? providerFor(TA ta, String slot) {
    final String? ref = ta.images[slot];
    if (ref == null || ref.isEmpty) return null;
    return providerForRef(ref);
  }

  /// 根据引用（逻辑文件名）返回可显示 ImageProvider；引用为空返回 null。
  ImageProvider? providerForRef(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    return _WebMemoryImage(ref);
  }

  String _normalizeExt(String? ext) {
    final String e = (ext == null || ext.isEmpty) ? '.jpg' : ext;
    return e.startsWith('.') ? e : '.$e';
  }
}

/// 异步从 IndexedDB 读取图片字节的 ImageProvider（仅 Web 使用）。
class _WebMemoryImage extends ImageProvider<_WebMemoryImage> {
  _WebMemoryImage(this.ref);

  final String ref;

  @override
  Future<_WebMemoryImage> obtainKey(ImageConfiguration configuration) async =>
      this;

  @override
  ImageStreamCompleter loadImage(
    _WebMemoryImage key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_loadAsync(decode));
  }

  Future<ImageInfo> _loadAsync(ImageDecoderCallback decode) async {
    final Uint8List? bytes = await ImageStorage.instance.readBytes(ref);
    if (bytes == null) {
      throw StateError('图片不存在: $ref');
    }
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(bytes);
    final ui.Codec codec = await decode(buffer);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is _WebMemoryImage && other.ref == ref;

  @override
  int get hashCode => Object.hash(_WebMemoryImage, ref);
}
