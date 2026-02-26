import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/role.dart';

class RoleService {
  static const String _rolesKey = 'roles_v1';

  Future<List<Role>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_rolesKey);
    if (raw == null || raw.isEmpty) {
      return <Role>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(Role.fromJson)
            .toList();
      }
    } catch (_) {}
    return <Role>[];
  }

  Future<void> save(List<Role> roles) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(roles.map((Role role) => role.toJson()).toList());
    await prefs.setString(_rolesKey, raw);
  }

  Future<String> storeImage({
    required String sourcePath,
    required String roleId,
    required String slot,
  }) async {
    final Directory dir = await _ensureRoleDir();
    final String ext = path.extension(sourcePath).isEmpty ? '.jpg' : path.extension(sourcePath);
    final String fileName = '${roleId}_$slot$ext';
    final String targetPath = path.join(dir.path, fileName);
    final File sourceFile = File(sourcePath);
    await sourceFile.copy(targetPath);
    return targetPath;
  }

  Future<Directory> _ensureRoleDir() async {
    final Directory doc = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(path.join(doc.path, 'roles'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
