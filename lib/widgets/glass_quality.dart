import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 玻璃画质：高 = Paint.shader 真折射；中 = 几何玻璃（当前默认）；关 = 平底。
enum GlassQuality {
  high('高（真折射）'),
  medium('中（几何高光）'),
  off('关');

  const GlassQuality(this.label);
  final String label;
}

/// 画质开关的本地存储 + 通知。默认「高」，渲染失败时自动回退到「中」。
class GlassQualityStore extends ChangeNotifier {
  GlassQualityStore._();

  static final GlassQualityStore instance = GlassQualityStore._();

  static const String prefsKey = 'glass_quality';

  GlassQuality _value = GlassQuality.high;
  GlassQuality get value => _value;

  /// shader 是否可用（加载失败/后端不支持时为 false，此时自动用几何版）。
  bool shaderAvailable = true;

  /// 由 GL 层在加载失败时调用。
  void markShaderUnavailable() {
    if (!shaderAvailable) return;
    shaderAvailable = false;
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(prefsKey);
      if (raw != null) {
        for (final GlassQuality q in GlassQuality.values) {
          if (q.name == raw) {
            _value = q;
            break;
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> set(GlassQuality q) async {
    if (_value == q) return;
    _value = q;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, q.name);
    } catch (_) {}
  }

  /// 实际生效的画质（shader 不可用时降级）。
  GlassQuality get effective =>
      _value == GlassQuality.high && !shaderAvailable ? GlassQuality.medium : _value;
}

/// 抓取后景纹理：把 [child] 放进 RepaintBoundary，按约 15fps 捕获成 `ui.Image`，
/// 供 [GlassQuality.high] 的 shader 玻璃采样。
///
/// 只捕获一次 0.5× 分辨率的整屏（玻璃本身会被 shader 用 y 上限排除），
/// 比每块玻璃各抓一次便宜得多。
class GlassBackdrop extends StatefulWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  static GlassBackdropState? of(BuildContext context) =>
      context.findAncestorStateOfType<GlassBackdropState>();

  @override
  State<GlassBackdrop> createState() => GlassBackdropState();
}

class GlassBackdropState extends State<GlassBackdrop> {
  final GlobalKey _boundaryKey = GlobalKey();
  final ValueNotifier<ui.Image?> image = ValueNotifier<ui.Image?>(null);

  Timer? _timer;
  bool _capturing = false;

  /// 本边界在屏幕上的左上角（逻辑像素），供 shader 玻璃换算采样原点。
  Offset get globalOffset {
    final RenderObject? ro = _boundaryKey.currentContext?.findRenderObject();
    if (ro is RenderBox && ro.hasSize) return ro.localToGlobal(Offset.zero);
    return Offset.zero;
  }

  @override
  void initState() {
    super.initState();
    // shader 玻璃只在「高」画质下才需要抓图，其余情况完全不起定时器。
    _syncTimer();
    GlassQualityStore.instance.addListener(_syncTimer);
  }

  @override
  void dispose() {
    GlassQualityStore.instance.removeListener(_syncTimer);
    _timer?.cancel();
    image.value?.dispose();
    image.dispose();
    super.dispose();
  }

  void _syncTimer() {
    final bool need = GlassQualityStore.instance.effective == GlassQuality.high;
    if (need && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 66), (_) => _capture());
    } else if (!need && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _capture() {
    if (_capturing || !mounted) return;
    _capturing = true;
    try {
      final RenderObject? ro =
          _boundaryKey.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return;
      final ui.Image next = ro.toImageSync(pixelRatio: 0.5);
      final ui.Image? old = image.value;
      image.value = next;
      if (old != null) {
        // 让引用先切走，下一帧再释放，避免正在被 shader 使用。
        SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } catch (_) {
      // 某些后端不支持同步截图，直接关掉这条路径。
      GlassQualityStore.instance.markShaderUnavailable();
      _timer?.cancel();
      _timer = null;
    } finally {
      _capturing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: widget.child,
    );
  }
}
