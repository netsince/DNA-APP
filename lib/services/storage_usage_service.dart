/// 存储占用盘点服务：**只负责算，不负责画**。
///
/// 页面（pages/settings/storage_settings_page.dart）拿 [StorageUsageService.scan]
/// 的结果渲染；这里不含任何 Widget。
///
/// ## 分类口径（改这里之前先想清楚「这条字节到底落在哪个目录/哪个 box」）
///
/// | 分类 | 算什么 |
/// |---|---|
/// | 会话类 | Hive conversations box 里每条会话的 JSON 字节（按会话聚合）+ 该 box 文件里不属于任何一条记录的索引开销 |
/// | 角色卡类 | Hive tas box 里每个角色的 JSON 字节 + `<doc>/tas/` 下属于它的图片与背景音乐 |
/// | 世界类 | Hive worlds box 里每张世界卡的 JSON 字节 + 该 box 的索引开销 |
/// | 缓存类 | `<doc>/tts_cache/`（合成语音的音频缓存） |
/// | 下载类 | `<doc>/tts_models/`（端侧 TTS 模型文件，按文件给名字） |
/// | 附件类 | `<doc>/attachments/`（聊天附件，内容寻址；盘上文件名是 sha256，能对上消息里的附件时显示原始文件名） |
/// | 其他类 | 身份/设置的 Hive 文件、`<doc>/dna_backups/`（导入替换前与删卡时的自动备份）、旧版残留目录 |
///
/// ## 三条不变量
///
/// 1. **分类字节数 = 该分类所有明细之和**（明细本身由扫描结果给出，不另算）。
///    所以「总占用」也等于七类之和 —— 页面上写的数与明细里加起来对得上。
/// 2. **不遍历文档目录本身**。Windows 上 getApplicationDocumentsDirectory()
///    返回的是**用户共用的「文档」文件夹**，全量遍历会把用户自己的文件算成
///    「软件占用」（那是最坏的谎话）。所以只认本应用写过的固定目录名。
/// 3. **拿不到的就不编**。磁盘总量/剩余拿不到时 [StorageDiskSpace] 为 null 或
///    字段为 null，页面写「未知」，绝不按「已用 × 某个系数」猜一个总量。
///
/// ## 为什么读 Hive 要单独抽一层
///
/// 明细里的「会话标题 + 条数」「角色名」只能从 box 里的 JSON 解出来；而单测要
/// 在临时目录里造假数据、不能碰真实用户目录，所以 [StorageRecordsSource] 是
/// 可注入的接口（[HiveStorageRecordsSource] 是真实实现）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 每类明细最多保留的条数（页面只展示这么多，超出部分只在 itemCount 里体现）。
const int kStorageItemsPerCategory = 50;

/// 磁盘容量查询的超时。查不到就当没有 —— 一个设置页不该被一条命令吊死。
const Duration kDiskSpaceTimeout = Duration(seconds: 3);

/// 存储占用的七个分类。
///
/// 固定七类、固定顺序：分类是**口径**而不是「发现什么就列什么」，
/// 少一类就会有一块字节无处安放，页面上的占比之和就对不上 100%。
enum StorageCategory {
  conversations,
  characters,
  worlds,
  cache,
  downloads,
  attachments,
  other,
}

/// 分类的显示名（界面与明细页标题共用）。
String storageCategoryLabel(StorageCategory category) => switch (category) {
  StorageCategory.conversations => '会话',
  StorageCategory.characters => '角色卡',
  StorageCategory.worlds => '世界',
  StorageCategory.cache => '缓存',
  StorageCategory.downloads => '下载',
  StorageCategory.attachments => '附件',
  StorageCategory.other => '其他',
};

/// 分类下面的一行（明细页的一项）。
class StorageUsageItem {
  const StorageUsageItem({required this.name, required this.bytes, this.note});

  /// 人能看懂的名字：会话标题 / 角色名 / 模型文件名 / 附件原名…
  ///
  /// 认不出来的一律退回文件名 —— **不编造**「角色 A 的立绘」这种名字。
  final String name;

  final int bytes;

  /// 补充说明（「128 条消息」「图片 2 张 · 音乐 1 首」这类）。
  final String? note;

  @override
  String toString() => 'StorageUsageItem($name, $bytes, $note)';
}

