import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// 图片像素尺寸。
@immutable
class ImageSize {
  const ImageSize(this.width, this.height);

  final int width;
  final int height;

  /// 长边（横图取宽、竖图取高）。
  int get longSide => width > height ? width : height;

  @override
  bool operator ==(Object other) =>
      other is ImageSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

/// 一次压缩的结果：字节 + 实际输出尺寸。
@immutable
class CompressedImage {
  const CompressedImage({required this.bytes, required this.size});

  final Uint8List bytes;

  /// 输出尺寸（已按 [ImageCompressor] 的语义等比收口）。
  final ImageSize size;
}

/// 图片缩放/压缩的**唯一入口**。
///
/// ## 为什么要有这个类
///
/// Windows 桌面端导出角色卡会直接报
/// 「导出失败: UnimplementedError: FlutterImageCompress.compressWithList is
/// not available.」。根因不是调用写错，是 flutter_image_compress 只给
/// Android / iOS / macOS（以及 Web / OHOS）注册了实现——见
/// flutter_image_compress_platform_interface 里的 UnsupportedFlutterImageCompress，
/// 它就是默认实例，Windows / Linux 上没人替换掉——而调用方用的是 kIsWeb 判平台：
///
/// * Web 走纯 Dart 兜底；
/// * 其余全部当「有原生实现」，桌面端因此调到了一个不存在的方法。
///
/// 这类 bug 的成因是**「有没有原生实现」这个判断散落在调用点**，所以修法不是在
/// 导出里补一个 Platform.isWindows（附件压缩的同类判断还错着，而且下一个新增的
/// 压缩调用点会再错一次），而是把判断和能力一起收进这一个入口：
///
/// 1. 支持哪些平台、不支持时怎么兜底，只在这里判一次（[hasNativeCompressor]）；
/// 2. 缩放语义只在这里定义（[fitInside]：等比、长边不超过上限、不放大）；
/// 3. 调用方只拿「压好的字节 + 尺寸」，不用再关心「这个平台行不行」。
///
/// 调用点只有两处（角色卡导出、聊天附件），都只调 [compress]。
///
/// ## 语义（各平台必须一致）
///
/// * 等比缩放，长边缩到 [maxSide] 以内；**不放大**（小图原样重编码）；
/// * 输出统一为 JPEG —— 与原行为一致（原生默认 CompressFormat.jpeg，Web 兜底也编 JPEG）；
/// * 动图（GIF）**不压**，返回 null 让调用方保留原始字节：压成 JPEG 会把逐帧动画
///   退化成静态帧，「静默丢动画」比「文件大一点」更糟；
/// * 解不出来的字节返回 null（调用方按原图处理），**绝不抛异常**。
///
/// 「长边不超过 [maxSide]」在纯 Dart 实现里是精确的；原生实现按浮点比例再取整，
/// 允许 1px 误差（[compress] 会复查原生输出，明显超出就交回纯 Dart 收口——只有
/// 带 EXIF 旋转的照片会走到那一步，它的有效宽高与文件里记的宽高是转置的）。
class ImageCompressor {
  ImageCompressor._();

  /// 真的有原生实现的平台。
  ///
  /// 依据：flutter_image_compress 的依赖集合里只有 _common（Android / iOS）、
  /// _macos、_web、_ohos 四个实现包，没有 Windows / Linux。用
  /// [defaultTargetPlatform] 而不是 dart:io 的 Platform.isWindows：前者在测试里
  /// 可以用 debugDefaultTargetPlatformOverride 覆盖，Web 上也不用碰 dart:io。
  static const Set<TargetPlatform> nativePlatforms = <TargetPlatform>{
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  };

  /// 当前平台是否有原生压缩实现（false 时走纯 Dart，不是「不支持」）。
  static bool get hasNativeCompressor =>
      !kIsWeb && nativePlatforms.contains(defaultTargetPlatform);

  /// 等比装进 maxSide x maxSide 的盒子：长边不超过 [maxSide]，不放大。
  ///
  /// 这是**唯一**的缩放语义定义。此前两处调用点各写一份：纯 Dart 分支用
  /// copyResize(width: n, height: n)（宽高都给 → 把图拉成正方形，人脸全歪），
  /// 原生分支用 minWidth/minHeight（插件实际是「至少」语义，竖图长边会超出上限）。
  static ImageSize fitInside(ImageSize source, int maxSide) {
    if (maxSide <= 0) return source;
    final int longSide = source.longSide;
    if (longSide <= maxSide) return source;
    final double scale = maxSide / longSide;
    return ImageSize(
      math.max(1, (source.width * scale).round()),
      math.max(1, (source.height * scale).round()),
    );
  }

  /// 只读文件头拿尺寸，不解析像素（大图也便宜）。解不出来返回 null。
  static ImageSize? probeSize(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    try {
      final img.DecodeInfo? info =
          img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null || info.width <= 0 || info.height <= 0) return null;
      return ImageSize(info.width, info.height);
    } catch (_) {
      return null;
    }
  }

