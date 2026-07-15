import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../services/conversation_export_import_service.dart';
import '../utils/ui_feedback.dart';

/// 导出选项
class ExportOptions {
  const ExportOptions({
    required this.format,
    required this.includeCharacterCards,
  });

  final ConversationExportFormat format;
  final bool includeCharacterCards;
}

/// 多选对话对话框
///
/// 返回选中的对话 ID 列表；取消或为空返回 null。
Future<List<String>?> showConversationPickerDialog({
  required BuildContext context,
  required List<Conversation> conversations,
  required Map<String, String> nameById,
}) async {
  final Set<String> selected = <String>{};
  return showDialog<List<String>>(
    context: context,
    builder: (BuildContext ctx) {
      return StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setState) {
          return AlertDialog(
            title: const Text('选择要导出的对话'),
            content: SizedBox(
              width: double.maxFinite,
              child: conversations.isEmpty
                  ? const Text('暂无对话。')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: conversations.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Conversation c = conversations[index];
                        final bool checked = selected.contains(c.id);
                        final String name = nameById[c.id] ?? '未命名对话';
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                selected.add(c.id);
                              } else {
                                selected.remove(c.id);
                              }
                            });
                          },
                          title: Text(name),
                          subtitle: Text(c.isGroup ? '群聊' : '单聊'),
                        );
                      },
                    ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(selected.toList()),
                child: const Text('下一步'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// 导出选项对话框（格式 + 是否内嵌角色卡）
Future<ExportOptions?> showExportOptionsDialog({
  required BuildContext context,
}) async {
  ConversationExportFormat format = ConversationExportFormat.json;
  bool includeCharacterCards = true;

  final ExportOptions? result = await showDialog<ExportOptions>(
    context: context,
    builder: (BuildContext ctx) {
      return StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setState) {
          return AlertDialog(
            title: const Text('导出选项'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('格式', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<ConversationExportFormat>(
                  segments: const <ButtonSegment<ConversationExportFormat>>[
                    ButtonSegment<ConversationExportFormat>(
                      value: ConversationExportFormat.json,
                      label: Text('JSON'),
                    ),
                    ButtonSegment<ConversationExportFormat>(
                      value: ConversationExportFormat.markdown,
                      label: Text('Markdown'),
                    ),
                  ],
                  selected: <ConversationExportFormat>{format},
                  onSelectionChanged: (Set<ConversationExportFormat> sel) {
                    setState(() => format = sel.first);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('内嵌角色卡'),
                  subtitle: const Text('JSON 模式下勾选后，会把角色设定（含图片）一并打包，'
                      '对方导入时可选择新建角色。Markdown 模式固定不含。'),
                  value: includeCharacterCards,
                  onChanged: format == ConversationExportFormat.markdown
                      ? null
                      : (bool value) =>
                          setState(() => includeCharacterCards = value),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  ExportOptions(
                    format: format,
                    includeCharacterCards: includeCharacterCards,
                  ),
                ),
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    },
  );
  return result;
}

/// 导入时的角色决议对话框
///
/// [needed] 为对话引用到的角色；[existingTas] 为本地已有角色。
/// 返回与 [needed] 顺序一致的决议列表；取消返回 null。
Future<List<CharacterImportDecision>?> showCharacterResolutionDialog({
  required BuildContext context,
  required List<NeededCharacter> needed,
  required List<TA> existingTas,
}) async {
  // 每个角色的初始抉择
  final List<bool> importAsNew = <bool>[];
  final List<String?> chosenExisting = <String?>[];
  for (int i = 0; i < needed.length; i++) {
    final NeededCharacter n = needed[i];
    // 有卡默认“导入新角色”；无卡必须选已有角色
    importAsNew.add(n.hasCard);
    // 不自动选择：让用户在导入时手动指定对应角色
    chosenExisting.add(null);
  }

  return showDialog<List<CharacterImportDecision>>(
    context: context,
    builder: (BuildContext ctx) {
      return StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setState) {
          return AlertDialog(
            title: const Text('选择角色归属'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: needed.length,
                itemBuilder: (BuildContext context, int index) {
                  final NeededCharacter n = needed[index];
                  final bool useExisting = !importAsNew[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            n.hasCard
                                ? '角色卡：${n.cardName ?? n.originalTaId}'
                                : '未包含角色卡（ID：${n.originalTaId}）',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          if (n.hasCard)
                            SegmentedButton<bool>(
                              segments: const <ButtonSegment<bool>>[
                                ButtonSegment<bool>(
                                  value: true,
                                  label: Text('导入此卡'),
                                ),
                                ButtonSegment<bool>(
                                  value: false,
                                  label: Text('替换已有'),
                                ),
                              ],
                              selected: <bool>{importAsNew[index]},
                              onSelectionChanged: (Set<bool> sel) {
                                setState(() => importAsNew[index] = sel.first);
                              },
                            )
                          else
                            const Text('请选择对应的已有角色：'),
                          const SizedBox(height: 8),
                          if (useExisting)
                            DropdownButton<String>(
                              isExpanded: true,
                              value: chosenExisting[index],
                              hint: const Text('选择角色'),
                              items: existingTas
                                  .map(
                                    (TA ta) => DropdownMenuItem<String>(
                                      value: ta.id,
                                      child: Text(
                                        ta.name.isNotEmpty ? ta.name : '未命名角色',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (String? value) {
                                setState(() => chosenExisting[index] = value);
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  // 校验：选择“替换已有”的必须有对应角色
                  for (int i = 0; i < needed.length; i++) {
                    if (!importAsNew[i] &&
                        (chosenExisting[i] == null || chosenExisting[i]!.isEmpty)) {
                      showSnack(context, '请为所有角色选择对应已有角色');
                      return;
                    }
                  }
                  final List<CharacterImportDecision> decisions =
                      <CharacterImportDecision>[];
                  for (int i = 0; i < needed.length; i++) {
                    decisions.add(
                      CharacterImportDecision(
                        originalTaId: needed[i].originalTaId,
                        importAsNew: importAsNew[i],
                        existingTaId:
                            importAsNew[i] ? null : chosenExisting[i],
                      ),
                    );
                  }
                  Navigator.of(context).pop(decisions);
                },
                child: const Text('确定导入'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// 导出完成后的保存 / 分享动作
Future<void> handleExportResult(
  BuildContext context,
  ConversationExportResult result,
) async {
  final String? action = await showDialog<String>(
    context: context,
    builder: (BuildContext ctx) {
      return AlertDialog(
        title: const Text('导出完成'),
        content: const Text('选择如何处理导出的对话：'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('clipboard'),
            child: const Text('复制到剪贴板'),
          ),
          if (result.suggestedFileName.endsWith('.md'))
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('share'),
              child: const Text('分享文本'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('file'),
            child: const Text('保存到文件'),
          ),
        ],
      );
    },
  );
  if (action == null || !context.mounted) return;

  if (action == 'clipboard') {
    await Clipboard.setData(ClipboardData(text: result.content));
    if (context.mounted) showSnack(context, '已复制到剪贴板');
    return;
  }

  if (action == 'share') {
    await Share.share(result.content);
    return;
  }

  // 保存到文件
  final Uint8List bytes = utf8.encode(result.content);
  final String? outPath = await FilePicker.platform.saveFile(
    dialogTitle: '保存对话导出',
    fileName: result.suggestedFileName,
    bytes: bytes,
  );
  if (outPath == null) return;
  // 移动端（Android/iOS）saveFile 已直接写入字节；桌面端需自行写入用户选择的路径。
  if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
    final String ext = path.extension(result.suggestedFileName);
    final String finalPath =
        outPath.toLowerCase().endsWith(ext.toLowerCase()) ? outPath : '$outPath$ext';
    final File file = File(finalPath);
    await file.writeAsString(result.content);
    if (context.mounted) showSnack(context, '已导出到：${file.path}');
  } else {
    if (context.mounted) showSnack(context, '已导出到：$outPath');
  }
}