/// 一个分类的盘点结果。
class StorageCategoryUsage {
  const StorageCategoryUsage({
    required this.category,
    required this.bytes,
    required this.items,
    required this.itemCount,
  });

  final StorageCategory category;

  /// 分类总字节数（**截断前**所有明细之和）。
  final int bytes;

  /// 明细，按字节数降序，最多 [kStorageItemsPerCategory] 条。
  final List<StorageUsageItem> items;

  /// 截断前的条目总数。
  final int itemCount;

  /// 明细是否被截断（页面据此提示「还有 N 项没显示」）。
  bool get truncated => itemCount > items.length;
}

/// 磁盘容量信息。拿不到的字段一律 null（页面写「未知」）。
class StorageDiskSpace {
  const StorageDiskSpace({this.totalBytes, this.freeBytes, this.label});

  /// 磁盘总容量。null = 这台设备/这个平台拿不到。
  final int? totalBytes;

  /// 磁盘剩余。null = 拿不到。
  final int? freeBytes;

  /// 这是哪个盘符/挂载点（如 D:、/），仅用于文案。
  final String? label;

  /// 能不能算「已用 / 总量」这个比例。
  bool get hasTotal => totalBytes != null && totalBytes! > 0;

  /// 已用字节数（拿不到总量或剩余时返回 null）。
  int? get usedBytes {
    if (!hasTotal || freeBytes == null) return null;
    return totalBytes! - freeBytes!;
  }
}

/// 一次盘点的结果。
class StorageUsageReport {
  const StorageUsageReport({
    required this.categories,
    required this.totalBytes,
    required this.scannedAt,
    this.disk,
    this.recordsError,
    this.filesScanned = true,
    this.unreadableRecords = 0,
  });

  /// 七个分类，顺序同 [StorageCategory.values]。
  final List<StorageCategoryUsage> categories;

  /// 本应用占用的总字节数（七类之和）。
  final int totalBytes;

  /// 盘点时间（页面显示出来，让用户知道这个数会过时）。
  final DateTime scannedAt;

  /// 磁盘容量；null = 拿不到（页面写「未知」）。
  final StorageDiskSpace? disk;

  /// 读本地数据库失败时的原因。
  ///
  /// 不为 null 时页面必须**明确提示**：这时会话/角色卡/世界三类只剩
  /// Hive 文件的固定开销，明细是空的 —— 静默展示一个偏小的数字比报错更坏。
  final String? recordsError;

  /// 是否真的扫了文件系统（Web 为 false：浏览器里拿不到应用目录）。
  final bool filesScanned;

  /// 有记录读不出来（JSON 坏了）的条数。
  final int unreadableRecords;

  /// 按分类取结果（页面渲染、测试断言都走这里）。
  StorageCategoryUsage usageOf(StorageCategory category) =>
      categories.firstWhere((StorageCategoryUsage c) => c.category == category);
}

/// 一条「数据库记录」的用量（会话 / 角色卡 / 世界卡都长这样）。
class StorageDataRecord {
  const StorageDataRecord({
    required this.name,
    required this.bytes,
    this.ownerId,
    this.note,
  });

  /// 显示名。
  final String name;

  /// 序列化后（也就是 Hive 里存的那个字符串）的 UTF-8 字节数。
  final int bytes;

  /// 归属 id（角色卡用它把 tas/ 下的图片/音乐并进同一个人）。
  final String? ownerId;

  /// 补充说明（「128 条消息」）。
  final String? note;

  @override
  String toString() =>
      'StorageDataRecord($name, $bytes, $ownerId, $note)';
}

/// 从本地数据库读出来的全部记录。
class StorageRecords {
  const StorageRecords({
    this.conversations = const <StorageDataRecord>[],
    this.characters = const <StorageDataRecord>[],
    this.worlds = const <StorageDataRecord>[],
    this.attachmentNames = const <String, String>{},
    this.unreadable = 0,
  });

  final List<StorageDataRecord> conversations;
  final List<StorageDataRecord> characters;
  final List<StorageDataRecord> worlds;

  /// 附件的「内容引用 → 原始文件名」（`<sha256>.<ext>` → `猫.png`）。
  ///
  /// 附件是按内容寻址存盘的，盘上的文件名是哈希；只有从消息数据里才能还原
  /// 出人看得懂的名字。找不到就退回哈希文件名，不猜。
  final Map<String, String> attachmentNames;

