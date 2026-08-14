import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/conversation_export_import_service.dart';
import '../../utils/ui_feedback.dart';

/// 处理导出结果：保存为文件、分享或复制到剪贴板（Web 端）。
///
/// IO 平台先把内容写入临时文件，再走「移动端分享 / 桌面选择路径后系统级复制」，
/// 避免把大文本/大 JSON 通过 saveFile(bytes:) 整体传入 MethodChannel 导致 OOM。
Future<void> handleExportResult(BuildContext context, ConversationExportResult result) async {
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
