import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dna/services/attachment_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// 附件存储（内容寻址）的六件事：
/// 1. 同一份内容只落一份、只算一次体积；
/// 2. 不同内容 → 不同引用；
/// 3. 引用格式 = 64 位小写 hex + 扩展名，且落在 <前 2 位>/ 前缀目录里；
/// 4. read 读回字节一致；读不到的引用返回 null 且不抛异常；
/// 5. listRefs 与实际文件一致；delete 之后 exists 为 false；
/// 6. 原子写：写完不留 .part 残片。
///
/// 只测 IO 实现：VM 上 `dart.library.io` 为真，入口文件的条件导出在这里会
/// 解析到 attachment_storage_io.dart，所以断言「文件真的落在磁盘上」同时也
/// 验证了条件导出没接错。Web 实现共用同一套引用格式（sha256 + ext），
/// 由同一份引用规则保证两端一致。
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._basePath);

  final String _basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _basePath;

  @override
  Future<String?> getTemporaryPath() async => _basePath;
}

Uint8List _bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  final AttachmentStore store = AttachmentStore.instance;

  late Directory tempDir;

  Directory attachmentsDir() => Directory(path.join(tempDir.path, 'attachments'));

  /// attachments/ 下所有文件的相对路径（排序，方便整体比对）。
  List<String> allFiles() {
    final Directory root = attachmentsDir();
    if (!root.existsSync()) return <String>[];
    final List<String> out = root
        .listSync(recursive: true)
        .whereType<File>()
        .map((File f) => path.relative(f.path, from: root.path))
        .toList()
      ..sort();
    return out;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dna_attachments_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('内容寻址 = 同一份内容只存一份', () {
    test('同一份字节存两次：引用相同、磁盘只有一个文件、体积只算一次', () async {
      final Uint8List data = _bytesOf('同一份内容，不管发几次都只该落一次盘');

      final String ref1 = await store.save(data, ext: 'txt');
      final String ref2 = await store.save(data, ext: 'txt');

      expect(ref2, ref1, reason: '内容相同就必须是同一个引用');
      expect(
        allFiles(),
        <String>[path.join(ref1.substring(0, 2), ref1)],
        reason: '磁盘上只能有一个文件（前缀目录 + 正式文件）',
      );
      expect(
        await store.totalBytes(),
        data.length,
        reason: '同一份内容不能重复计入体积',
      );
      expect(await store.listRefs(), <String>[ref1]);
    });

    test('不同字节 → 不同引用，两份内容各占一个文件', () async {
      final Uint8List a = _bytesOf('第一份内容');
      final Uint8List b = _bytesOf('第二份内容');

      final String refA = await store.save(a, ext: 'txt');
      final String refB = await store.save(b, ext: 'txt');

      expect(refA, isNot(refB));
      expect(allFiles().length, 2);
      expect(await store.totalBytes(), a.length + b.length);
    });
  });

  group('引用格式', () {
    test('引用 = sha256 小写 hex + 归一化扩展名，落在前 2 位前缀目录里', () async {
      final Uint8List data = _bytesOf('格式检查');
      final String ref = await store.save(data, ext: '.PNG');

      expect(ref, '${sha256.convert(data)}.png', reason: '引用就是内容的 sha256，不另造 id');
      expect(
        RegExp(r'^[0-9a-f]{64}\.[a-z0-9]+$').hasMatch(ref),
        isTrue,
        reason: '64 位小写 hex + . + 扩展名，格式必须固定',
      );

      final File onDisk = File(
        path.join(attachmentsDir().path, ref.substring(0, 2), ref),
      );
      expect(
        onDisk.existsSync(),
        isTrue,
        reason: '落盘路径必须是 attachments/<sha 前 2 位>/<sha256>.<ext>',
      );
      expect(store.shardOf(ref), ref.substring(0, 2));
    });

    test('扩展名统一小写纯字母数字，空则 bin', () async {
      final Uint8List data = _bytesOf('扩展名归一化');

      expect(await store.save(data, ext: 'JPG'), endsWith('.jpg'));
      expect(await store.save(data, ext: 'jp!g'), endsWith('.jpg'));
      expect(await store.save(data, ext: '  '), endsWith('.bin'));
      expect(await store.save(data, ext: ''), endsWith('.bin'));
    });
  });

  group('读取', () {
    test('read 读回的字节与写入完全一致', () async {
      final Uint8List data = Uint8List.fromList(
        List<int>.generate(4096, (int i) => (i * 7) % 256),
      );
      final String ref = await store.save(data, ext: 'bin');

      final Uint8List? back = await store.read(ref);
      expect(back, isNotNull);
      expect(back, data);
      expect(await store.exists(ref), isTrue);
    });

    test('读不到就返回 null，不抛异常（文件被删/换机/坏引用）', () async {
      final Uint8List data = _bytesOf('待会儿要被删掉的文件');
      final String ref = await store.save(data, ext: 'txt');

      // 1) 文件被用户/清理工具删掉
      File(
        path.join(attachmentsDir().path, store.shardOf(ref), ref),
      ).deleteSync();
      expect(await store.read(ref), isNull);
      expect(await store.exists(ref), isFalse);

      // 2) 从来就不存在的引用
      final String missingRef = '${List<String>.filled(64, '0').join()}.bin';
      expect(await store.read(missingRef), isNull);
      expect(await store.read(''), isNull);

      // 3) 坏引用（导入的 JSON 被人手改过）：不允许变成路径穿越
      expect(await store.read('../../settings/hive.txt'), isNull);
      expect(await store.exists('../attachments'), isFalse);

      // 4) 目录整个不存在（全新的机器）
      await attachmentsDir().delete(recursive: true);
      expect(await store.read(ref), isNull);
      expect(await store.listRefs(), isEmpty);
      expect(await store.totalBytes(), 0);
    });
  });

  group('列举与删除', () {
    test('listRefs 与实际文件一一对应；delete 之后 exists 为 false', () async {
      final Uint8List a = _bytesOf('a');
      final Uint8List b = _bytesOf('b');
      final String refA = await store.save(a, ext: 'txt');
      final String refB = await store.save(b, ext: 'txt');

      final List<String> onDisk = attachmentsDir()
          .listSync(recursive: true)
          .whereType<File>()
          .map((File f) => path.basename(f.path))
          .toList()
        ..sort();
      expect((await store.listRefs())..sort(), onDisk, reason: '列举结果必须和磁盘一致');

      await store.delete(refA);
      expect(await store.exists(refA), isFalse);
      expect(await store.read(refA), isNull);
      expect(await store.listRefs(), <String>[refB]);
      expect(await store.totalBytes(), b.length);

      // 删不存在 / 删坏引用都不报错（GC 会重复调用）
      await store.delete(refA);
      await store.delete('不是引用');
    });
  });

  group('原子写入', () {
    test('写完目录里只有正式文件，没有 .part 残片', () async {
      final Uint8List data = _bytesOf('原子写' * 200);
      final String ref = await store.save(data, ext: 'txt');

      expect(
        allFiles().where((String p) => p.endsWith('.part')),
        isEmpty,
        reason: '.part 只该在写入途中存在，rename 之后不能残留',
      );
      expect(allFiles(), <String>[path.join(ref.substring(0, 2), ref)]);
      // 前缀目录下只有正式文件，没有别的临时名字
      final Directory shard = Directory(
        path.join(attachmentsDir().path, ref.substring(0, 2)),
      );
      expect(
        shard.listSync().whereType<File>().map((File f) => path.basename(f.path)),
        <String>[ref],
      );
      // 存第二次（命中已存在）不产生任何新文件
      await store.save(data, ext: 'txt');
      expect(allFiles().length, 1);
    });

    test('并发存同一份内容：都拿到同一个引用，只留一个文件、不留 .part', () async {
      // 真实场景：用户连点两下发送、或回溯重填与输入区同时存同一张图。
      // 共用一个 `.part` 名字时，并发写会互相抢 rename —— 实现必须把
      // 「对手已经先 rename 走、正式文件已在」当成成功，而不是抛异常。
      final Uint8List data = _bytesOf('并发存同一份内容' * 500);

      final List<String> refs = await Future.wait(<Future<String>>[
        for (int i = 0; i < 8; i++) store.save(data, ext: 'txt'),
      ]);

      expect(refs.toSet().length, 1, reason: '同一份内容只能有一个引用');
      expect(
        allFiles().where((String p) => p.endsWith('.part')),
        isEmpty,
        reason: '并发写不能留下 .part 残片',
      );
      expect(allFiles().length, 1);
      expect(await store.read(refs.first), data);
    });
  });

  group('上限常量（其他地方按它写代码）', () {
    test('数值与产品约定一致', () {
      expect(kMaxAttachmentsPerMessage, 3);
      expect(kMaxAttachmentBytes, 20 * 1024 * 1024);
      expect(kMaxImageBytes, 5 * 1024 * 1024);
      expect(kMaxTextChars, 200000);
    });
  });
}
