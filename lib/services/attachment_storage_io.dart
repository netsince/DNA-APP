import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dna/services/attachment_ref.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 单个附件（落盘字节）的硬上限：20MB。超过就不该进存储层。
const int kMaxAttachmentBytes = 20 * 1024 * 1024;

/// 图片（压缩后）的上限：5MB。
const int kMaxImageBytes = 5 * 1024 * 1024;

/// 文本类附件最多读取的字符数（再长就截断，避免一次把上下文撑爆）。
const int kMaxTextChars = 200000;

/// 聊天附件存储（IO 平台实现）—— 内容寻址：文件名就是内容字节的 sha256。
///
/// 落盘布局：`<应用文档目录>/attachments/<sha256 前 2 位>/<sha256>.<ext>`。
/// 分一级前缀目录是为了别把几千个文件全堆进同一个文件夹（单目录文件数过多时，
/// 列目录、查重、GC 遍历都会明显变慢；一级就够把单目录规模压到 1/256）。
class AttachmentStore {
  AttachmentStore._();

  static final AttachmentStore instance = AttachmentStore._();

  static const String _rootName = 'attachments';

  /// 原子写的临时后缀：先写 `<ref>.<唯一后缀>.part`，flush 后 rename 成正式文件名。
  static const String _partSuffix = '.part';


