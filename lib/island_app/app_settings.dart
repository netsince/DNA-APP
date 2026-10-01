import 'package:flutter/material.dart';
import 'package:dna/island_app/shared_prefs.dart';

/// 全局外观设置（主题模式 + 强调色），持久化到本地。
///
/// - 主题模式：自动（跟随系统）/ 白天（浅色）/ 黑天（深色）
/// - 强调色：自动（默认品牌色）或用户自定义
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const String _themeModeKey = 'theme_mode'; // 'system' | 'light' | 'dark'
  static const String _accentKey = 'accent_color'; // 缺失则“自动”

  ThemeMode _themeMode = ThemeMode.system;
  int? _accentColor;

  ThemeMode get themeMode => _themeMode;

  /// null 表示“自动”（使用默认品牌色）。
  int? get accentColor => _accentColor;
  bool get useCustomAccent => _accentColor != null;

  Future<void> load() async {
    final prefs = await SharedPrefs.instance;
    final mode = prefs.getString(_themeModeKey);
    _themeMode = switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _accentColor = prefs.getInt(_accentKey);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPrefs.instance;
    await prefs.setString(
      _themeModeKey,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      },
    );
    notifyListeners();
  }

  Future<void> setAccentColor(int? color) async {
    _accentColor = color;
    final prefs = await SharedPrefs.instance;
    if (color == null) {
      await prefs.remove(_accentKey);
    } else {
      await prefs.setInt(_accentKey, color);
    }
    notifyListeners();
  }
}
