import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'ta_export_import_models.dart';

/// 角色卡 / 世界 / 身份 的「导出到文件 / 从文件导入」统一工具。
///
/// 三者此前只能走剪贴板,本工具补齐文件通道,交互与 `data_settings_page`
/// 的 ZIP 导出保持一致的四分支策略:
/// * Web:交给浏览器下载(`FilePicker.saveFile(bytes:)`);
/// * Android / iOS:先写临时文件,再走系统分享;
/// * 桌面(Windows / macOS / Linux):选保存路径后系统级复制。
///
/// 导入侧统一用 `FilePicker.pickFiles` 读取文本内容。
class ExportFileUtils {
  const ExportFileUtils._();

  /// 可阅读的友好时间戳:`YYYY_MM_DD_小时_分钟_秒`。
  ///
  /// 例:`2026_09_12_23_45_08`。
  static String friendlyTimestamp([DateTime? now]) {
    final DateTime t = (now ?? DateTime.now()).toLocal();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}_${p2(t.month)}_${p2(t.day)}'
        '_${p2(t.hour)}_${p2(t.minute)}_${p2(t.second)}';
  }

  /// 文件名中需要过滤的非法字符(Windows 保留字符 + 路径分隔符 + 控制字符)。
  ///
  /// 仅用于**文件名**,不触碰文件内容。
  static final RegExp _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

  /// 生成导出文件名:`{名称}-{友好时间}.{扩展名}`。
  ///
  /// * [name] 为空时使用 [fallbackName](如「角色」「世界」「身份」)。
  /// * 文件名中的非法字符会被替换为下划线;[name] 本身不做其它改动。
  /// * [ext] 传入不带点的小写扩展名,如 `dnata`。
  static String buildFileName({
    required String name,
    required String fallbackName,
    required String ext,
    DateTime? now,
  }) {
    final String raw = name.trim().isEmpty ? fallbackName : name.trim();
    String safe = raw.replaceAll(_illegal, '_');
    // Windows 不允许文件名以点或空格结尾。
    safe = safe.replaceAll(RegExp(r'[. ]+$'), '');
    if (safe.isEmpty) safe = fallbackName;
    return '$safe-${friendlyTimestamp(now)}.$ext';
  }

  /// 导出文本内容到文件(或 Web 下载)。返回落盘路径;用户取消返回 null。
  ///
  /// [content] 为 JSON 文本,[fileName] 由 [buildFileName] 生成。
  static Future<ExportImportResult<String?>> exportText({
    required String content,
    required String fileName,
    required String ext,
    required String dialogTitle,
  }) async {
    try {
      final Uint8List bytes = Uint8List.fromList(
        const Utf8Encoder().convert(content),
      );

      if (kIsWeb) {
        // Web 无文件系统:交给浏览器触发下载。
        final String? out = await FilePicker.platform.saveFile(
          dialogTitle: dialogTitle,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: <String>[ext],
          bytes: bytes,
        );
        return ExportImportResult(success: true, data: out);
      }

      // 移动端:先写临时文件,再走系统分享(与 ZIP 导出策略一致)。
      if (Platform.isAndroid || Platform.isIOS) {
        final Directory tmpDir = await getTemporaryDirectory();
        final String tmpPath = '${tmpDir.path}/$fileName';
        await File(tmpPath).writeAsBytes(bytes, flush: true);
        await Share.shareXFiles(<XFile>[XFile(tmpPath)], subject: dialogTitle);
        return ExportImportResult(success: true, data: tmpPath);
      }

      // 桌面端:选保存路径后系统级复制(避免大文件走 Dart 内存)。
      final String? out = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: <String>[ext],
      );
      if (out == null) {
        return const ExportImportResult(success: true, data: null);
      }
      final String target = out.toLowerCase().endsWith('.${ext.toLowerCase()}')
          ? out
          : '$out.$ext';
      final Directory tmpDir = await getTemporaryDirectory();
      final String tmpPath = '${tmpDir.path}/$fileName';
      await File(tmpPath).writeAsBytes(bytes, flush: true);
      await File(tmpPath).copy(target);
      try {
        await File(tmpPath).delete();
      } catch (_) {
        // 临时文件清理失败不影响导出结果。
      }
      return ExportImportResult(success: true, data: target);
    } catch (e) {
      return ExportImportResult(success: false, message: '导出到文件失败: $e');
    }
  }

  /// 移动端放开类型过滤后的软校验。
  ///
  /// 扩展名明显不对时返回一句人话；没问题（或根本没有扩展名）返回 null。
  ///
  /// 为什么需要它：Android / iOS 上只能用 [FileType.any]（原因见 [importText]），
  /// 用户这时能选到任意文件。与其让 JSON 解析抛一个看不懂的错，不如直接说清楚。
  /// **没有扩展名的不拦** —— 从聊天软件转存过来的文件常常没有扩展名。
  static String? extensionWarning(String fileName, List<String> exts) {
    final int dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return null;
    final String picked = fileName.substring(dot + 1).toLowerCase();
    final Set<String> accepted = <String>{
      for (final String e in exts) e.toLowerCase(),
      // 兼容用户手工改扩展名 / 其它来源的文件。
      'json',
      'txt',
    };
    if (accepted.contains(picked)) return null;
    final String wanted = exts.map((String e) => '.$e').join(' / ');
    return '这不是可导入的文件（.$picked），请选择 $wanted 文件';
  }

  /// 从文件选择并读取文本内容。用户取消返回 `data == null`。
  ///
  /// [exts] 为允许的扩展名列表(不含点,小写)。同时接受 `json` 以兼容
  /// 用户手工改扩展名或其它来源的文件。
  static Future<ExportImportResult<String?>> importText({
    required List<String> exts,
    required String dialogTitle,
  }) async {
    try {
      // **移动端必须用 FileType.any。**
      //
      // file_picker 在 Android / iOS 上是把 allowedExtensions 映射成 **MIME
      // 类型** 去过滤的（Android 走 android.webkit.MimeTypeMap）。.dnata /
      // .dnaworld / .dnapersona 这类自定义扩展名不在系统 MIME 表里，映射结果
      // 是 null —— 文件被**置灰选不中**，列表里还显示成 "BIN"
      // （application/octet-stream）。
      //
      // 桌面 / Web 保持 FileType.custom：那边是按扩展名字符串过滤的，自定义
      // 扩展名工作正常，能保住「只看到该看的文件」这个体验。
      final bool mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        dialogTitle: dialogTitle,
        type: mobile ? FileType.any : FileType.custom,
        allowedExtensions: mobile ? null : exts,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        return const ExportImportResult(success: true, data: null);
      }

      final PlatformFile f = picked.files.first;

      // 移动端放开了类型过滤，这里补一道软校验。
      if (mobile) {
        final String? warning = extensionWarning(f.name, exts);
        if (warning != null) {
          return ExportImportResult(success: false, message: warning);
        }
      }

      // Web / 已带字节:直接用内存数据。
      final Uint8List? bytes = f.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        return ExportImportResult(
          success: true,
          data: const Utf8Decoder(allowMalformed: true).convert(bytes),
        );
      }

      // IO 平台:按路径读取(带 withData 时通常也有 bytes,此处兜底)。
      final String? path = f.path;
      if (path == null || path.isEmpty) {
        return const ExportImportResult(
          success: false,
          message: '无法读取所选文件',
        );
      }
      final String text = await File(path).readAsString();
      return ExportImportResult(success: true, data: text);
    } catch (e) {
      return ExportImportResult(success: false, message: '读取文件失败: $e');
    }
  }
}