  /// 保存字节，返回内容寻址引用 `'<sha256>.<ext>'`。
  ///
  /// 内容相同 → 同一个引用；目标文件已存在就直接返回，不再写盘（幂等）。
  /// 写入是原子的：先写临时文件 `<ref>.<唯一后缀>.part`，flush 后再 rename 成
  /// 正式文件名。这样即使写到一半崩溃/断电，也不会留下「名字对、内容残」的
  /// 文件 —— 残片只会以 `.part` 身份躺在旁边，而读取端只认正式文件名。
  ///
  /// 临时名里带唯一后缀（不是写死的 `<ref>.part`）是被 Windows 逼的：
  /// 同一份内容被两处同时保存（连点发送、回溯重填与输入区同时存同一张图）
  /// 时，两个写者共用一个 `.part` 名字会触发 sharing violation
  /// （rename 报 errno 32「另一个程序正在使用此文件」）。各写各的临时文件，
  /// 谁最后 rename 都行 —— 字节本来就是同一份。
  Future<String> save(Uint8List bytes, {required String ext}) async {
    final String ref = '${sha256.convert(bytes)}.${normalizeExt(ext)}';
    final Directory root = await _ensureRoot();
    final File target = File(path.join(root.path, shardOf(ref), ref));
    // 已经存过同一份内容：直接返回，不重复占盘。
    if (await target.exists()) return ref;

    await target.parent.create(recursive: true);
    final File part = File('${target.path}.${_nextTempToken()}$_partSuffix');
    try {
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(target.path);
    } catch (_) {
      // 并发写同一份内容时，对手可能已经先把正式文件 rename 到位：
      // 只要正式文件已经在，结果完全一样，算成功；否则把异常抛给调用方。
      if (!await target.exists()) rethrow;
    } finally {
      // 失败路径不留下半截文件。成功路径上 .part 已经被 rename 走了。
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {
          // 清不掉也不致命：listRefs / totalBytes 都不认 .part。
        }
      }
    }
    return ref;
  }

  /// 每次写入独有的临时后缀（进程内）。不用随机数，避免为它引入 dart:math。
  static int _tempSeq = 0;

  static String _nextTempToken() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_tempSeq++}';

  /// 读取引用对应字节；文件不存在（用户删了、换机了、引用被改坏）一律返回 null。
  ///
  /// **不抛异常**：聊天页只该把附件显示成「已丢失」，不该因为一个读不到的
  /// 文件整页崩掉。
  Future<Uint8List?> read(String ref) async {
    if (!isValidRef(ref)) return null;
    try {
      final File f = await _fileFor(ref);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      // 权限不足 / 文件被占用 / 坏盘：同样只当「没有这个文件」。
      return null;
    }
  }

  /// 引用对应的字节是否还在（同样不抛异常）。
  /// 附件在磁盘上的绝对路径（不存在或引用非法时返回 null）。
  ///
  /// 全量备份要用它做「流式写 zip」，避免把几十 MB 附件一次性读进内存。
  Future<String?> pathFor(String ref) async {
    if (!isValidRef(ref)) return null;
    final File f = await _fileFor(ref);
    return await f.exists() ? f.path : null;
  }

  /// 清掉崩溃/断电留下的临时文件（`*.part`），返回删掉的个数。
  ///
  /// 这些残片不被 listRefs/totalBytes 统计，但确实占盘 —— 回收时顺手扫一遍。
  Future<int> cleanPartials() async {
    int removed = 0;
    try {
      final Directory root = Directory(await _rootPath());
      if (!await root.exists()) return 0;
      await for (final FileSystemEntity entity
          in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith(_partSuffix)) continue;
        try {
          await entity.delete();
          removed++;
        } catch (_) {
          // 单个删不掉不影响其它
        }
      }
    } catch (e) {
      debugPrint('[attachment] 清理临时文件失败: $e');
    }
    return removed;
  }

  Future<bool> exists(String ref) async {
    if (!isValidRef(ref)) return false;
    try {
      final File f = await _fileFor(ref);
      return await f.exists();
    } catch (_) {
      return false;
    }
  }

  /// 所有已存引用（GC / 存储页用）；目录还不存在时返回空列表。
  Future<List<String>> listRefs() async {
    final List<File> files = await _refFiles();
    final List<String> refs = <String>[
      for (final File f in files) path.basename(f.path),
    ]..sort();
    return refs;
  }

  /// 已存附件的总字节数（同一份内容只算一次 —— 它本来就只有一个文件）。
  Future<int> totalBytes() async {
    final List<File> files = await _refFiles();
    int total = 0;
    for (final File f in files) {
      total += await f.length();
    }
    return total;
  }

  /// 删除某个引用（GC 用；调用方负责先确认没有消息再引用它）。删不存在的不报错。
  Future<void> delete(String ref) async {
    if (!isValidRef(ref)) return;
    try {
      final File f = await _fileFor(ref);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 删不掉（被占用等）留给下次 GC，不打断调用方。
    }
  }

  /// 计算引用落在哪个前缀目录（sha256 前 2 位）。
  ///
  /// 存储页/调试工具要定位文件时用；正常读写走本类即可。
  String shardOf(String ref) => shardOfRef(ref);

  /// ext 归一化：小写、只留字母数字（`.PNG`→`png`、`jp!g`→`jpg`），空则 `bin`。
  ///
  /// 扩展名来自用户文件名，必须洗一遍再用进路径（否则 `../`、空格、
  /// 中文标点都会进文件名）。
  String normalizeExt(String ext) => normalizeAttachmentExt(ext);

  /// 引用是否合法（同时也是读取/删除前的路径穿越防线）。
  bool isValidRef(String ref) => isValidAttachmentRef(ref);

  /// 所有正式文件（跳过 `.part` 残片与目录）。
  Future<List<File>> _refFiles() async {
    final Directory root = Directory(await _rootPath());
    if (!await root.exists()) return const <File>[];
    final List<File> files = <File>[];
    await for (final FileSystemEntity entity
        in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!isValidRef(path.basename(entity.path))) continue;
      files.add(entity);
    }
    return files;
  }

  /// 附件根目录路径（不创建）。
  Future<String> _rootPath() async {
    final Directory doc = await getApplicationDocumentsDirectory();
    return path.join(doc.path, _rootName);
  }

  /// 附件根目录（不存在就建出来，只有写入路径会用到）。
  Future<Directory> _ensureRoot() async {
    final Directory dir = Directory(await _rootPath());
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 引用对应的正式文件（`<root>/<前 2 位>/<引用>`）。
  Future<File> _fileFor(String ref) async {
    final String root = await _rootPath();
    return File(path.join(root, shardOf(ref), ref));
  }
}
