import 'dart:convert';
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
Future<void> handleExportResult(BuildContext context, ConversationExportResult result) async {
  final content = result.content;
  final bytes = Uint8List.fromList(utf8.encode(content));
  if (kIsWeb) {
    await Clipboard.setData(ClipboardData(text: content));
    if (context.mounted)
      showSnack(
        context,
        '已复制内容到剪贴板（Web 端）。',
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      );
    return;
  }
  if (Platform.isIOS) {
    final tmp = File(path.join((await getTemporaryDirectory()).path, result.suggestedFileName));
    await tmp.writeAsString(content);
    if (!context.mounted) return;
    await Share.shareXFiles(<XFile>[XFile(tmp.path)], subject: 'DNA 对话导出');
    return;
  }
  final out = await FilePicker.platform.saveFile(
    dialogTitle: '导出对话',
    fileName: result.suggestedFileName,
    type: FileType.custom,
    allowedExtensions: <String>[path.extension(result.suggestedFileName).replaceFirst('.', '')],
    bytes: bytes,
  );
  if (out == null) return;
  var saved = out;
  if (!Platform.isAndroid) {
    final f = File(out.endsWith('.json') || out.endsWith('.md') ? out : '$out.${path.extension(result.suggestedFileName).replaceFirst('.', '')}');
    await f.writeAsBytes(bytes);
    saved = f.path;
  }
  if (context.mounted) showSnack(context, '已导出到：$saved');
}