  /// 解析失败的记录条数（JSON 损坏等）。不为 0 时页面会提示。
  final int unreadable;
}

/// 记录来源。真实实现读 Hive；测试注入假数据。
abstract class StorageRecordsSource {
  Future<StorageRecords> load();
}

/// 读真实 Hive box 的实现。
///
/// 每个 box 都会先查 boxExists 再打开 —— 只是看一眼设置页不该凭空建出几个
/// 空 box 文件（那会让下一次盘点多出几项来路不明的占用）。
class HiveStorageRecordsSource implements StorageRecordsSource {
  HiveStorageRecordsSource({
    this.conversationsBox = 'conversations',
    this.charactersBox = 'tas',
    this.worldsBox = 'worlds',
  });

  final String conversationsBox;
  final String charactersBox;
  final String worldsBox;

  @override
  Future<StorageRecords> load() async {
    int unreadable = 0;

    // 先读角色卡：非群聊会话的标题要用角色名。
    final Map<String, String> characterNames = <String, String>{};
    final List<StorageDataRecord> characters = <StorageDataRecord>[];
    for (final String raw in await _readStrings(charactersBox)) {
      final StorageDataRecord? record = characterRecordFromJson(raw);
      if (record == null) {
        unreadable++;
        continue;
      }
      characters.add(record);
      if (record.ownerId != null) characterNames[record.ownerId!] = record.name;
    }

    final List<StorageDataRecord> worlds = <StorageDataRecord>[];
    for (final String raw in await _readStrings(worldsBox)) {
      final StorageDataRecord? record = worldRecordFromJson(raw);
      if (record == null) {
        unreadable++;
        continue;
      }
      worlds.add(record);
    }

    final List<StorageDataRecord> conversations = <StorageDataRecord>[];
    final Map<String, String> attachmentNames = <String, String>{};
    for (final String raw in await _readStrings(conversationsBox)) {
      final ConversationRecordParse? parsed = parseConversationRecord(
        raw,
        characterNames,
      );
      if (parsed == null) {
        unreadable++;
        continue;
      }
      conversations.add(parsed.record);
      attachmentNames.addAll(parsed.attachmentNames);
    }

    return StorageRecords(
      conversations: conversations,
      characters: characters,
      worlds: worlds,
      attachmentNames: attachmentNames,
      unreadable: unreadable,
    );
  }

  /// 读出某个 box 里所有字符串值（逐条读，不一次性把整个 box 拉进内存）。
  Future<List<String>> _readStrings(String boxName) async {
    if (!await Hive.boxExists(boxName)) return const <String>[];
    final Box<dynamic> box = await Hive.openBox<dynamic>(boxName);
    final List<String> out = <String>[];
    for (final Object? key in box.keys) {
      final Object? value = box.get(key);
      if (value is String) out.add(value);
    }
    return out;
  }
}

/// 会话 JSON 解析结果：一条明细 + 其中出现的附件名。
class ConversationRecordParse {
  const ConversationRecordParse({
    required this.record,
    required this.attachmentNames,
  });

  final StorageDataRecord record;

  /// 附件「引用 → 原始文件名」。
  final Map<String, String> attachmentNames;
}

