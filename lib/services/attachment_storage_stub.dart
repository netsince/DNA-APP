import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 单个附件（落盘字节）的硬上限：20MB。超过就不该进存储层。
const int kMaxAttachmentBytes = 20 * 1024 * 1024;

/// 图片（压缩后）的上限：5MB。
const int kMaxImageBytes = 5 * 1024 * 1024;

/// 文本类附件最多读取的字符数（再长就截断，避免一次把上下文撑爆）。
const int kMaxTextChars = 200000;

/// 聊天附件存储（Web 平台实现）—— 同样是内容寻址：key 就是内容字节的 sha256。
///
/// Web 没有可写的文件系统，字节存 IndexedDB（Hive box `attachments`）：
/// key = 引用 `<sha256>.<ext>`，value = 原始字节。引用格式与 IO 端完全一致，
/// 所以消息 JSON 跨端可读；字节本身不随引用走，换端后要重新上传。
class AttachmentStore {
  AttachmentStore._();

  static final AttachmentStore instance = AttachmentStore._();

  /// 现有 box：tas / identities / worlds / conversations / settings / ta_images，
  /// 这里用 `attachments` 单独一个，不跟它们混。
  static const String _boxName = 'attachments';

  /// 合法引用：64 位小写十六进制 sha256 + '.' + 扩展名（与 IO 端同一套规则）。
  static final RegExp _refPattern = RegExp(r'^[0-9a-f]{64}\.[a-z0-9]+$');

  Future<Box<Uint8List>> _box() => Hive.openBox<Uint8List>(_boxName);

  /// 保存字节，返回内容寻址引用 `'<sha256>.<ext>'`。
  ///
  /// 内容相同 → 同一个引用；box 里已经有就只返回引用，不再写一遍（幂等，
  /// IndexedDB 的写入量按内容去重后是 0）。
  Future<String> save(Uint8List bytes, {required String ext}) async {
    final String ref = '${sha256.convert(bytes)}.${normalizeExt(ext)}';
    final Box<Uint8List> box = await _box();
    if (box.containsKey(ref)) return ref;
    await box.put(ref, bytes);
    return ref;
  }

  /// 读取引用对应字节；不存在（清过缓存、换端、引用被改坏）一律返回 null。
  ///
  /// **不抛异常**：聊天页只该把附件显示成「已丢失」，不该整页崩掉。
  Future<Uint8List?> read(String ref) async {
    if (!isValidRef(ref)) return null;
    try {
      final Box<Uint8List> box = await _box();
      return box.get(ref);
    } catch (_) {
      // IndexedDB 打不开（无痕模式、配额满）：同样只当「没有这个文件」。
      return null;
    }
  }

  /// 引用对应的字节是否还在（同样不抛异常）。
  /// Web 端没有文件系统路径：恒为 null（调用方退化到按字节处理）。
  Future<String?> pathFor(String ref) async => null;

  Future<bool> exists(String ref) async {
    if (!isValidRef(ref)) return false;
    try {
      final Box<Uint8List> box = await _box();
      return box.containsKey(ref);
    } catch (_) {
      return false;
    }
  }

  /// 所有已存引用（GC / 存储页用）。
  Future<List<String>> listRefs() async {
    try {
      final Box<Uint8List> box = await _box();
      final List<String> refs = box.keys.whereType<String>().where(isValidRef).toList()
        ..sort();
      return refs;
    } catch (_) {
      return const <String>[];
    }
  }

  /// 已存附件的总字节数（同一份内容只算一次 —— 它本来就只有一个 key）。
  Future<int> totalBytes() async {
    try {
      final Box<Uint8List> box = await _box();
      int total = 0;
      for (final String ref in box.keys.whereType<String>()) {
        if (!isValidRef(ref)) continue;
        total += box.get(ref)?.length ?? 0;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// 删除某个引用（GC 用；调用方负责先确认没有消息再引用它）。删不存在的不报错。
  Future<void> delete(String ref) async {
    if (!isValidRef(ref)) return;
    try {
      final Box<Uint8List> box = await _box();
      if (box.containsKey(ref)) {
        await box.delete(ref);
      }
    } catch (_) {
      // 删不掉留给下次 GC，不打断调用方。
    }
  }

  /// 计算引用落在哪个前缀目录（sha256 前 2 位）。
  ///
  /// Web 端字节都在同一个 box 里、没有目录，这里返回同一套前缀，
  /// 只是为了 API 与 IO 端保持一致（两端调用方代码可以完全一样）。
  String shardOf(String ref) {
    if (ref.length < 2) return '00';
    return ref.substring(0, 2);
  }

  /// ext 归一化：小写、只留字母数字（`.PNG`→`png`、`jp!g`→`jpg`），空则 `bin`。
  ///
  /// 两端必须用同一套规则：扩展名会进引用，两边不一致就会把同一份内容
  /// 存成两个引用，去重也就白做了。
  String normalizeExt(String ext) {
    final String cleaned = ext.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return cleaned.isEmpty ? 'bin' : cleaned;
  }

  /// 引用是否合法。
  bool isValidRef(String ref) => _refPattern.hasMatch(ref);
}
