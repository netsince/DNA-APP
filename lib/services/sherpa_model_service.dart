import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/voice_models.dart';

/// 语音识别（sherpa-onnx）模型的一个下载来源。
class SherpaModelSource {
  const SherpaModelSource({
    required this.id,
    required this.label,
    required this.baseUrl,
    this.isCustom = false,
  });

  final String id;
  final String label;

  /// 资源根地址（不含末尾斜杠）。
  final String baseUrl;
  final bool isCustom;

  /// 拼接某个模型资源文件的完整下载地址。
  String urlFor(String fileName) => '$baseUrl/$fileName';
}

/// 预置来源：ModelScope（默认，国内直连）与 GitHub Releases（回退）。
///
/// ModelScope 原始文件地址经核实为：
/// https://modelscope.cn/models/zhaochaoqun/sherpa-onnx-asr-models/resolve/master/&lt;file&gt;
/// 若版本变动导致不可用，可在设置中改用「自定义服务器」或「GitHub」。
const List<SherpaModelSource> kPresetSherpaSources = <SherpaModelSource>[
  SherpaModelSource(
    id: 'modelscope',
    label: 'ModelScope（国内镜像）',
    baseUrl:
        'https://modelscope.cn/models/zhaochaoqun/sherpa-onnx-asr-models/resolve/master',
  ),
  SherpaModelSource(
    id: 'github',
    label: 'GitHub Releases',
    baseUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models',
  ),
];

/// 应用内模型根目录名。
const String kSherpaModelDirName = 'sherpa_models';

/// 严格构造指定 id 的单个来源（不探测、不回退）。
///
/// [id] 为 'modelscope' / 'github' / 'custom'。'custom' 必须提供非空
/// [customBaseUrl]，否则返回 null。用于「手动单选」场景：下载失败即报错，
/// 不会切换到其它来源。
SherpaModelSource? buildSherpaSource({
  required String id,
  String? customBaseUrl,
}) {
  if (id == 'custom') {
    if (customBaseUrl == null || customBaseUrl.trim().isEmpty) return null;
    return SherpaModelSource(
      id: 'custom',
      label: '自定义服务器',
      baseUrl: customBaseUrl.trim().replaceAll(RegExp(r'/$'), ''),
      isCustom: true,
    );
  }
  for (final SherpaModelSource s in kPresetSherpaSources) {
    if (s.id == id) return s;
  }
  return null;
}

/// 生成「自动选择」时的候选来源顺序：自定义服务器（若提供）> 偏好预置源 > 其余。
///
/// 仅用于自动模式：按顺序逐个尝试下载，前一个失败则回退到下一个。
List<SherpaModelSource> orderedSherpaCandidates({
  String? customBaseUrl,
  String preferredPreset = 'modelscope',
}) {
  final List<SherpaModelSource> list = <SherpaModelSource>[];

  if (customBaseUrl != null && customBaseUrl.trim().isNotEmpty) {
    list.add(
      SherpaModelSource(
        id: 'custom',
        label: '自定义服务器',
        baseUrl: customBaseUrl.trim().replaceAll(RegExp(r'/$'), ''),
        isCustom: true,
      ),
    );
  }

  final List<SherpaModelSource> ordered = <SherpaModelSource>[
    ...kPresetSherpaSources
  ];
  ordered.sort((SherpaModelSource a, SherpaModelSource b) {
    final int rankA = a.id == preferredPreset ? 0 : 1;
    final int rankB = b.id == preferredPreset ? 0 : 1;
    return rankA.compareTo(rankB);
  });
  list.addAll(ordered);
  return list;
}

/// 语音模型下载与解压结果。
class SherpaDownloadResult {
  const SherpaDownloadResult({
    required this.success,
    this.message,
    this.modelDir,
  });

  final bool success;
  final String? message;

  /// 模型解压后的目录（成功时非空）。
  final String? modelDir;
}

/// sherpa-onnx 模型下载 / 解压服务。
///
/// 仅负责把模型资源拉到应用私有目录，不涉及录音与识别（由 [SpeechToTextService] 使用）。
class SherpaModelDownloadService {
  /// 单此请求的全局超时（含连接与传输），避免单个失效源长时间挂起。
  static const Duration _requestTimeout = Duration(seconds: 30);