/// 纯函数：一条会话 JSON → 明细（标题 + 条数 + 字节数）+ 附件名。
///
/// 单独抽出来是为了能直接测「标题怎么来、条数怎么写」，不用起 Hive。
/// 解析不出对象时返回 null（调用方计一条「读不出来的记录」）。
ConversationRecordParse? parseConversationRecord(
  String raw,
  Map<String, String> characterNames,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;

  final bool isGroup = decoded['isGroup'] == true;
  final String groupName = (decoded['groupName'] as String?)?.trim() ?? '';
  final String taId = (decoded['taId'] as String?) ?? '';
  final String title = isGroup
      ? (groupName.isEmpty ? '群聊' : groupName)
      : (characterNames[taId] ?? '未命名对话');

  final int messageCount = switch (decoded['messages']) {
    List<dynamic> list => list.length,
    _ => 0,
  };
  final int summaryCount = switch (decoded['summaries']) {
    List<dynamic> list => list.length,
    _ => 0,
  };
  final List<String> noteParts = <String>[
    if (isGroup) '群聊',
    '$messageCount 条消息',
    if (summaryCount > 0) '$summaryCount 段摘要',
  ];

  final Map<String, String> attachmentNames = <String, String>{};
  final Object? messages = decoded['messages'];
  if (messages is List) {
    for (final Object? message in messages) {
      if (message is! Map) continue;
      final Object? attachments = message['attachments'];
      if (attachments is! List) continue;
      for (final Object? attachment in attachments) {
        if (attachment is! Map) continue;
        final Object? ref = attachment['ref'];
        final Object? name = attachment['name'];
        if (ref is String &&
            ref.isNotEmpty &&
            name is String &&
            name.isNotEmpty) {
          attachmentNames.putIfAbsent(ref, () => name);
        }
      }
    }
  }

  return ConversationRecordParse(
    record: StorageDataRecord(
      name: title,
      bytes: utf8ByteLength(raw),
      note: noteParts.join(' · '),
    ),
    attachmentNames: attachmentNames,
  );
}

/// 纯函数：角色卡 JSON → 明细。解析失败返回 null。
StorageDataRecord? characterRecordFromJson(String raw) {
  final Map<String, dynamic>? json = _decodeMap(raw);
  if (json == null) return null;
  final String id = (json['id'] as String?) ?? '';
  final String name = (json['name'] as String?)?.trim() ?? '';
  return StorageDataRecord(
    name: name.isEmpty ? '未命名角色' : name,
    bytes: utf8ByteLength(raw),
    ownerId: id.isEmpty ? null : id,
  );
}

/// 纯函数：世界卡 JSON → 明细。解析失败返回 null。
StorageDataRecord? worldRecordFromJson(String raw) {
  final Map<String, dynamic>? json = _decodeMap(raw);
  if (json == null) return null;
  final String id = (json['id'] as String?) ?? '';
  final String name = (json['name'] as String?)?.trim() ?? '';
  return StorageDataRecord(
    name: name.isEmpty ? '未命名世界' : name,
    bytes: utf8ByteLength(raw),
    ownerId: id.isEmpty ? null : id,
  );
}

Map<String, dynamic>? _decodeMap(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  return decoded.map(
    (Object? key, Object? value) => MapEntry<String, dynamic>('$key', value),
  );
}

/// 字节数 → 人话（「12.3 MB」）。
///
/// 页面、明细页、测试共用这一份，避免到处出现「有的写 1 位小数、有的写 2 位」。
String formatStorageBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const List<String> units = <String>['KB', 'MB', 'GB', 'TB'];
  double value = bytes / 1024;
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // 上了三位数再留一位小数就是噪音（621.4 KB → 621 KB）。
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

/// 字符数 → UTF-8 字节数。
///
/// Hive 存的就是这个 JSON 字符串，盘上占的字节数就是这个数（不含 Hive 自己的
/// 帧头与索引 —— 那部分由分类里的「索引与空闲空间」一项体现）。
int utf8ByteLength(String text) => utf8.encode(text).length;

/// 磁盘容量查询入口。拿不到一律返回 null（页面写「未知」）。
///
/// * Web：没有这个概念，直接 null。
/// * Windows：dart:io 拿不到磁盘容量，退一步问系统（PowerShell 读 DriveInfo，
///   输出是 JSON、字段名不随系统语言变）。
/// * Linux / macOS / Android：df -k -P。
/// * iOS：系统不让起子进程，会抛异常 → 退化成未知。
///
/// 任何一步失败都只意味着「这个数未知」，不影响其它分类的扫描。
Future<StorageDiskSpace?> readDiskSpace(String documentsPath) async {
  if (kIsWeb) return null;
  try {
    if (Platform.isWindows) return await _readWindowsDiskSpace(documentsPath);
    return await _readUnixDiskSpace(documentsPath);
  } catch (_) {
    return null;
  }
}

