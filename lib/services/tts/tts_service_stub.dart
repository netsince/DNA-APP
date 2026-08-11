import 'dart:typed_data';

/// 端侧语音合成服务的 Web 空实现。
///
/// Web 平台不支持 onnxruntime（dart:ffi），语音合成在 UI 层已通过
/// [PlatformCapabilities] 置灰禁用。此 stub 保证编译通过并提供安全的
/// 默认行为（模型不可用 / 合成抛错），不触碰任何原生 API。
class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  bool _downloading = false;

  String? get modelsDir => null;

  /// 检查模型是否已全部下载就绪（Web 上恒为 false）。
  Future<bool> isModelsReady() async => false;

  /// 只下载缺失的模型文件（Web 上直接报错，不会触发任何网络/磁盘操作）。
  Future<void> ensureModels({
    void Function(TtsDownloadProgress)? onProgress,
  }) async {
    if (_downloading) return;
    _downloading = true;
    try {
      throw StateError('当前平台不支持端侧语音合成');
    } finally {
      _downloading = false;
    }
  }

  /// 合成文本（Web 上直接抛错）。
  Future<Float32List> synthesize(
    String text, {
    int? roleSeed,
    int? globalSeed,
    bool doRefine = true,
    bool useCache = true,
    bool quoteOnly = true,
    void Function(double progress)? onProgress,
  }) async {
    throw StateError('当前平台不支持端侧语音合成');
  }

  /// 删除已下载的全部模型文件（Web 上空操作）。
  Future<void> deleteModels() async {}
}

/// 模型下载进度（与 IO 实现同构，保证调用方类型兼容）。
class TtsDownloadProgress {
  const TtsDownloadProgress({
    required this.doneFiles,
    required this.totalFiles,
    required this.currentFile,
    required this.receivedBytes,
    this.totalBytes,
    this.speedBps,
  });

  final int doneFiles;
  final int totalFiles;
  final String currentFile;
  final int receivedBytes;
  final int? totalBytes;
  final double? speedBps;
}
