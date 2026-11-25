import 'package:material_ui/material_ui.dart';
import 'package:dna/theme/tokens.dart';

import '../../services/conversation_export_import_service.dart';
import 'package:dna/widgets/fit_text.dart';

/// 导出选项。
class ExportOptions {
  const ExportOptions({
    this.includeCharacterCards = true,
    this.format = ConversationExportFormat.json,
    this.includeAttachments = true,
  });

  final bool includeCharacterCards;
  final ConversationExportFormat format;

  /// 是否把聊天附件（图片/文件）一起打包。
  ///
  /// 打包后是 zip：同一份文件按内容只存一份，不会因为「三条消息引用了同一张图」
  /// 就把图存三遍。
  final bool includeAttachments;
}

/// 选择导出格式与是否内嵌角色卡。
Future<ExportOptions?> showExportOptionsDialog({
  required BuildContext context,
  Color? accentColor,
  bool hasAttachments = false,
}) async {
  var includeCards = true;
  var format = ConversationExportFormat.json;
  var includeAttachments = true;
  final ThemeData base = Theme.of(context);
  final ThemeData dialogTheme = accentColor == null
      ? base
      : base.copyWith(
          colorScheme: base.colorScheme.copyWith(
            primary: accentColor,
            onPrimary: ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
                ? Colors.white
                : Colors.black,
            primaryContainer: Color.alphaBlend(
                accentColor.withValues(alpha: AppAlpha.a16), base.colorScheme.surface),
            onPrimaryContainer: accentColor,
          ),
        );
  return showDialog<ExportOptions>(
    context: context,
    builder: (ctx) => Theme(
      data: dialogTheme,
      child: AlertDialog(
        title: const FitText('导出选项'),
        content: StatefulBuilder(
          builder: (bc, setSB) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const FitText('内嵌角色卡'),
                value: includeCards,
                onChanged: (v) => setSB(() => includeCards = v),
              ),
              if (hasAttachments)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const FitText('包含聊天附件'),
                  subtitle: const FitText('打包成 zip，同一份文件只存一份'),
                  value: includeAttachments,
                  onChanged: (v) => setSB(() => includeAttachments = v),
                ),
              const SizedBox(height: 8),
              const FitText('导出格式'),
              RadioGroup<ConversationExportFormat>(
                groupValue: format,
                onChanged: (v) => setSB(() => format = v!),
                child: Column(
                  children: <Widget>[
                    RadioListTile<ConversationExportFormat>(
                      title: const FitText('JSON（可再导入）'),
                      value: ConversationExportFormat.json,
                    ),
                    RadioListTile<ConversationExportFormat>(
                      title: const FitText('Markdown（便于阅读）'),
                      value: ConversationExportFormat.markdown,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const FitText('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              ExportOptions(
                includeCharacterCards: includeCards,
                format: format,
                includeAttachments: hasAttachments && includeAttachments,
              ),
            ),
            child: const FitText('确定'),
          ),
        ],
      ),
    ),
  );
}
