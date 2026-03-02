import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ta.dart';

class TaService {
  static const String _tasKey = 'tas_v1';

  Future<List<TA>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_tasKey);
    if (raw == null || raw.isEmpty) {
      return <TA>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(TA.fromJson)
            .toList();
      }
    } catch (_) {}
    return <TA>[];
  }

  Future<void> save(List<TA> tas) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(tas.map((TA ta) => ta.toJson()).toList());
    await prefs.setString(_tasKey, raw);
  }

  Future<String> storeImage({
    required String sourcePath,
    required String taId,
    required String slot,
  }) async {
    final Directory dir = await _ensureTaDir();
    final String ext = path.extension(sourcePath).isEmpty ? '.jpg' : path.extension(sourcePath);
    final String fileName = '${taId}_$slot$ext';
    final String targetPath = path.join(dir.path, fileName);
    final File sourceFile = File(sourcePath);
    await sourceFile.copy(targetPath);
    return targetPath;
  }

  Future<Directory> _ensureTaDir() async {
    final Directory doc = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(path.join(doc.path, 'tas'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
