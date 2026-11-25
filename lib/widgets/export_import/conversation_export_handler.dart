import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/conversation_export_import_service.dart';
import '../../services/web_download.dart';
import '../../utils/ui_feedback.dart';

/// 处理导出结果：保存为文件、分享或复制到剪贴板（Web 端）。
///
/// IO 平台先把内容写入临时文件，再走「移动端分享 / 桌面保存对话框」。
///
/// file_picker 13 起 `saveFile` 不再有「只给路径、由调用方写盘」的形式：它必须收
/// bytes 并自己落盘。这里内容本来就已经在内存里（String 或 result.bytes），
/// 再交给 saveFile 不额外增加一份常驻内存；真正需要流式的「全部数据 ZIP」
/// 在 data_settings_page 里走「选目录 + 复制临时文件」。
Future<void> handleExportResult(BuildContext context, ConversationExportResult result) async {
  // 打包成 zip（含附件）时走二进制分支：内容为空、bytes 有值。
  if (result.isBinary) {
    await _handleBinaryExport(context, result);
    return;
  }
  final content = result.content;
  if (kIsWeb) {
    await Clipboard.setData(ClipboardData(text: content));
    if (context.mounted) {
      showSnack(
        context,
        '已复制内容到剪贴板（Web 端）。',
        behavior: SnackBarBehavior.floating,
      );
    }
    return;
  }
  final tmp = File(path.join((await getTemporaryDirectory()).path, result.suggestedFileName));
  await tmp.writeAsString(content);
  // 移动端：分享临时文件
  if (Platform.isAndroid || Platform.isIOS) {
    if (!context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(tmp.path)], subject: 'DNA 对话导出'),
    );
    return;
  }
  // 桌面：saveFile 自己写盘（v13 必须传 bytes）。内容本来就在内存里，
  // 直接编码，不必回头读临时文件。
  final out = await FilePicker.saveFile(
    dialogTitle: '导出对话',
    fileName: result.suggestedFileName,
    bytes: Uint8List.fromList(utf8.encode(content)),
  );
  if (out == null) return;
  if (context.mounted) showSnack(context, '已导出到：${_displayPath(out)}');
}

/// `saveFile` 返回 Uri：本地文件取路径，其它形式保留原样。
String _displayPath(Uri uri) =>
    uri.scheme == 'file' ? uri.toFilePath() : uri.toString();

/// 二进制导出（zip：conversations.json + attachments/*）。
Future<void> _handleBinaryExport(
  BuildContext context,
  ConversationExportResult result,
) async {
  final Uint8List? bytes = result.bytes;
  if (bytes == null) return;
  final String summary = result.attachmentCount > 0
      ? '，含 ${result.attachmentCount} 个附件（${(result.attachmentBytes / 1024 / 1024).toStringAsFixed(1)} MB）'
      : '';
  if (kIsWeb) {
    // Web：Blob + <a download> 直接下载（不依赖临时目录）。
    final bool ok = downloadBytes(
      bytes: bytes,
      fileName: result.suggestedFileName,
      mime: 'application/zip',
    );
    if (!context.mounted) return;
    showSnack(
      context,
      ok
          ? '已开始下载导出包$summary'
          : '浏览器拦下了下载，请允许本站下载后重试$summary',
      behavior: SnackBarBehavior.floating,
    );
    return;
  }
  final File tmp = File(
    path.join((await getTemporaryDirectory()).path, result.suggestedFileName),
  );
  await tmp.writeAsBytes(bytes, flush: true);
  if (Platform.isAndroid || Platform.isIOS) {
    if (!context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(tmp.path)], subject: 'DNA 对话导出$summary'),
    );
    return;
  }
  final Uri? out = await FilePicker.saveFile(
    dialogTitle: '导出对话（含附件）',
    fileName: result.suggestedFileName,
    bytes: bytes,
  );
  if (out == null) return;
  if (context.mounted) showSnack(context, '已导出到：${_displayPath(out)}$summary');
}
