import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/dialogue_style.dart';

class SettingsService {
  static const String _baseUrlKey = 'base_url';
  static const String _apiKeyKey = 'api_key';
  static const String _modelKey = 'selected_model';
  static const String _oobeKey = 'completed_oobe';
  static const String _dialogueKey = 'dialogue_style';

  Future<AppSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? dialogueRaw = prefs.getString(_dialogueKey);
    final List<DialogueTurn> dialogueStyle = _decodeDialogue(dialogueRaw);
    return AppSettings(
      baseUrl: prefs.getString(_baseUrlKey) ?? '',
      apiKey: prefs.getString(_apiKeyKey) ?? '',
      selectedModel: prefs.getString(_modelKey) ?? '',
      completedOobe: prefs.getBool(_oobeKey) ?? false,
      dialogueStyle: dialogueStyle,
    );
  }

  Future<void> save(AppSettings settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, settings.baseUrl);
    await prefs.setString(_apiKeyKey, settings.apiKey);
    await prefs.setString(_modelKey, settings.selectedModel);
    await prefs.setBool(_oobeKey, settings.completedOobe);
    await prefs.setString(_dialogueKey, _encodeDialogue(settings.dialogueStyle));
  }

  List<DialogueTurn> _decodeDialogue(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <DialogueTurn>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(DialogueTurn.fromJson)
            .toList();
      }
    } catch (_) {}
    return <DialogueTurn>[];
  }

  String _encodeDialogue(List<DialogueTurn> turns) {
    final List<Map<String, dynamic>> data =
        turns.map((DialogueTurn turn) => turn.toJson()).toList();
    return jsonEncode(data);
  }
}
