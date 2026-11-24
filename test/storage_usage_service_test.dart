import 'dart:convert';
import 'dart:io';

import 'package:dna/pages/settings/storage_texts_zh.dart';
import 'package:dna/services/storage_usage_service.dart';
import 'package:dna/pages/settings/storage_labels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

/// 存储占用盘点的聚合逻辑。
///
/// 全部在临时目录里造假数据：不碰真实用户目录、不读 Hive、不起子进程
/// （磁盘空间也注入假的）。断言的是**口径**：
///
/// 1. 七个分类固定、顺序固定，分类字节数 = 该类所有明细之和；
/// 2. 总占用 = 七类之和 = 本应用自己写的那些文件的实际字节数
///    （用户自己在「文档」里放的文件**不算**）；
/// 3. 角色卡的图片/音乐要并到同一个人身上，认不出来的退回文件名；
/// 4. Hive 文件里不属于任何一条记录的部分单独成一项，不许悄悄摊给某条内容；
/// 5. 每类明细按大小降序、最多 50 条，但分类字节数仍按截断前的总数算。

/// 假的记录来源：直接给一份 [StorageRecords]。
class _FakeRecords implements StorageRecordsSource {
  _FakeRecords(this.records);

  final StorageRecords records;

  @override
  Future<StorageRecords> load() async => records;
}

/// 读库直接失败（模拟 Hive 打不开）。
class _BrokenRecords implements StorageRecordsSource {
  @override
  Future<StorageRecords> load() async => throw StateError('box 打不开');
}

/// 附件引用（真实格式是 64 位小写 hex + 扩展名）。
String _ref(String shard, String ext) =>
    '$shard${List<String>.generate(64 - shard.length, (int _) => 'c').join()}'
    '.$ext';

const StorageTextsZh _texts = StorageTextsZh();

/// 纯函数都要措辞（文本由页面侧提供）：测试里统一注入中文实现，
/// 这样断言仍然比对中文串，与「服务不再持有文案」互不影响。
ConversationRecordParse? _parseConv(String raw, Map<String, String> names) =>
    parseConversationRecord(raw, names, texts: _texts);

StorageDataRecord? _charRec(String raw) =>
    characterRecordFromJson(raw, texts: _texts);