  /// 压缩 [input]：等比缩到长边不超过 [maxSide]，按 [quality] 编码 JPEG。
  ///
  /// 返回 null 表示「这张图不该/不能被压」（动图、解不出来），调用方按原图处理。
  static Future<CompressedImage?> compress(
    Uint8List input, {
    required int maxSide,
    int quality = 85,
  }) async {
    if (input.isEmpty) return null;

    final img.Decoder? decoder = _decoderFor(input);
    // 动图不压：压完只剩第一帧，用户丢的是动画本身。
    if (decoder is img.GifDecoder) {
      debugPrint('[image] GIF 不压缩（会丢逐帧动画），保留原始字节');
      return null;
    }
    final ImageSize? probed = probeSize(input);
    if (probed == null) {
      debugPrint('[image] 解不出图片尺寸，保留原始字节');
      return null;
    }

    final ImageSize target = fitInside(probed, maxSide);
    if (hasNativeCompressor) {
      final CompressedImage? native =
          await _compressWithNative(input, target, maxSide, quality);
      if (native != null) return native;
    }
    return _compressInDart(input, maxSide, quality);
  }

  static img.Decoder? _decoderFor(Uint8List bytes) {
    try {
      return img.findDecoderForData(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 原生实现：把**已经算好的目标尺寸**传下去。
  ///
  /// 不能只传一个盒子让插件自己算：插件的 minWidth/minHeight 是「至少」语义
  /// （scale = max(1, min(srcW/minW, srcH/minH))，见 BitmapCompressExt.calcScale
  /// 与 UIImage+scale.m），竖图会算出长边 1365 > 1024。传等比后的目标尺寸，
  /// 两条路径的结果才一致。
  static Future<CompressedImage?> _compressWithNative(
    Uint8List input,
    ImageSize target,
    int maxSide,
    int quality,
  ) async {
    try {
      final Uint8List out = await FlutterImageCompress.compressWithList(
        input,
        minWidth: target.width,
        minHeight: target.height,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (out.isEmpty) return null;
      final ImageSize? actual = probeSize(out);
      if (actual == null) return null;
      // 复查：原生按浮点比例取整，允许 1px 误差；明显超出（EXIF 旋转过的照片，
      // 有效宽高与文件里记的转置）就交回纯 Dart 收口。
      if (actual.longSide > maxSide + 1) {
        debugPrint('[image] 原生输出 $actual 超出长边上限 $maxSide，改用纯 Dart 收口');
        return null;
      }
      return CompressedImage(bytes: out, size: actual);
    } catch (e) {
      // 万一还有平台没注册实现，不能让「导出」这一步跟着失败。
      debugPrint('[image] 原生压缩不可用，改用纯 Dart 实现: $e');
      return null;
    }
  }

  /// 纯 Dart 实现（Web / Windows / Linux，以及原生失败时的兜底）。
  ///
  /// 解码 + 缩放是 CPU 密集的（4K 图要一两秒），放 isolate 里做，避免卡界面。
  static Future<CompressedImage?> _compressInDart(
    Uint8List input,
    int maxSide,
    int quality,
  ) async {
    try {
      return await compute(
        _compressInDartTask,
        _DartCompressArgs(input, maxSide, quality),
      );
    } catch (e) {
      debugPrint('[image] 纯 Dart 压缩失败: $e');
      return null;
    }
  }
}

/// [compute] 的入参（跨 isolate 传递的普通数据）。
@immutable
class _DartCompressArgs {
  const _DartCompressArgs(this.input, this.maxSide, this.quality);

  final Uint8List input;
  final int maxSide;
  final int quality;
}

/// 在 isolate 里跑：解码 → 摆正 → 等比缩放 → JPEG 编码。
CompressedImage? _compressInDartTask(_DartCompressArgs args) {
  try {
    final img.Image? decoded = img.decodeImage(args.input);
    if (decoded == null) return null;

    // 与原生对齐：原生默认 autoCorrectionAngle = true，会把 EXIF 旋转烘进像素。
    // 不烘的话导出的 JPEG（编码时丢 EXIF）会变成躺倒的照片。
    final int orientation = decoded.exif.imageIfd.hasOrientation
        ? (decoded.exif.imageIfd.orientation ?? 1)
        : 1;
    final img.Image upright =
        orientation == 1 ? decoded : img.bakeOrientation(decoded);

    final ImageSize fit = ImageCompressor.fitInside(
      ImageSize(upright.width, upright.height),
      args.maxSide,
    );
    final bool needsResize =
        fit.width != upright.width || fit.height != upright.height;
    // 宽高同时给 copyResize 会「拉满成盒子」；这里的两个值由同一个比例算出，
    // 所以不会把图拉成方图（与旧实现的关键差别）。
    final img.Image out = needsResize
        ? img.copyResize(
            upright,
            width: fit.width,
            height: fit.height,
            interpolation: img.Interpolation.linear,
          )
        : upright;

    return CompressedImage(
      bytes: Uint8List.fromList(img.encodeJpg(out, quality: args.quality)),
      size: ImageSize(out.width, out.height),
    );
  } catch (e) {
    debugPrint('[image] 纯 Dart 压缩失败: $e');
    return null;
  }
}
