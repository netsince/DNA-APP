import 'dart:ui';

import 'tokens.dart';

/// 界面配色（深色玻璃主题的可自定义部分）。
///
/// 用户可以挑一套预设，也可以自定义「画布底色」和「玻璃底色」；
/// 玻璃卡片的填充/描边透明度、深浅文字色都从这两个基色推导，
/// 保证任意配色下文字对比度仍然够用。
///
/// 语义分层：
/// - [canvas]     页面最底层（AppBackdrop 中段、Scaffold 背景）
/// - [canvasSoft] 侧边栏等次级区域
/// - [glassTint]  玻璃卡片的色相来源（白色 = 中性玻璃，带色 = 有色玻璃）
class AppPalette {
  const AppPalette({
    required this.key,
    required this.name,
    required this.canvas,
    required this.glassTint,
  });

  /// 预设标识（持久化用）。
  final String key;

  /// 展示名。
  final String name;

  /// 画布基色（不透明）。
  final Color canvas;

  /// 玻璃基色（不透明，仅取色相；透明度由 [AppPaletteResolved] 决定）。
  final Color glassTint;

  /// 自定义配色的保留 key。
  static const String customKey = 'custom';

  /// 预设列表。第一个是默认（v1.1 深色玻璃的原始观感）。
  static const List<AppPalette> presets = <AppPalette>[
    AppPalette(
      key: 'graphite',
      name: '深空石墨',
      canvas: Color(0xFF080A0D),
      glassTint: Color(0xFFFFFFFF),
    ),
    AppPalette(
      key: 'cobalt',
      name: '午夜钴蓝',
      canvas: Color(0xFF070B16),
      glassTint: Color(0xFFB7D3FF),
    ),
    AppPalette(
      key: 'violet',
      name: '暗夜紫',
      canvas: Color(0xFF0B0714),
      glassTint: Color(0xFFCFC2FF),
    ),
    AppPalette(
      key: 'jade',
      name: '墨玉青',
      canvas: Color(0xFF06110E),
      glassTint: Color(0xFFAEEBD8),
    ),
    AppPalette(
      key: 'rose',
      name: '暗玫瑰',
      canvas: Color(0xFF120A0C),
      glassTint: Color(0xFFFFC4CC),
    ),
    AppPalette(
      key: 'amber',
      name: '暖琥珀',
      canvas: Color(0xFF100D08),
      glassTint: Color(0xFFFFD9A3),
    ),
  ];

  /// 默认预设。
  static AppPalette get fallback => presets.first;

  static AppPalette? byKey(String key) {
    for (final AppPalette p in presets) {
      if (p.key == key) return p;
    }
    return null;
  }

  /// 把设置解析成最终的界面色板。
  ///
  /// [customCanvas]/[customGlass] 为自定义模式下的 ARGB；缺省则回退默认预设。
  static AppPaletteResolved resolve({
    required String key,
    int? customCanvas,
    int? customGlass,
  }) {
    if (key == customKey) {
      final AppPalette base = fallback;
      return AppPaletteResolved.fromBases(
        canvas: customCanvas != null ? Color(customCanvas) : base.canvas,
        glassTint: customGlass != null ? Color(customGlass) : base.glassTint,
      );
    }
    final AppPalette p = byKey(key) ?? fallback;
    return AppPaletteResolved.fromBases(
      canvas: p.canvas,
      glassTint: p.glassTint,
    );
  }
}

/// 已解析的具体颜色（可直接写进 [AppSurfaces]）。
class AppPaletteResolved {
  AppPaletteResolved._({
    required this.canvas,
    required this.canvasSoft,
    required this.glassFill,
    required this.glassFillStrong,
    required this.glassFillWeak,
    required this.glassBorder,
    required this.glassBorderSoft,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkTertiary,
  });

  factory AppPaletteResolved.fromBases({
    required Color canvas,
    required Color glassTint,
  }) {
    // 玻璃色相保留，透明度固定——这是「玻璃」质感的来源。
    final Color tint = glassTint;
    // 画布偏亮时改深色文字，避免看不清。
    final bool lightCanvas = canvas.computeLuminance() > 0.42;
    return AppPaletteResolved._(
      canvas: canvas,
      canvasSoft: Color.lerp(canvas, const Color(0xFFFFFFFF), 0.045)!,
      glassFill: tint.withValues(alpha: 0.11),
      glassFillStrong: tint.withValues(alpha: 0.17),
      glassFillWeak: tint.withValues(alpha: 0.06),
      glassBorder: tint.withValues(alpha: 0.14),
      glassBorderSoft: tint.withValues(alpha: 0.09),
      inkPrimary: lightCanvas
          ? const Color(0xFF12151A)
          : const Color(0xFFEDEFF3),
      inkSecondary: lightCanvas
          ? const Color(0xFF454C57)
          : const Color(0xFFA7B0BD),
      inkTertiary: lightCanvas
          ? const Color(0xFF6B7380)
          : const Color(0xFF6E7885),
    );
  }

  final Color canvas;
  final Color canvasSoft;
  final Color glassFill;
  final Color glassFillStrong;
  final Color glassFillWeak;
  final Color glassBorder;
  final Color glassBorderSoft;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkTertiary;

  /// 派生一个「同色系更亮/更暗」的表面色（用于 surfaceContainer 层级）。
  Color shade(double amount) =>
      Color.lerp(canvas, const Color(0xFFFFFFFF), amount)!;

  /// 写入全局表面令牌，然后由 DnaApp 重建主题。
  void apply() {
    AppSurfaces.canvasDark = canvas;
    AppSurfaces.canvasDarkSoft = canvasSoft;
    AppSurfaces.glassFill = glassFill;
    AppSurfaces.glassFillStrong = glassFillStrong;
    AppSurfaces.glassFillWeak = glassFillWeak;
    AppSurfaces.glassBorder = glassBorder;
    AppSurfaces.glassBorderSoft = glassBorderSoft;
    AppSurfaces.inkPrimary = inkPrimary;
    AppSurfaces.inkSecondary = inkSecondary;
    AppSurfaces.inkTertiary = inkTertiary;
  }
}
