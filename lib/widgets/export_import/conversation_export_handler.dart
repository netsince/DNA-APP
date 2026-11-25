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
/// IO 平台先把内容写入临时文件，再走「移动端分享 / 桌面选择路径后系统级复制」，
/// 避免把大文本/大 JSON 通过 saveFile(bytes:) 整体传入 MethodChannel 导致 OOM。
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
    await Share.shareXFiles(<XFile>[XFile(tmp.path)], subject: 'DNA 对话导出');
    return;
  }
  // 桌面：选择保存路径后系统级复制（不走 Dart 内存）
  final out = await FilePicker.platform.saveFile(
    dialogTitle: '导出对话',
    fileName: result.suggestedFileName,
    type: FileType.custom,
    allowedExtensions: <String>[path.extension(result.suggestedFileName).replaceFirst('.', '')],
  );
  if (out == null) return;
  final String ext = path.extension(result.suggestedFileName);
  final target = out.endsWith(ext) ? out : '$out$ext';
  await tmp.copy(target);
  if (context.mounted) showSnack(context, '已导出到：$target');
}

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
    await Share.shareXFiles(<XFile>[XFile(tmp.path)], subject: 'DNA 对话导出$summary');
    return;
  }
  final String? out = await FilePicker.platform.saveFile(
    dialogTitle: '导出对话（含附件）',
    fileName: result.suggestedFileName,
    type: FileType.custom,
    allowedExtensions: const <String>['zip'],
  );
  if (out == null) return;
  final String target = out.toLowerCase().endsWith('.zip') ? out : '$out.zip';
  await tmp.copy(target);
  if (context.mounted) showSnack(context, '已导出到：$target$summary');
}
