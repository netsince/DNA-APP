import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置项的「使用记录」：搜索页的「常用 / 最近使用」靠它。
///
/// 只记入口 id（不是每个字段）：用户点开的是「外观与聊天界面」这一页，
/// 说「最近用过『字号』」是假精度。存两份数据：点开次数（算常用）和最后一次
/// 打开的时间（算最近）。
///
/// 存储用 SharedPreferences 独立键，不塞进 AppSettings：这是使用痕迹，不是配置，
/// 不该跟着设置一起备份/迁移。
class SettingsUsageStore extends ChangeNotifier {
  SettingsUsageStore._();

  static final SettingsUsageStore instance = SettingsUsageStore._();

  static const String _prefsKey = 'settings_usage_v1';

  final Map<String, int> _counts = <String, int>{};
  final Map<String, int> _lastUsedMs = <String, int>{};
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      for (final MapEntry<String, dynamic> e in decoded.entries) {
        final Map<String, dynamic> v = e.value as Map<String, dynamic>;
        _counts[e.key] = (v['c'] as num?)?.toInt() ?? 0;
        _lastUsedMs[e.key] = (v['t'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      // 记录坏了不能影响设置页可用：当作没有记录。
      debugPrint('读取设置使用记录失败: $e');
    }
  }

  /// 记一次打开。
  Future<void> record(String entryId, {DateTime? now}) async {
    await ensureLoaded();
    _counts[entryId] = (_counts[entryId] ?? 0) + 1;
    _lastUsedMs[entryId] = (now ?? DateTime.now()).millisecondsSinceEpoch;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> out = <String, dynamic>{};
      for (final MapEntry<String, int> e in _counts.entries) {
        out[e.key] = <String, int>{
          'c': e.value,
          't': _lastUsedMs[e.key] ?? 0,
        };
      }
      await prefs.setString(_prefsKey, jsonEncode(out));
    } catch (e) {
      debugPrint('保存设置使用记录失败: $e');
    }
  }

  int countOf(String entryId) => _counts[entryId] ?? 0;

  /// 常用：按点开次数降序（同次数按最近使用靠前）。
  List<String> mostUsed({int limit = 6}) {
    final List<String> ids = _counts.keys.toList()
      ..sort((String a, String b) {
        final int byCount = (_counts[b] ?? 0).compareTo(_counts[a] ?? 0);
        if (byCount != 0) return byCount;
        return (_lastUsedMs[b] ?? 0).compareTo(_lastUsedMs[a] ?? 0);
      });
    return ids.take(limit).toList();
  }

  /// 最近使用：按最后打开时间降序。
  List<String> recentlyUsed({int limit = 6}) {
    final List<String> ids = _lastUsedMs.keys.toList()
      ..sort((String a, String b) =>
          (_lastUsedMs[b] ?? 0).compareTo(_lastUsedMs[a] ?? 0));
    return ids.take(limit).toList();
  }

  @visibleForTesting
  void debugReset() {
    _counts.clear();
    _lastUsedMs.clear();
    _loaded = false;
  }
}
