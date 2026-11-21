import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/message_attachment.dart';
import 'attachment_storage.dart';
import 'image_compressor.dart';

/// 文本类塞进 prompt 的预览长度（比存储层的全文上限小得多：
/// 全文进上下文，预览只用于气泡展示与「发了什么」的回看）。
const int kAttachmentPreviewChars = 4000;

// 上限只有一份真值，在存储层：kMaxAttachmentBytes / kMaxImageBytes / kMaxTextChars。
// 这里直接复用，避免「intake 收 20MB、存储层以为 10MB」这类分叉。
const int kAttachmentMaxBytes = kMaxAttachmentBytes;
const int kAttachmentMaxImageBytes = kMaxImageBytes;
const int kAttachmentMaxTextChars = kMaxTextChars;

/// 图片附件的长边上限：够模型看清细节，又不至于把请求体撑爆。
const int kAttachmentImageLongSide = 1568;

/// 附件接入的结果。
class AttachmentIntakeResult {
  const AttachmentIntakeResult({this.attachment, this.error});

  final MessageAttachment? attachment;

  /// 失败原因（人类可读，直接展示给用户；成功时为 null）。
  final String? error;

  bool get ok => attachment != null;
}

/// 把「用户选中的东西」变成可发送的 [MessageAttachment]。
///
/// 三件事都收在这一个入口，避免调用方各写一份：
/// 1. **体积限制**：单文件 > 20MB、图片压缩后 > 5MB 直接拒绝；
/// 2. **归一化**：图片一律压到长边 1568 内（够模型看，又不至于把请求撑爆）；
/// 3. **内容寻址存储**：交给 [AttachmentStore]，同一份内容只落一次盘。
class AttachmentIntake {
  AttachmentIntake._();

  static final AttachmentIntake instance = AttachmentIntake._();

  final ImagePicker _picker = ImagePicker();

  /// 从系统文件选择器挑文件（多选，最多 [maxCount] 个）。
  Future<List<AttachmentIntakeResult>> pickFiles({int maxCount = 3}) async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (picked == null) return const <AttachmentIntakeResult>[];
    final List<AttachmentIntakeResult> out = <AttachmentIntakeResult>[];
    for (final PlatformFile file in picked.files.take(maxCount)) {
      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        out.add(const AttachmentIntakeResult(
          error: '读不到文件内容（权限不足或文件过大）',
        ));
        continue;
      }
      out.add(await _ingest(
        bytes: bytes,
        fileName: file.name,
        declaredSize: file.size,
        mime: _mimeOfName(file.name),
      ));
    }
    return out;
  }

  /// 从相册挑图片（可多选，PC 上同样可用）。
  Future<List<AttachmentIntakeResult>> pickGallery({int maxCount = 3}) async {
    final List<XFile> picked = await _picker.pickMultiImage(
      maxWidth: 4096,
      maxHeight: 4096,
    );
    if (picked.isEmpty) return const <AttachmentIntakeResult>[];
    final List<AttachmentIntakeResult> out = <AttachmentIntakeResult>[];
    for (final XFile file in picked.take(maxCount)) {
      final Uint8List bytes = await file.readAsBytes();
      out.add(await _ingest(
        bytes: bytes,
        fileName: file.name.isEmpty ? 'image.jpg' : file.name,
        declaredSize: bytes.length,
        mime: file.mimeType ?? _mimeOfName(file.name),
        forceImage: true,
      ));
    }
    return out;
  }

  /// 拍照（PC 上没有相机，调用方负责不展示这个入口）。
  Future<AttachmentIntakeResult?> pickCamera() async {
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 4096,
      maxHeight: 4096,
    );
    if (shot == null) return null;
    final Uint8List bytes = await shot.readAsBytes();
    return _ingest(
      bytes: bytes,
      fileName: shot.name.isEmpty ? 'camera.jpg' : shot.name,
      declaredSize: bytes.length,
      mime: shot.mimeType ?? 'image/jpeg',
      forceImage: true,
    );
  }

  /// 统一入口：限制 → 压缩 → 抽文本 → 存盘 → 生成描述。
  Future<AttachmentIntakeResult> _ingest({
    required Uint8List bytes,
    required String fileName,
    required int declaredSize,
    required String mime,
    bool forceImage = false,
  }) async {
    if (declaredSize > kAttachmentMaxBytes) {
      return AttachmentIntakeResult(
        error: '「$fileName」太大（${_mb(declaredSize)}），单个文件不能超过 '
            '${_mb(kAttachmentMaxBytes)}',
      );
    }
    final bool isImage = forceImage || mime.startsWith('image/');
    Uint8List payload = bytes;
    String ext = _extOf(fileName);

    if (isImage) {
      final Uint8List? compressed = await _compressImage(bytes);
      if (compressed != null) {
        payload = compressed;
        ext = 'jpg';
      }
      if (payload.length > kAttachmentMaxImageBytes) {
        return AttachmentIntakeResult(
          error: '图片「$fileName」压缩后仍有 ${_mb(payload.length)}，'
              '请换一张小一点的（上限 ${_mb(kAttachmentMaxImageBytes)}）',
        );
      }
    }

    String kind = 'file';
    String? preview;
    int textChars = 0;
    if (isImage) {
      kind = 'image';
    } else if (_looksTextual(fileName, mime)) {
      kind = 'text';
      final String decoded = _decodeText(payload);
      textChars = decoded.length;
      final String capped = decoded.length > kAttachmentMaxTextChars
          ? decoded.substring(0, kAttachmentMaxTextChars)
          : decoded;
      preview = capped.length > kAttachmentPreviewChars
          ? capped.substring(0, kAttachmentPreviewChars)
          : capped;
    }

    final String ref = await AttachmentStore.instance.save(payload, ext: ext);
    return AttachmentIntakeResult(
      attachment: MessageAttachment(
        ref: ref,
        name: fileName,
        mime: isImage ? 'image/jpeg' : mime,
        size: payload.length,
        kind: kind,
        textPreview: preview,
        textChars: textChars,
      ),
    );
  }

  Future<Uint8List?> _compressImage(Uint8List bytes) async {
    // 平台差异由 ImageCompressor 一个入口处理（它不抛异常，解不出来返回 null）。
    final CompressedImage? compressed = await ImageCompressor.compress(
      bytes,
      maxSide: kAttachmentImageLongSide,
      quality: 82,
    );
    if (compressed == null) return null;
    // 压缩反而变大（小图/已高度压缩）时保留原图。
    return compressed.bytes.length < bytes.length ? compressed.bytes : bytes;
  }

  static bool _looksTextual(String name, String mime) {
    if (mime.startsWith('text/')) return true;
    const List<String> textExts = <String>[
      'md', 'markdown', 'txt', 'json', 'yaml', 'yml', 'csv', 'tsv',
      'xml', 'html', 'htm', 'log', 'dart', 'js', 'ts', 'py', 'java',
      'kt', 'c', 'h', 'cpp', 'cs', 'go', 'rs', 'rb', 'php', 'sh', 'sql',
      'toml', 'ini', 'conf',
    ];
    final String ext = _extOf(name);
    if (textExts.contains(ext)) return true;
    return mime == 'application/json' || mime == 'application/xml';
  }

  static String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  static String _extOf(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'bin';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _mimeOfName(String name) {
    switch (_extOf(name)) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'json':
        return 'application/json';
      case 'md':
      case 'txt':
      case 'csv':
      case 'log':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  static String _mb(int bytes) =>
      '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
