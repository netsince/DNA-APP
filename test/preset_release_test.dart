import 'dart:convert';
import 'dart:io';

import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/preset_release_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_export_import_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHive extends HiveService {
  final List<TA> tas = <TA>[];
  final List<Conversation> conversations = <Conversation>[];

  @override
  Future<void> init() async {}
  @override
  Future<List<TA>> getTas() async => <TA>[];
  @override
  Future<List<UserIdentity>> getIdentities() async => <UserIdentity>[];
  @override
  Future<List<World>> getWorlds() async => <World>[];
  @override
  Future<List<Conversation>> getConversations() async => <Conversation>[];
  @override
  Future<void> upsertTa(TA ta) async {
    tas.removeWhere((TA t) => t.id == ta.id);
    tas.add(ta);
  }
  @override
  Future<void> upsertConversation(Conversation c) async {
    conversations.removeWhere((Conversation x) => x.id == c.id);
    conversations.add(c);
  }
}

/// 只带两个资源：清单 + 一张卡。
class _FakeAssets extends CachingAssetBundle {
  _FakeAssets(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final String? content = files[key];
    if (content == null) throw FlutterError('没有这个资源: $key');
    final List<int> bytes = utf8.encode(content);
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final String? content = files[key];
    if (content == null) throw FlutterError('没有这个资源: $key');
    return content;
  }
}

String _card(String id, String name) => jsonEncode(<String, dynamic>{
      'version': 2,
      'exportType': 'single',
      'exportedAt': '2026-01-01T00:00:00.000Z',
      'compressed': false,
      'character': <String, dynamic>{
        'id': id,
        'name': name,
        'gender': '无性',
        'persona': '测试用',
        'intro': '测试用',
        'opening': '你来了。',
        'tags': <String>[],
        'dialogueStyle': <dynamic>[],
        'images': <String, dynamic>{},
        'authorNoteInterval': 0,
      },
    });

Future<AppController> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final AppController c = AppController(
    settingsService: SettingsService(),
    openAiService: OpenAiService(),
    taService: TaService(),
    hiveService: _FakeHive(),
  );
  await c.initialize();
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('释放：落卡 + 给第一张建会话，坏文件跳过不中断', () async {
    final AppController c = await _boot();
    final _FakeAssets assets = _FakeAssets(<String, String>{
      kPresetIndexAsset: jsonEncode(<String, dynamic>{
        'version': 1,
        'presets': <dynamic>[
          <String, dynamic>{'file': 'broken.dnata'},
          <String, dynamic>{'file': 'ok.dnata', 'startConversation': true},
        ],
      }),
      'assets/presets/broken.dnata': '{ 这不是 JSON',
      'assets/presets/ok.dnata': _card('preset.test', '示例角色'),
    });

    final PresetReleaseResult result =
        await PresetReleaseService.release(controller: c, bundle: assets);

    expect(result.entries, hasLength(2));
    expect(result.releasedCount, 1);
    expect(result.conversationsCreated, 1);
    expect(result.ok, isFalse, reason: '坏文件应如实记为失败');

    expect(c.getTaById('preset.test')?.name, '示例角色');
    expect(c.getConversationById('preset.conv.preset.test'), isNotNull);
  });

  test('释放是幂等的：第二次不重复建卡建会话', () async {
    final AppController c = await _boot();
    final _FakeAssets assets = _FakeAssets(<String, String>{
      kPresetIndexAsset: jsonEncode(<String, dynamic>{
        'version': 1,
        'presets': <dynamic>[
          <String, dynamic>{'file': 'ok.dnata', 'startConversation': true},
        ],
      }),
      'assets/presets/ok.dnata': _card('preset.test', '示例角色'),
    });

    await PresetReleaseService.release(controller: c, bundle: assets);
    final PresetReleaseResult second =
        await PresetReleaseService.release(controller: c, bundle: assets);

    expect(second.releasedCount, 0, reason: '同 id 已存在必须跳过');
    expect(second.conversationsCreated, 0);
  });

  test('清单缺失时安静跳过，不抛异常', () async {
    final AppController c = await _boot();
    final PresetReleaseResult result = await PresetReleaseService.release(
      controller: c,
      bundle: _FakeAssets(<String, String>{}),
    );
    expect(result.entries, isEmpty);
    expect(result.conversationsCreated, 0);
  });

  test('工程里的真卡能通过导入器（防止手写 .dnata 写坏）', () async {
    for (final String file in <String>['assets/presets/alan.dnata']) {
      final File f = File(file);
      expect(f.existsSync(), isTrue, reason: '$file 不在）；');
      final ExportImportResult<ImportResult> parsed =
          TaExportImportService.importCharacter(f.readAsStringSync());
      expect(parsed.success, isTrue, reason: parsed.message);
      final TA ta = parsed.data!.ta;
      expect(ta.name.isNotEmpty, isTrue);
      expect(ta.opening.isNotEmpty, isTrue, reason: '没有开场白就没有「内置聊天」');
    }
  });

  test('presetReleased 不随 restartOobe 复位', () async {
    final AppController c = await _boot();
    await c.completeOobe();
    expect(c.settings.completedOobe, isTrue);
    expect(c.settings.presetReleased, isTrue, reason: '第一次完成引导应释放预置卡');
    await c.restartOobe();
    expect(c.settings.completedOobe, isFalse);
    expect(c.settings.presetReleased, isTrue, reason: '重走引导不许再释放一次');
  });
}