StorageDataRecord? _worldRec(String raw) =>
    worldRecordFromJson(raw, texts: _texts);

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dna_storage_usage_');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// 往临时目录里写一个指定大小的文件（内容无所谓，只看字节数）。
  Future<void> writeFile(String relativePath, int bytes) async {
    final File file = File(path.join(temp.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(bytes, 65), flush: true);
  }

  /// 按本应用的真实目录布局造一套假数据。
  ///
  /// 各目录/box 的字节数（后面断言的期望值都从这里来）：
  /// * tas/：图片 2000+1000、音乐 5000、孤儿 300、认不出的 100 = 8400
  /// * tas.hive：900（其中记录 JSON 800，索引开销 100）
  /// * conversations.hive：7000（记录 JSON 1000+2000+3000=6000，开销 1000）
  /// * worlds.hive：500（记录 JSON 500，无开销）
  /// * tts_models/：1000+500、tts_cache/：700+300
  /// * attachments/：400（能对上原名）+200（对不上）、dna_backups/：900
  /// * identities.hive：120、settings.hive：80、sherpa_models/：50
  /// * 另外在根上放一个 999999 字节的 user-notes.txt：**不能被算进去**
  Future<StorageRecords> buildFixture() async {
    await writeFile('tas/ta-1_avatar_1700000000000000.jpg', 2000);
    await writeFile('tas/music_ta-1.mp3', 5000);
    await writeFile('tas/ta-2_cover_1700000000000001.png', 1000);
    await writeFile('tas/orphan_1.jpg', 300);
    await writeFile('tas/weirdfile.jpg', 100);

    await writeFile('tts_models/dvae.onnx', 1000);
    await writeFile('tts_models/tokenizer/tokenizer.json', 500);

    await writeFile('tts_cache/aaa.f32', 700);
    await writeFile('tts_cache/bbb.f32', 300);

    await writeFile(path.join('attachments', 'ab', _ref('ab', 'png')), 400);
    await writeFile(path.join('attachments', 'cd', 'unknown.bin'), 200);

    await writeFile('dna_backups/auto_backup_2026-11-21.zip', 900);
    await writeFile('sherpa_models/old_model.bin', 50);

    await writeFile('conversations.hive', 7000);
    await writeFile('tas.hive', 900);
    await writeFile('worlds.hive', 500);
    await writeFile('identities.hive', 120);
    await writeFile('settings.hive', 80);

    // 用户自己放在「文档」里的东西 —— 与软件占用无关。
    await writeFile('user-notes.txt', 999999);

    return StorageRecords(
      conversations: <StorageDataRecord>[
        const StorageDataRecord(
          name: '和小艾的对话',
          bytes: 3000,
          note: '128 条消息',
        ),
        const StorageDataRecord(name: '和阿七的对话', bytes: 2000, note: '40 条消息'),
        const StorageDataRecord(
          name: '群聊「夜间电台」',
          bytes: 1000,
          note: '群聊 · 12 条消息',
        ),
      ],
      characters: <StorageDataRecord>[
        const StorageDataRecord(name: '小艾', bytes: 600, ownerId: 'ta-1'),
        const StorageDataRecord(name: '阿七', bytes: 200, ownerId: 'ta-2'),
      ],
      worlds: <StorageDataRecord>[
        const StorageDataRecord(name: '夜航世界', bytes: 500, ownerId: 'w-1'),
      ],
      attachmentNames: <String, String>{_ref('ab', 'png'): '猫.png'},
    );
  }

  StorageUsageService buildService({
    StorageRecordsSource? records,
    StorageDiskSpace? disk,
  }) {
    return StorageUsageService(texts: const StorageTextsZh(), 
      documentsPath: () async => temp.path,
      recordsSource: records ?? _FakeRecords(const StorageRecords()),
      diskSpaceReader: (String _) async => disk,
    );
  }

  group('分类聚合', () {
    late StorageUsageReport report;
    late StorageRecords fixture;

    setUp(() async {
      fixture = await buildFixture();
      report = await buildService(
        records: _FakeRecords(fixture),
        disk: const StorageDiskSpace(
          totalBytes: 100000,
          freeBytes: 40000,
          label: 'D:',
        ),
      ).scan();
    });

    test('七类固定、顺序固定', () {
      expect(
        report.categories.map((StorageCategoryUsage c) => c.category).toList(),
        StorageCategory.values,
      );
    });

    test('会话类 = 每条会话的 JSON + box 文件里的索引开销', () {
      final StorageCategoryUsage usage = report.usageOf(
        StorageCategory.conversations,
      );
      // 6000 的记录 + 1000 的索引开销 = 7000（等于 conversations.hive 的大小）
      expect(usage.bytes, 7000);
      expect(usage.itemCount, 4);
      expect(usage.items.take(2).map((StorageUsageItem i) => i.name), <String>[
        '和小艾的对话',
        '和阿七的对话',
      ]);
      expect(usage.items[3].name, '群聊「夜间电台」');
      expect(usage.items[1].note, '40 条消息');
      // 索引开销单独成一项（1000 字节，和「群聊」并列时按名称排在前面）。
      final StorageUsageItem overhead = usage.items.firstWhere(
        (StorageUsageItem i) => i.name.contains('索引与空闲空间'),
      );
      expect(overhead.bytes, 1000);
      expect(overhead.name, contains('conversations.hive'));
    });

    test('角色卡类按人合并：资料 + 图片 + 音乐落到同一行', () {
      final StorageCategoryUsage usage = report.usageOf(
        StorageCategory.characters,
      );
      // 8400 的文件 + 800 的记录 + 100 的索引开销 = 9300
      expect(usage.bytes, 9300);
      expect(usage.items.first.name, '小艾');
      expect(usage.items.first.bytes, 600 + 2000 + 5000);
      expect(usage.items.first.note, '图片 1 张 · 背景音乐 1 首 · 资料 600 B');
      expect(usage.items[1].name, '阿七');
      expect(usage.items[1].bytes, 200 + 1000);
      expect(usage.items[1].note, '图片 1 张 · 资料 200 B');
    });

    test('认不出归属的角色目录文件退回文件名，不硬塞给某个角色', () {
      final List<StorageUsageItem> items = report
          .usageOf(StorageCategory.characters)
          .items;
      final StorageUsageItem orphan = items.firstWhere(
        (StorageUsageItem i) => i.name == 'orphan_1.jpg',
      );
      expect(orphan.bytes, 300);
      expect(orphan.note, '找不到对应的角色卡');
      final StorageUsageItem unknown = items.firstWhere(
        (StorageUsageItem i) => i.name == 'weirdfile.jpg',
      );
      expect(unknown.note, '认不出属于哪个角色');
    });

    test('世界类只有记录本身，没有文件就不凭空加项', () {
      final StorageCategoryUsage usage = report.usageOf(
        StorageCategory.worlds,
      );
      expect(usage.bytes, 500);
      expect(usage.itemCount, 1);
      expect(usage.items.single.name, '夜航世界');
    });

    test('缓存类聚成一条（文件名是 sha1，不给用户看哈希）', () {
      final StorageCategoryUsage usage = report.usageOf(StorageCategory.cache);
      expect(usage.bytes, 1000);
      expect(usage.items.single.name, '合成语音缓存（2 个音频）');
    });

    test('下载类按文件给模型名，按大小降序', () {
      final StorageCategoryUsage usage = report.usageOf(
        StorageCategory.downloads,
      );
      expect(usage.bytes, 1500);
      expect(usage.items.map((StorageUsageItem i) => i.name).toList(), <String>[
        'dvae.onnx',
        path.join('tokenizer', 'tokenizer.json'),
      ]);
    });

    test('附件类能对上消息里的附件就用原名，对不上就用哈希文件名', () {
      final StorageCategoryUsage usage = report.usageOf(
        StorageCategory.attachments,
      );
      expect(usage.bytes, 600);
      expect(usage.items.first.name, '猫.png');
      expect(usage.items.first.bytes, 400);
      expect(usage.items.first.note, '聊天附件');
      expect(usage.items[1].name, 'unknown.bin');
      expect(usage.items[1].note, '附件（只有哈希名）');
    });

    test('其他类：备份 + 身份/设置库 + 旧版残留', () {
      final StorageCategoryUsage usage = report.usageOf(StorageCategory.other);
      expect(usage.bytes, 900 + 120 + 80 + 50);
      expect(
        usage.items.map((StorageUsageItem i) => i.name).toList(),
        containsAll(<String>[
          'auto_backup_2026-11-21.zip',
          '身份数据（identities.hive）',
          '设置数据（settings.hive）',
          '旧版语音输入模型（已废弃）',
        ]),
      );
    });

    test('分类字节数 = 该类明细之和（截断前）', () {
      for (final StorageCategoryUsage usage in report.categories) {
        expect(
          usage.bytes,
          usage.items.fold<int>(
            0,
            (int sum, StorageUsageItem i) => sum + i.bytes,
          ),
          reason:
              '分类 ${storageCategoryLabel(usage.category)} 的字节数与明细之和不一致',
        );
      }
    });

    test('总占用 = 七类之和 = 本应用自己写的文件字节数', () {
      const int expected =
          7000 + // conversations.hive
          9300 + // tas.hive + tas/
          500 + // worlds.hive
          1000 + // tts_cache/
          1500 + // tts_models/
          600 + // attachments/
          1150; // dna_backups/ + identities/settings + sherpa_models/
      expect(report.totalBytes, expected);
      expect(
        report.categories.fold<int>(
          0,
          (int sum, StorageCategoryUsage c) => sum + c.bytes,
        ),
        expected,
      );
    });

    test('用户自己放在文档目录里的文件不算进来', () {
      // 根上那个 999999 字节的 user-notes.txt 必须一分不加。
      expect(report.totalBytes, lessThan(999999));
      for (final StorageCategoryUsage usage in report.categories) {
        for (final StorageUsageItem item in usage.items) {
          expect(item.name, isNot('user-notes.txt'));
        }
      }
    });

    test('磁盘容量注入什么就报什么，不自己算总量', () {
      expect(report.disk, isNotNull);
      expect(report.disk!.totalBytes, 100000);
      expect(report.disk!.freeBytes, 40000);
      expect(report.disk!.usedBytes, 60000);
      expect(report.disk!.label, 'D:');
    });
  });

  group('截断与排序', () {
    test('每类最多 50 条，但分类字节数按全部 60 条算', () async {
      final StorageRecords records = StorageRecords(
        conversations: <StorageDataRecord>[
          for (int i = 1; i <= 60; i++)
            StorageDataRecord(name: '会话 $i', bytes: i),
        ],
      );
      final StorageUsageReport report = await buildService(
        records: _FakeRecords(records),
      ).scan();
      final StorageCategoryUsage usage = report.usageOf(
        StorageCategory.conversations,
      );
      expect(usage.itemCount, 60);
      expect(usage.items.length, 50);
      expect(usage.truncated, isTrue);
      // 1+2+...+60
      expect(usage.bytes, 1830);
      expect(usage.items.first.name, '会话 60');
      expect(usage.items.last.name, '会话 11');
    });

    test('明细按字节数降序（同名时按名称兜底，保证顺序稳定）', () async {
      final StorageRecords records = StorageRecords(
        worlds: <StorageDataRecord>[
          const StorageDataRecord(name: '甲', bytes: 10),
          const StorageDataRecord(name: '乙', bytes: 30),
          const StorageDataRecord(name: '丙', bytes: 20),
        ],
      );
      final StorageUsageReport report = await buildService(
        records: _FakeRecords(records),
      ).scan();
      expect(
        report
            .usageOf(StorageCategory.worlds)
            .items
            .map((StorageUsageItem i) => i.name)
            .toList(),
        <String>['乙', '丙', '甲'],
      );
    });
  });

  group('失败与缺信息', () {
    test('读库失败：不抛异常，但要留下原因，文件部分照常统计', () async {
      await writeFile('tts_models/dvae.onnx', 1000);
      await writeFile('conversations.hive', 400);
      final StorageUsageReport report = await buildService(
        records: _BrokenRecords(),
      ).scan();
      expect(report.recordsError, isNotNull);
      expect(report.recordsError, contains('读取本地数据库失败'));
      // 会话类只剩 box 文件的固定开销，明细为空。
      final StorageCategoryUsage conversations = report.usageOf(
        StorageCategory.conversations,
      );
      expect(conversations.bytes, 400);
      expect(conversations.items.single.name, contains('索引与空闲空间'));
      // 文件系统那部分不受影响。
      expect(report.usageOf(StorageCategory.downloads).bytes, 1000);
    });

    test('拿不到应用目录（Web）：不扫文件，只有记录，磁盘未知', () async {
      final StorageUsageReport report = await StorageUsageService(texts: const StorageTextsZh(), 
        documentsPath: () async => null,
        recordsSource: _FakeRecords(
          const StorageRecords(
            worlds: <StorageDataRecord>[
              StorageDataRecord(name: '夜航世界', bytes: 700),
            ],
          ),
        ),
        diskSpaceReader: (String _) async => null,
      ).scan();
      expect(report.filesScanned, isFalse);
      expect(report.disk, isNull);
      expect(report.usageOf(StorageCategory.worlds).bytes, 700);
      expect(report.usageOf(StorageCategory.downloads).bytes, 0);
      expect(report.usageOf(StorageCategory.downloads).itemCount, 0);
    });

    test('磁盘容量拿不到：disk 为 null，其余数字照旧', () async {
      await writeFile('tts_cache/aaa.f32', 100);
      final StorageUsageReport report = await buildService().scan();
      expect(report.disk, isNull);
      expect(report.usageOf(StorageCategory.cache).bytes, 100);
    });
  });

  group('纯函数', () {
    test('会话标题：群聊用群名，单聊用角色名，认不出写「未命名对话」', () {
      final Map<String, String> names = <String, String>{'ta-1': '小艾'};
      final ConversationRecordParse group =
          _parseConv(
            jsonEncode(<String, Object>{
              'isGroup': true,
              'groupName': '夜间电台',
              'messages': <Object>[
                <String, Object>{'id': 'm1'},
              ],
            }),
            names,
          )!;
      expect(group.record.name, '夜间电台');
      expect(group.record.note, '群聊 · 1 条消息');

      final ConversationRecordParse solo =
          _parseConv(
            jsonEncode(<String, Object>{
              'taId': 'ta-1',
              'messages': <Object>[],
              'summaries': <Object>[
                <String, Object>{'id': 's1'},
              ],
            }),
            names,
          )!;
      expect(solo.record.name, '小艾');
      expect(solo.record.note, '0 条消息 · 1 段摘要');

      final ConversationRecordParse unknown = _parseConv(
        '{"taId":"ta-9"}',
        names,
      )!;
      expect(unknown.record.name, '未命名对话');
    });

    test('会话里的附件能还原出原始文件名；坏 JSON 返回 null', () {
      final ConversationRecordParse parsed =
          _parseConv(
            jsonEncode(<String, Object>{
              'taId': 'ta-1',
              'messages': <Object>[
                <String, Object>{
                  'attachments': <Object>[
                    <String, Object>{'ref': 'abc.png', 'name': '猫.png'},
                  ],
                },
              ],
            }),
            <String, String>{},
          )!;
      expect(parsed.attachmentNames, <String, String>{'abc.png': '猫.png'});
      expect(_parseConv('这不是 JSON', <String, String>{}), isNull);
    });

    test('角色卡 / 世界卡的名称与归属 id', () {
      expect(
        _charRec('{"id":"ta-1","name":"小艾"}')!.name,
        '小艾',
      );
      expect(
        _charRec('{"id":"ta-1","name":"小艾"}')!.ownerId,
        'ta-1',
      );
      expect(_worldRec('{"id":"w-1"}')!.name, '未命名世界');
      expect(_charRec('[]'), isNull);
    });

    test('从文件名解析角色 id：图片与背景音乐两种命名', () {
      expect(
        taIdFromImageFileName('ta-1_avatar_1700000000000000.jpg'),
        'ta-1',
      );
      expect(taIdFromImageFileName('music_ta-1.mp3'), 'ta-1');
      expect(taIdFromImageFileName('weirdfile.jpg'), isNull);
      expect(taIdFromImageFileName('music_.mp3'), isNull);
      expect(isMusicFileName('music_ta-1.mp3'), isTrue);
      expect(isMusicFileName('ta-1_avatar_1.jpg'), isFalse);
    });

    test('字节数格式化', () {
      expect(formatStorageBytes(0), '0 B');
      expect(formatStorageBytes(999), '999 B');
      expect(formatStorageBytes(1024), '1.0 KB');
      expect(formatStorageBytes(1024 * 1024), '1.0 MB');
      expect(formatStorageBytes(621 * 1024), '621 KB');
      expect(formatStorageBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });
}