Future<StorageDiskSpace?> _readWindowsDiskSpace(String documentsPath) async {
  final String drive = _windowsDriveOf(documentsPath);
  if (drive.isEmpty) return null;
  final ProcessResult result = await Process.run('powershell.exe', <String>[
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "[System.IO.DriveInfo]::new('$drive') | "
        'Select-Object TotalSize,AvailableFreeSpace | ConvertTo-Json -Compress',
  ]).timeout(kDiskSpaceTimeout);
  if (result.exitCode != 0) return null;
  final String out = '${result.stdout}'.trim();
  if (out.isEmpty) return null;
  final Object? decoded = jsonDecode(out);
  if (decoded is! Map) return null;
  final int? total = (decoded['TotalSize'] as num?)?.toInt();
  final int? free = (decoded['AvailableFreeSpace'] as num?)?.toInt();
  if (total == null || total <= 0) return null;
  return StorageDiskSpace(totalBytes: total, freeBytes: free, label: drive);
}

/// 「D:\a\b」→「D:」；认不出盘符返回空串。
String _windowsDriveOf(String windowsPath) {
  if (windowsPath.length < 2) return '';
  final String head = windowsPath.substring(0, 2);
  if (head[1] != ':') return '';
  final String letter = head[0].toUpperCase();
  if (letter.compareTo('A') < 0 || letter.compareTo('Z') > 0) return '';
  return head;
}

Future<StorageDiskSpace?> _readUnixDiskSpace(String documentsPath) async {
  final ProcessResult result = await Process.run('df', <String>[
    '-k',
    '-P',
    documentsPath,
  ]).timeout(kDiskSpaceTimeout);
  if (result.exitCode != 0) return null;
  final List<String> lines = '${result.stdout}'
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .toList();
  if (lines.length < 2) return null;
  final List<String> fields = lines.last.split(RegExp(r'\s+'));
  // Filesystem 1024-blocks Used Available Capacity Mounted on
  if (fields.length < 4) return null;
  final int? totalKb = int.tryParse(fields[1]);
  final int? availKb = int.tryParse(fields[3]);
  if (totalKb == null || totalKb <= 0) return null;
  return StorageDiskSpace(
    totalBytes: totalKb * 1024,
    freeBytes: availKb == null ? null : availKb * 1024,
    label: fields.length > 5 ? fields.sublist(5).join(' ') : fields.last,
  );
}

/// 盘点入口。
///
/// 三个依赖全部可注入（目录、记录来源、磁盘查询），单测才能在临时目录里跑，
/// 不碰真实用户目录、也不去起子进程。
class StorageUsageService {
  StorageUsageService({
    Future<String?> Function()? documentsPath,
    StorageRecordsSource? recordsSource,
    Future<StorageDiskSpace?> Function(String documentsPath)? diskSpaceReader,
    this.itemsPerCategory = kStorageItemsPerCategory,
  }) : _documentsPath = documentsPath ?? _defaultDocumentsPath,
       _recordsSource = recordsSource ?? HiveStorageRecordsSource(),
       _diskSpaceReader = diskSpaceReader ?? readDiskSpace;

  final Future<String?> Function() _documentsPath;
  final StorageRecordsSource _recordsSource;
  final Future<StorageDiskSpace?> Function(String documentsPath)
  _diskSpaceReader;

  /// 每类保留的明细条数。
  final int itemsPerCategory;

