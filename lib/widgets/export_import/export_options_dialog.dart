import 'package:flutter/material.dart';

import '../../services/conversation_export_import_service.dart';

/// 导出选项。
class ExportOptions {
  const ExportOptions({this.includeCharacterCards = true, this.format = ConversationExportFormat.json});
  final bool includeCharacterCards;
  final ConversationExportFormat format;
}

/// 选择导出格式与是否内嵌角色卡。
Future<ExportOptions?> showExportOptionsDialog({
  required BuildContext context,
  Color? accentColor,
}) async {
  var includeCards = true;
  var format = ConversationExportFormat.json;
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
                accentColor.withValues(alpha: 0.16), base.colorScheme.surface),
            onPrimaryContainer: accentColor,
          ),
        );
  return showDialog<ExportOptions>(
    context: context,
    builder: (ctx) => Theme(
      data: dialogTheme,
      child: AlertDialog(
        title: const Text('导出选项'),
        content: StatefulBuilder(
          builder: (bc, setSB) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('内嵌角色卡'),
                value: includeCards,
                onChanged: (v) => setSB(() => includeCards = v),
              ),
              const SizedBox(height: 8),
              const Text('导出格式'),
              RadioGroup<ConversationExportFormat>(
                groupValue: format,
                onChanged: (v) => setSB(() => format = v!),
                child: Column(
                  children: <Widget>[
                    RadioListTile<ConversationExportFormat>(
                      title: const Text('JSON（可再导入）'),
                      value: ConversationExportFormat.json,
                    ),
                    RadioListTile<ConversationExportFormat>(
                      title: const Text('Markdown（便于阅读）'),
                      value: ConversationExportFormat.markdown,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ExportOptions(includeCharacterCards: includeCards, format: format)),
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
}
