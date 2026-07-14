import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/dialogue_style.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/data_backup_service.dart';
import 'package:dna/services/ta_export_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

const List<int> _sampleImageBytes = <int>[1, 2, 3, 4, 5, 6, 7, 8];

TA _buildTa({required String id, Map<String, String> images = const <String, String>{}}) {
  return TA(
    id: id,
    name: '角色$id',
    gender: '女',
    persona: 'persona-$id',
    intro: 'intro-$id',
    opening: 'opening-$id',
    tags: <String>['tag-a', 'tag-b'],
    images: images,
    dialogueStyle: const <DialogueTurn>[],
  );
}

World _buildWorld({required String id}) {
  return World(
    id: id,
    name: '世界$id',
    summary: 'summary-$id',
    description: 'desc-$id',
    tags: const <String>['w'],
    forbiddenWords: const <String>[],
    entries: const <WorldEntry>[],
  );
}

Conversation _buildConversation({required String id, required String taId}) {
  return Conversation(
    id: id,
    taId: taId,
    worldId: 'world-1',
    note: 'note-$id',
    messages: <ConversationMessage>[
      ConversationMessage(
        id: 'm-$id-1',
        role: 'user',
        text: 'hello',
        timestamp: 1000,
      ),
      ConversationMessage(
        id: 'm-$id-2',
        role: 'assistant',
        text: 'hi there',
        timestamp: 1001,
        speakerTaId: taId,
      ),
    ],
    backgroundMode: 'none',
    summaries: const <ConversationSummary>[],
    archived: false,
    isGroup: false,
    groupName: '',
    groupPrompt: '',
    memberTaIds: const <String>[],
    activeTaId: null,
  );
}

void main() {
  group('DataBackupService 全量 ZIP', () {
    test('buildZip + parseZip 往返一致', () async {
      final TA ta = _buildTa(id: 'ta-1');
      final World world = _buildWorld(id: 'w-1');
      final Conversation conv = _buildConversation(id: 'c-1', taId: 'ta-1');

      final ExportImportResult<Uint8List> build =
          await DataBackupService.buildZip(tas: [ta], worlds: [world], conversations: [conv]);
      expect(build.success, isTrue);
      expect(build.data, isNotNull);

      final ExportImportResult<ParsedBackup> parsed =
          DataBackupService.parseZip(build.data!);
      expect(parsed.success, isTrue);
      final ParsedBackup backup = parsed.data!;

      expect(backup.manifest.type, 'full');
      expect(backup.tas.length, 1);
      expect(backup.tas.first.name, '角色ta-1');
      expect(backup.tas.first.persona, 'persona-ta-1');
      expect(backup.worlds.length, 1);
      expect(backup.worlds.first.name, '世界w-1');
      expect(backup.conversations.length, 1);
      expect(backup.conversations.first.id, 'c-1');
      expect(backup.conversations.first.messages.length, 2);
      expect(backup.conversations.first.messages.last.text, 'hi there');
    });

    test('ZIP 内不含 settings.json（不打包设置）', () async {
      final ExportImportResult<Uint8List> build = await DataBackupService.buildZip(
        tas: [_buildTa(id: 't')],
        worlds: const <World>[],
        conversations: const <Conversation>[],
      );
      expect(build.success, isTrue);

      final Archive archive = ZipDecoder().decodeBytes(build.data!);
      final bool hasSettings =
          archive.files.any((ArchiveFile f) => f.name == 'settings.json');
      expect(hasSettings, isFalse);
    });

    test('TA 图片随包导出并在解析后落盘还原', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp('dna_bkp_');
      try {
        final File imgFile = File('${tempDir.path}/avatar.png');
        await imgFile.writeAsBytes(_sampleImageBytes);

        final TA ta = _buildTa(
          id: 'ta-img',
          images: <String, String>{'avatar': imgFile.path},
        );
        final ExportImportResult<Uint8List> build = await DataBackupService.buildZip(
          tas: [ta],
          worlds: const <World>[],
          conversations: const <Conversation>[],
        );
        expect(build.success, isTrue);

        final ParsedBackup backup = DataBackupService.parseZip(build.data!).data!;
        // 解析后图片以相对文件名表示
        expect(backup.tas.first.images['avatar'], 'avatar.png');
        expect(backup.imageBytes.containsKey('avatar.png'), isTrue);

        final Directory outDir = Directory('${tempDir.path}/out')..createSync();
        final List<TA> resolved = DataBackupService.resolveTasImages(
          backup.tas,
          backup.imageBytes,
          outDir.path,
        );
        final String resolvedPath = resolved.first.images['avatar']!;
        expect(resolvedPath, startsWith(outDir.path));
        expect(File(resolvedPath).readAsBytesSync(), _sampleImageBytes);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('解析损坏/缺失 manifest 的 ZIP 失败', () {
      final Archive archive = Archive();
      final ExportImportResult<ParsedBackup> parsed =
          DataBackupService.parseZip(Uint8List.fromList(ZipEncoder().encode(archive)));
      expect(parsed.success, isFalse);
    });
  });

  group('DataBackupService 仅对话 ZIP', () {
    test('buildConversationsZip + parseConversationsZip 往返一致', () async {
      final Conversation c1 = _buildConversation(id: 'c-1', taId: 'ta-1');
      final Conversation c2 = _buildConversation(id: 'c-2', taId: 'ta-2');

      final ExportImportResult<Uint8List> build =
          await DataBackupService.buildConversationsZip(conversations: [c1, c2]);
      expect(build.success, isTrue);

      final ExportImportResult<List<Conversation>> parsed =
          DataBackupService.parseConversationsZip(build.data!);
      expect(parsed.success, isTrue);
      expect(parsed.data!.length, 2);
      expect(parsed.data!.map((Conversation c) => c.id).toList(),
          unorderedEquals(<String>['c-1', 'c-2']));
      expect(parsed.data!.first.messages.length, 2);
    });

    test('全量包可被 parseConversationsZip 兼容解析', () async {
      final Conversation conv = _buildConversation(id: 'c-full', taId: 'ta-1');
      final ExportImportResult<Uint8List> full = await DataBackupService.buildZip(
        tas: [_buildTa(id: 'ta-1')],
        worlds: [_buildWorld(id: 'w-1')],
        conversations: [conv],
      );
      expect(full.success, isTrue);

      final ExportImportResult<List<Conversation>> parsed =
          DataBackupService.parseConversationsZip(full.data!);
      expect(parsed.success, isTrue);
      expect(parsed.data!.length, 1);
      expect(parsed.data!.first.id, 'c-full');
    });

    test('缺少 conversations.json 时 parseConversationsZip 失败', () {
      final Archive archive = Archive();
      final ExportImportResult<List<Conversation>> parsed =
          DataBackupService.parseConversationsZip(
        Uint8List.fromList(ZipEncoder().encode(archive)),
      );
      expect(parsed.success, isFalse);
      expect(parsed.message, contains('conversations.json'));
    });
  });
}