  /// Web 没有应用目录；其它平台拿不到就抛（让页面报错 + 重试，而不是假装 0）。
  static Future<String?> _defaultDocumentsPath() async {
    if (kIsWeb) return null;
    final Directory dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// 扫一遍。
  ///
  /// 只有「文件系统扫不动」才会抛异常；读数据库失败会写进
  /// [StorageUsageReport.recordsError]，其余分类照常给结果。
  Future<StorageUsageReport> scan() async {
    final String? documentsPath = await _documentsPath();

    StorageRecords records = const StorageRecords();
    String? recordsError;
    try {
      records = await _recordsSource.load();
    } catch (error) {
      recordsError = '读取本地数据库失败：$error';
    }

    final _ScanBuilder builder = _ScanBuilder(
      itemsPerCategory: itemsPerCategory,
    );
    builder.addRecords(StorageCategory.conversations, records.conversations);
    builder.addRecords(StorageCategory.worlds, records.worlds);
    builder.addCharacters(records.characters);

    if (documentsPath != null) {
      await _scanOwnedPaths(documentsPath, builder, records.attachmentNames);
    }

    StorageDiskSpace? disk;
    if (documentsPath != null) {
      disk = await _diskSpaceReader(documentsPath);
    }

    final List<StorageCategoryUsage> categories = <StorageCategoryUsage>[
      for (final StorageCategory category in StorageCategory.values)
        builder.build(category),
    ];
    int total = 0;
    for (final StorageCategoryUsage usage in categories) {
      total += usage.bytes;
    }

    return StorageUsageReport(
      categories: categories,
      totalBytes: total,
      scannedAt: DateTime.now(),
      disk: disk,
      recordsError: recordsError,
      filesScanned: documentsPath != null,
      unreadableRecords: records.unreadable,
    );
  }

  /// 只扫本应用自己写过的目录/文件。
  ///
  /// 刻意**不**对文档目录做 Directory.list() 一把梭：见文件头不变量 2。
  Future<void> _scanOwnedPaths(
    String documentsPath,
    _ScanBuilder builder,
    Map<String, String> attachmentNames,
  ) async {
    // 1) 角色卡目录：图片（<taId>_<槽位>_<时间戳>.<ext>）与背景音乐（music_<taId>.<ext>）。
    for (final (String rel, int bytes) in await _listFiles(
      path.join(documentsPath, 'tas'),
    )) {
      builder.addCharacterFile(rel, bytes);
    }

    // 2) 端侧模型：按文件给名字（模型文件本身就叫这个名）。
    for (final (String rel, int bytes) in await _listFiles(
      path.join(documentsPath, 'tts_models'),
    )) {
      builder.addFileItem(
        StorageCategory.downloads,
        rel,
        bytes,
        note: '端侧语音模型',
      );
    }

    // 3) 语音缓存：文件名是 sha1，认不出来 —— 聚成一条，别拿哈希骗人。
    final List<(String, int)> cacheFiles = await _listFiles(
      path.join(documentsPath, 'tts_cache'),
    );
    if (cacheFiles.isNotEmpty) {
      int cacheBytes = 0;
      for (final (String _, int bytes) in cacheFiles) {
        cacheBytes += bytes;
      }
      builder.addFileItem(
        StorageCategory.cache,
        '合成语音缓存（${cacheFiles.length} 个音频）',
        cacheBytes,
        note: '听过的台词，再听不用重新合成',
      );
    }

    // 4) 聊天附件：盘上的名字是 sha256，能对上消息里的附件就显示原名。
    for (final (String rel, int bytes) in await _listFiles(
      path.join(documentsPath, 'attachments'),
    )) {
      final String baseName = path.basename(rel);
      final String? originalName = attachmentNames[baseName];
      builder.addFileItem(
        StorageCategory.attachments,
        originalName ?? baseName,
        bytes,
        note: originalName == null ? '附件（只有哈希名）' : '聊天附件',
      );
    }

    // 5) 备份：导入替换前、删卡前自动存的 ZIP/JSON。
    for (final (String rel, int bytes) in await _listFiles(
      path.join(documentsPath, 'dna_backups'),
    )) {
      builder.addFileItem(
        StorageCategory.other,
        rel,
        bytes,
        note: '自动备份（可以自己删）',
      );
    }

    // 6) 已移除的语音输入留下的模型目录（老版本升级上来可能还在）。
    final List<(String, int)> legacyModels = await _listFiles(
      path.join(documentsPath, 'sherpa_models'),
    );
    if (legacyModels.isNotEmpty) {
      int legacyBytes = 0;
      for (final (String _, int bytes) in legacyModels) {
        legacyBytes += bytes;
      }
      builder.addFileItem(
        StorageCategory.other,
        '旧版语音输入模型（已废弃）',
        legacyBytes,
        note: '${legacyModels.length} 个文件，可以删',
      );
    }

    // 7) Hive 数据库文件：会话/角色卡/世界三类按「明细之外的部分」计，
    //    身份与设置直接整文件计（它们没有明细可列）。
    for (final String boxName in _hiveBoxNames) {
      final int bytes =
          await _fileBytes(path.join(documentsPath, '$boxName.hive')) +
          await _fileBytes(path.join(documentsPath, '$boxName.lock'));
      if (bytes <= 0) continue;
      final StorageCategory? category = _hiveBoxCategory(boxName);
      if (category != null) {
        builder.addHiveFileBytes(category, boxName, bytes);
      } else {
        builder.addFileItem(
          StorageCategory.other,
          '${_hiveBoxLabel(boxName)}（$boxName.hive）',
          bytes,
          note: '数据库文件',
        );
      }
    }
  }

  /// 本应用可能写过的 Hive box（Hive 直接落在文档目录根下）。
  static const List<String> _hiveBoxNames = <String>[
    'conversations',
    'tas',
    'worlds',
    'identities',
    'settings',
    'attachments',
  ];

  static StorageCategory? _hiveBoxCategory(String boxName) => switch (boxName) {
    'conversations' => StorageCategory.conversations,
    'tas' => StorageCategory.characters,
    'worlds' => StorageCategory.worlds,
    _ => null,
  };

  static String _hiveBoxLabel(String boxName) => switch (boxName) {
    'identities' => '身份数据',
    'settings' => '设置数据',
    'attachments' => '附件索引（网页版）',
    _ => boxName,
  };

  /// 列出一个目录下所有文件的（相对路径, 字节数）。目录不存在返回空。
  Future<List<(String, int)>> _listFiles(String directoryPath) async {
    final Directory dir = Directory(directoryPath);
    final List<(String, int)> out = <(String, int)>[];
    if (!await dir.exists()) return out;
    try {
      await for (final FileSystemEntity entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        try {
          out.add((
            path.relative(entity.path, from: dir.path),
            await entity.length(),
          ));
        } catch (_) {
          // 单个文件 stat 不动（被占用/权限）就跳过：它只是少一项明细，
          // 不该让整页盘点失败。
        }
      }
    } catch (_) {
      // 目录读不动同理：这一块当成空的，不影响其它分类。
    }
    return out;
  }

  Future<int> _fileBytes(String filePath) async {
    try {
      final File file = File(filePath);
      if (!await file.exists()) return 0;
      return await file.length();
    } catch (_) {
      return 0;
    }
  }
}

/// 扫描过程的累加器：把散落的字节按分类收拢，最后一次性排序 + 截断。
class _ScanBuilder {
  _ScanBuilder({required this.itemsPerCategory});

