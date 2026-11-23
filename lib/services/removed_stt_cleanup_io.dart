import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 旧版本用的模型目录名（原 `kSherpaModelDirName`）。
const String _removedModelDirName = 'sherpa_models';

/// 清理完成的标记键：有它就说明已经清理过，直接返回。
const String _cleanupDoneKey = 'stt_removed_cleanup_v1';

/// 旧版本写过的 6 个设置键（现在没人读，留着只会让备份/排查困惑）。
const List<String> _legacyKeys = <String>[
  'sherpa_model_source',
  'sherpa_custom_base_url',
  'sherpa_model_ready',
  'sherpa_model_path',
  'sherpa_selected_model_id',
  'voice_input_enabled',
];

/// 一次性清理已移除的语音输入留下的模型目录与设置键。
///
/// 幂等：标记存在时只做一次字典查找就返回。任何失败都只记日志，不抛出 ——
/// 清理失败不该拦住启动。
Future<void> cleanupRemovedSpeechInput() async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_cleanupDoneKey) == true) return;

    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory modelDir = Directory(
      path.join(docs.path, _removedModelDirName),
    );
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
      debugPrint('[stt-cleanup] 已删除旧语音模型目录: ${modelDir.path}');
    }

    for (final String key in _legacyKeys) {
      await prefs.remove(key);
    }
    await prefs.setBool(_cleanupDoneKey, true);
  } catch (e) {
    debugPrint('[stt-cleanup] 清理失败（忽略）: $e');
  }
}