  /// 下载并解压指定 [model] 到 `<文档目录>/sherpa_models/<model.id>`。
  ///
  /// 严格使用给定 [source]，不做任何回退；网络/HTTP 错误会作为失败的
  /// [SherpaDownloadResult] 返回（不抛异常）。
  ///
  /// [onProgress] 回调整体进度：[progress] 为 0~1（无总长度时为 null），
  /// [received]/[total] 为已下载/总字节数，[speedBps] 为当前速度（字节/秒）。
  static Future<SherpaDownloadResult> downloadModel({
    required SherpaModelSource source,
    required VoiceModelOption model,
    void Function(double? progress, int received, int? total, double? speedBps)?
        onProgress,
  }) async {
    final Directory docDir = await getApplicationDocumentsDirectory();
    final Directory baseDir =
        Directory(path.join(docDir.path, kSherpaModelDirName));
    final Directory modelDir =
        Directory(path.join(baseDir.path, model.id));
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
    await modelDir.create(recursive: true);

    final http.Client client = http.Client();
    // 临时文件：流式写入磁盘，绝不在内存中攒整包（避免 List<int> 8 字节/元素撑爆内存）。
    final File tmpFile = File(path.join(baseDir.path, '.${model.id}.part'));
    IOSink? sink;
    try {
      final http.Request request =
          http.Request('GET', Uri.parse(source.urlFor(model.fileName)));
      final http.StreamedResponse response = await client.send(request).timeout(
        _requestTimeout,
        onTimeout: () =>
            throw const SocketException('连接或下载超时'),
      );

      if (response.statusCode != 200) {
        return SherpaDownloadResult(
          success: false,
          message:
              '来源「${source.label}」下载失败（HTTP ${response.statusCode}）',
        );
      }

      final int? total = response.contentLength;
      int received = 0;
      int lastReceived = 0;
      DateTime lastStamp = DateTime.now();

      sink = tmpFile.openWrite();
      await for (final List<int> chunk in response.stream.timeout(
        _requestTimeout,
        onTimeout: (EventSink<List<int>> sink) {
          sink.close();
          throw const SocketException('下载中断（超时）');
        },
      )) {
        sink.add(chunk);
        received += chunk.length;

        final DateTime now = DateTime.now();
        final int dtMs = now.difference(lastStamp).inMilliseconds;
        if (dtMs >= 250) {
          final double dtSec = dtMs / 1000;
          final double speed = (received - lastReceived) / dtSec;
          final double? progress =
              total != null && total > 0 ? received / total : null;
          onProgress?.call(progress, received, total, speed);
          lastReceived = received;
          lastStamp = now;
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      onProgress?.call(total != null && total > 0 ? 1.0 : null, received, total,
          null);

      await _extractTarBz2(tmpFile, modelDir);
      // 解压完成后删除压缩包
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
      return SherpaDownloadResult(success: true, modelDir: modelDir.path);
    } on SocketException catch (e) {
      return SherpaDownloadResult(
        success: false,
        message: '来源「${source.label}」连接失败：${e.message}',
      );
    } catch (e) {
      return SherpaDownloadResult(
        success: false,
        message: '来源「${source.label}」下载失败：$e',
      );
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // 忽略：下载已失败，关闭失败不影响错误处理
      }
      client.close();
    }
  }

  /// 删除某个已下载模型的目录。
  static Future<void> deleteModel(String modelId) async {
    final Directory docDir = await getApplicationDocumentsDirectory();
    final Directory modelDir = Directory(
      path.join(docDir.path, kSherpaModelDirName, modelId),
    );
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
  }

  /// 解压 .tar.bz2 文件 [compressed] 到 [target]。
  static Future<void> _extractTarBz2(File compressed, Directory target) async {
    final Uint8List compressedBytes = await compressed.readAsBytes();
    final Uint8List tarBytes = BZip2Decoder().decodeBytes(compressedBytes);
    // compressedBytes 已完成使命，置空便于 GC 尽早回收，降低峰值内存。
    final Archive archive = TarDecoder().decodeBytes(tarBytes);
    for (final ArchiveFile file in archive.files) {
      final String outPath = path.join(target.path, file.name);
      if (file.isFile) {
        final File outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      }
    }
  }
}
