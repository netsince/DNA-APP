import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../state/app_controller.dart';
import 'ta_export_import_service.dart';

/// 预置内容清单：`assets/presets/index.json`。
///
/// 为什么要有这份名单：Flutter 运行时**列不出** assets 目录，只能按已知文件名读。
/// 名单同时承担两件事：① 声明要释放哪些卡；② 用数组顺序决定释放顺序 ——
/// 首页第一条会话是谁，靠它而不是靠文件名排序（各平台 glob 顺序不一致）。
const String kPresetIndexAsset = 'assets/presets/index.json';
const String kPresetDir = 'assets/presets/';

/// 一张预置卡的释放结果。
class PresetReleaseEntry {
  const PresetReleaseEntry({
    required this.file,
    required this.released,
    this.characterId,
    this.error,
  });

  final String file;

  /// 是否真的落库（文件坏、已存在都算 false）。
  final bool released;

  final String? characterId;
  final String? error;
}

/// 一次释放的汇总。
class PresetReleaseResult {
  const PresetReleaseResult({
    required this.entries,
    required this.conversationsCreated,
  });

  final List<PresetReleaseEntry> entries;

  /// 顺带建出来的会话数（正常是 0 或 1）。
  final int conversationsCreated;

  int get releasedCount =>
      entries.where((PresetReleaseEntry e) => e.released).length;

  bool get ok => entries.every((PresetReleaseEntry e) => e.error == null);
}

/// 释放 `assets/presets/` 里的预置角色卡。
///
/// 设计要点（都是踩过的坑）：
/// * **只做一次**：是否已释放由调用方（[AppController.completeOobe]）用一个不可复位的
///   标记控制；这里本身是幂等的 —— 已存在的 id 一律跳过，不会覆盖用户改过的卡。
/// * **一个坏文件不能拖垮整次**：逐张 try/catch，坏的记 error 继续下一张。
/// * **只给第一张标了 startConversation 的卡建会话**：一次冒出好几条会话，
///   首页比空态还劝退。
class PresetReleaseService {
  PresetReleaseService._();

  /// 释放全部预置卡。任何失败都不抛异常，结果里如实返回。
  static Future<PresetReleaseResult> release({
    required AppController controller,
    AssetBundle? bundle,
  }) async {
    final AssetBundle assets = bundle ?? rootBundle;
    final List<PresetReleaseEntry> entries = <PresetReleaseEntry>[];
    int conversations = 0;

    final List<_PresetDecl> decls = await _readIndex(assets);
    for (final _PresetDecl decl in decls) {
      try {
        final String raw = await assets.loadString('$kPresetDir${decl.file}');
        final ExportImportResult<ImportResult> parsed =
            TaExportImportService.importCharacter(raw);
        if (!parsed.success || parsed.data == null) {
          entries.add(PresetReleaseEntry(
            file: decl.file,
            released: false,
            error: parsed.message ?? '解析失败',
          ));
          continue;
        }
        final TA parsedTa = parsed.data!.ta;
        // 已有同 id：跳过。用户可能已经改过这张卡，覆盖等于把他的改动吃掉。
        if (controller.getTaById(parsedTa.id) != null) {
          entries.add(PresetReleaseEntry(
            file: decl.file,
            released: false,
            characterId: parsedTa.id,
          ));
          continue;
        }
        // 把 .dnata 里内嵌的图片落到本机存储（无图时原样返回）。
        TA ta = parsedTa;
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final ExportImportResult<TA> restored =
              await TaExportImportService.restoreTaImages(parsedTa, decoded);
          if (restored.success && restored.data != null) ta = restored.data!;
        }
        await controller.upsertTa(ta);
        entries.add(PresetReleaseEntry(
          file: decl.file,
          released: true,
          characterId: ta.id,
        ));

        if (decl.startConversation && conversations == 0) {
          final String convId = 'preset.conv.${ta.id}';
          if (controller.getConversationById(convId) == null) {
            await controller.upsertConversation(
              Conversation(
                id: convId,
                taId: ta.id,
                worldId: null,
                note: ta.name,
                messages: const <ConversationMessage>[],
                backgroundMode: 'color',
                summaries: const <ConversationSummary>[],
                archived: false,
                isGroup: false,
                groupName: '',
                groupPrompt: '',
                memberTaIds: const <String>[],
                activeTaId: ta.id,
                // 会话没有时间戳字段：首页只按「置顶 + 存储顺序」排，
                // 这条是首启第一条，自然在最上面。
              ),
            );
            conversations++;
          }
        }
      } catch (e) {
        debugPrint('[preset] 释放失败 ${decl.file}: $e');
        entries.add(PresetReleaseEntry(
          file: decl.file,
          released: false,
          error: '$e',
        ));
      }
    }
    return PresetReleaseResult(
      entries: entries,
      conversationsCreated: conversations,
    );
  }

  static Future<List<_PresetDecl>> _readIndex(AssetBundle assets) async {
    try {
      final String raw = await assets.loadString(kPresetIndexAsset);
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return const <_PresetDecl>[];
      final Object? list = decoded['presets'];
      if (list is! List) return const <_PresetDecl>[];
      final List<_PresetDecl> out = <_PresetDecl>[];
      for (final Object? item in list) {
        if (item is! Map) continue;
        final Object? file = item['file'];
        if (file is! String || file.trim().isEmpty) continue;
        out.add(_PresetDecl(
          file: file.trim(),
          startConversation: item['startConversation'] == true,
        ));
      }
      return out;
    } catch (e) {
      debugPrint('[preset] 读不到预置清单（跳过释放）: $e');
      return const <_PresetDecl>[];
    }
  }
}

class _PresetDecl {
  const _PresetDecl({required this.file, required this.startConversation});

  final String file;
  final bool startConversation;
}