  final int itemsPerCategory;

  final Map<StorageCategory, _CategoryDraft> _drafts =
      <StorageCategory, _CategoryDraft>{
        for (final StorageCategory category in StorageCategory.values)
          category: _CategoryDraft(),
      };

  /// 角色卡的按人合并表（图片/音乐要和 JSON 落到同一行）。
  final Map<String, _CharacterDraft> _characters = <String, _CharacterDraft>{};

  /// 认不出属于谁的角色目录文件（比如删卡后没清干净的残图）。
  final List<StorageUsageItem> _orphanCharacterFiles = <StorageUsageItem>[];

  void addRecords(StorageCategory category, List<StorageDataRecord> records) {
    final _CategoryDraft draft = _drafts[category]!;
    for (final StorageDataRecord record in records) {
      draft.items.add(
        StorageUsageItem(
          name: record.name,
          bytes: record.bytes,
          note: record.note,
        ),
      );
      draft.recordsBytes += record.bytes;
    }
  }

  void addCharacters(List<StorageDataRecord> records) {
    for (final StorageDataRecord record in records) {
      final String key = record.ownerId ?? 'name:${record.name}';
      final _CharacterDraft draft = _characters.putIfAbsent(
        key,
        () => _CharacterDraft(name: record.name),
      );
      draft.dataBytes += record.bytes;
      _drafts[StorageCategory.characters]!.recordsBytes += record.bytes;
    }
  }

  void addCharacterFile(String relativePath, int bytes) {
    final String baseName = path.basename(relativePath);
    final String? taId = taIdFromImageFileName(baseName);
    final _CharacterDraft? draft = taId == null ? null : _characters[taId];
    if (draft == null) {
      _orphanCharacterFiles.add(
        StorageUsageItem(
          name: relativePath,
          bytes: bytes,
          note: taId == null ? '认不出属于哪个角色' : '找不到对应的角色卡',
        ),
      );
      return;
    }
    if (isMusicFileName(baseName)) {
      draft.musicCount++;
    } else {
      draft.imageCount++;
    }
    draft.fileBytes += bytes;
  }

