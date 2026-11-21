import 'dart:io';

import 'package:dna/services/storage_usage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// 回归：应用启动后 box 已经以 `Box<String>` 开着，此时盘点再去
/// `openBox<dynamic>`（或 `Hive.box<dynamic>`）会抛 HiveError
/// 「The box "tas" is already open and of type Box&lt;String&gt;」——
/// 存储空间页当场报「读取本地数据库失败」。
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dna_hive_test_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('box 已被应用以 Box<String> 打开时，盘点直接复用、不抛错', () async {
    final Box<String> box = await Hive.openBox<String>('tas');
    await box.put('ta1', '{"id":"ta1","name":"林夏","images":{}}');

    final HiveStorageRecordsSource source = HiveStorageRecordsSource(
      conversationsBox: 'no_such_conversations',
      charactersBox: 'tas',
      worldsBox: 'no_such_worlds',
    );

    late StorageRecords records;
    await expectLater(
      source.load().then((StorageRecords r) => records = r),
      completes,
      reason: '已开的 box 不该再被 openBox<dynamic> 打开',
    );
    expect(records.characters, hasLength(1));
    expect(records.characters.first.name, contains('林夏'));
    expect(records.unreadable, 0);
  });

  test('box 没开过但文件存在时也能读（走 openBox 分支）', () async {
    final Box<String> box = await Hive.openBox<String>('worlds');
    await box.put('w1', '{"id":"w1","name":"雾港"}');
    await Hive.close();

    Hive.init(dir.path);
    final HiveStorageRecordsSource source = HiveStorageRecordsSource(
      conversationsBox: 'no_such_conversations',
      charactersBox: 'no_such_tas',
      worldsBox: 'worlds',
    );
    final StorageRecords records = await source.load();
    expect(records.worlds, hasLength(1));
    expect(records.worlds.first.name, contains('雾港'));
  });
}