  void addFileItem(
    StorageCategory category,
    String name,
    int bytes, {
    String? note,
  }) {
    _drafts[category]!.items.add(
      StorageUsageItem(name: name, bytes: bytes, note: note),
    );
  }

  /// Hive 文件实际大小（最终只把「明细之外的差额」算进分类）。
  void addHiveFileBytes(StorageCategory category, String boxName, int bytes) {
    final _CategoryDraft draft = _drafts[category]!;
    draft.hiveBytes += bytes;
    draft.hiveBoxNames.add(boxName);
  }

  StorageCategoryUsage build(StorageCategory category) {
    final _CategoryDraft draft = _drafts[category]!;
    final List<StorageUsageItem> items = <StorageUsageItem>[...draft.items];

    if (category == StorageCategory.characters) {
      for (final _CharacterDraft character in _characters.values) {
        items.add(
          StorageUsageItem(
            name: character.name ?? '未命名角色',
            bytes: character.dataBytes + character.fileBytes,
            note: character.note,
          ),
        );
      }
      items.addAll(_orphanCharacterFiles);
    }

    // Hive 文件里不属于任何一条记录的部分（帧头、索引、删数据后没回收的空闲页）。
    final int overhead = draft.hiveBytes - draft.recordsBytes;
    if (overhead > 0) {
      items.add(
        StorageUsageItem(
          name: '索引与空闲空间（${draft.hiveBoxNames.join(' / ')}.hive）',
          bytes: overhead,
          note: '数据库文件的固定开销，不算在任何一条内容里',
        ),
      );
    }

    int total = 0;
    for (final StorageUsageItem item in items) {
      total += item.bytes;
    }

    final List<StorageUsageItem> sorted = <StorageUsageItem>[...items]
      ..sort((StorageUsageItem a, StorageUsageItem b) {
        final int byBytes = b.bytes.compareTo(a.bytes);
        return byBytes != 0 ? byBytes : a.name.compareTo(b.name);
      });

    return StorageCategoryUsage(
      category: category,
      bytes: total,
      items: sorted.length > itemsPerCategory
          ? sorted.sublist(0, itemsPerCategory)
          : sorted,
      itemCount: items.length,
    );
  }
}

/// 单类的累加草稿。
class _CategoryDraft {
  final List<StorageUsageItem> items = <StorageUsageItem>[];

  /// 记录 JSON 字节合计（用来和 Hive 文件实际大小求差）。
  int recordsBytes = 0;

  /// 这一类对应的 Hive 文件实际大小。
  int hiveBytes = 0;

  final List<String> hiveBoxNames = <String>[];
}

/// 单个角色卡的累加草稿：资料 JSON + 图片/音乐文件。
class _CharacterDraft {
  _CharacterDraft({this.name});

  final String? name;
  int dataBytes = 0;
  int fileBytes = 0;
  int imageCount = 0;
  int musicCount = 0;

  String? get note {
    final List<String> parts = <String>[
      if (imageCount > 0) '图片 $imageCount 张',
      if (musicCount > 0) '背景音乐 $musicCount 首',
      if (dataBytes > 0) '资料 ${formatStorageBytes(dataBytes)}',
      if (imageCount == 0 && musicCount == 0) '没有图片/音乐',
    ];
    return parts.join(' · ');
  }
}

/// 背景音乐文件名：`music_<taId>.<ext>`（见 TaService.storeMusic）。
bool isMusicFileName(String fileName) =>
    path.basenameWithoutExtension(fileName).startsWith('music_');

/// 从角色目录里的文件名解析出角色 id。
///
/// * 图片：`<taId>_<槽位>_<微秒>.<ext>`（见 ImageStorage.saveBytes）；
/// * 音乐：`music_<taId>.<ext>`（见 TaService.storeMusic）。
///
/// 角色 id 是 UUID（只有连字符、没有下划线），所以取第一个下划线之前的部分
/// 就是 id。解析不出来返回 null —— 宁可显示文件名，也不猜。
String? taIdFromImageFileName(String fileName) {
  final String stem = path.basenameWithoutExtension(fileName);
  if (stem.startsWith('music_')) {
    final String id = stem.substring('music_'.length);
    return id.isEmpty ? null : id;
  }
  final int index = stem.indexOf('_');
  if (index <= 0) return null;
  return stem.substring(0, index);
}
