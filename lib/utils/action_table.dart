import 'dart:async';

import 'package:flutter/material.dart';

import '../services/export_file_utils.dart';
import '../services/ta_export_import_models.dart';
import '../widgets/export_import/transport_source_dialog.dart';
import 'dialogs.dart';
import 'ui_feedback.dart';

/// **动作表**：把「一排可执行的动作」写成数据，而不是每个页面各抄一遍。
///
/// 收的是三类重复（`docs/PAGE_DATA_DRIVEN_AUDIT.md` 的「动作表」一节）：
/// 1. 编辑器的「放弃修改？」确认 —— 5 个外壳逐字相同；
/// 2. 导出 / 导入的三段式接线 —— 身份、世界、角色包各 100~200 行；
/// 3. 行内菜单（每行可见项随状态变）—— 一堆 `switch` + 条件 `PopupMenuItem`。
///
/// 这一层只管**流程与展示**，不管数据：内容怎么序列化、导入后怎么回填，
/// 都由调用方通过 `buildContent` / `parse` / 返回值传进来。

/// 「放弃未保存的修改？」确认（文案与原来手写实现逐字一致）。
///
/// 返回 true 表示用户选择放弃；false 表示继续编辑。
Future<bool> confirmDiscardEdits(BuildContext context) {
  return showConfirmDialog(
    context: context,
    title: '放弃修改？',
    content: '还有未保存的修改，返回会丢失。',
    cancelText: '继续编辑',
    confirmText: '放弃',
  );
}

/// 行内动作：一条 = id + 文案 + 可见条件 + 执行体。
class RowAction {
  const RowAction({
    required this.id,
    required this.label,
    required this.onSelected,
    this.icon,
    this.visible = true,
    this.danger = false,
    this.enabled = true,
  });

  final String id;
  final String label;
  final VoidCallback onSelected;
  final IconData? icon;

  /// 当前行状态下是否出现（例如「重新提审」只在被拒时出现）。
  final bool visible;

  /// 危险动作（删除 / 隐藏）用 error 色。
  final bool danger;

  /// 当前是否可点（忙碌中置灰，但仍显示 —— 与原来 `enabled: false` 的观感一致）。
  final bool enabled;
}

/// 是否还有可见动作（页面据此决定要不要渲染菜单按钮）。
bool hasVisibleRowAction(List<RowAction> actions) =>
    actions.any((RowAction a) => a.visible);

/// 把动作表渲染成行尾的「更多操作」菜单。
///
/// 调用方先用 [hasVisibleRowAction] 判断，菜单里至少有一条可见项。
Widget rowActionMenu({
  required List<RowAction> actions,
  String tooltip = '更多操作',
}) {
  final List<RowAction> visible = actions
      .where((RowAction a) => a.visible)
      .toList(growable: false);
  assert(visible.isNotEmpty, 'rowActionMenu: 没有可见动作时不要渲染菜单');
  return PopupMenuButton<String>(
    tooltip: tooltip,
    onSelected: (String id) {
      for (final RowAction a in visible) {
        if (a.id == id) {
          a.onSelected();
          return;
        }
      }
    },
    itemBuilder: (BuildContext context) {
      final ColorScheme scheme = Theme.of(context).colorScheme;
      return <PopupMenuEntry<String>>[
        for (final RowAction a in visible)
          PopupMenuItem<String>(
            value: a.id,
            enabled: a.enabled,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (a.icon != null) ...<Widget>[
                  Icon(a.icon, size: 18, color: a.danger ? scheme.error : null),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    a.label,
                    style: a.danger ? TextStyle(color: scheme.error) : null,
                  ),
                ),
              ],
            ),
          ),
      ];
    },
  );
}

/// 导出动作：询问目的地 → 生成内容 → 剪贴板 / 文件 → 结果提示。
///
/// 顺序、提示文案与「取消不报错」的语义都与原来手写实现一致。
class ExportActionSpec {
  const ExportActionSpec({
    required this.title,
    required this.description,
    required this.fallbackName,
    required this.fileExt,
    required this.buildContent,
    required this.copyToClipboard,
    this.extraOptions,
    this.fileDialogTitle,
    this.onBeforeBuild,
    this.copySuccessMessage = '已复制到剪贴板，可以粘贴分享',
    this.copyFailedMessage,
  });

  /// 目的地询问弹窗的标题（如「导出身份」）。
  final String title;

  /// 目的地询问弹窗的说明。
  final String description;

  /// 文件名兜底（实体没名字时用）。
  final String fallbackName;

  /// 扩展名（如 `dnapersona`）。
  final String fileExt;

  /// 生成导出文本；失败时自行返回 failure 结果。
  ///
  /// 允许异步（角色卡要先把图片压进包里再序列化）。
  final FutureOr<ExportImportResult<String>> Function() buildContent;

  /// 复制到剪贴板。
  final Future<ExportImportResult<void>> Function(String data) copyToClipboard;

  /// 目的地弹窗里的额外选项（如角色卡的「压缩图片」勾选）。
  final Widget? extraOptions;

  /// 文件保存对话框的标题；不传就用 [title]（角色卡两者不同）。
  final String? fileDialogTitle;

  /// 生成内容之前的提示（如「正在导出…」）。
  final VoidCallback? onBeforeBuild;

  /// 复制成功的提示。
  final String copySuccessMessage;

  /// 复制失败的提示；**传了就用它**（原文里有硬编码文案，不读 message）。
  final String? copyFailedMessage;
}

/// 执行一次导出（提示统一走 [showSnack]）。
Future<void> runExportAction(
  BuildContext context,
  ExportActionSpec spec, {
  required String entityName,
}) async {
  final ExportTarget? target = await showExportTargetDialog(
    context: context,
    title: spec.title,
    description: spec.description,
    extraOptions: spec.extraOptions,
  );
  if (target == null || !context.mounted) return;

  spec.onBeforeBuild?.call();
  final ExportImportResult<String> result = await spec.buildContent();
  if (!context.mounted) return;
  if (!result.success) {
    showSnack(context, result.message ?? '导出失败');
    return;
  }

  if (target == ExportTarget.clipboard) {
    final ExportImportResult<void> copyResult = await spec.copyToClipboard(
      result.data!,
    );
    if (!context.mounted) return;
    showSnack(
      context,
      copyResult.success
          ? spec.copySuccessMessage
          : (spec.copyFailedMessage ?? copyResult.message ?? '复制失败'),
      behavior: SnackBarBehavior.floating,
    );
    return;
  }

  final ExportImportResult<String?> fileResult =
      await ExportFileUtils.exportText(
        content: result.data!,
        fileName: ExportFileUtils.buildFileName(
          name: entityName,
          fallbackName: spec.fallbackName,
          ext: spec.fileExt,
        ),
        ext: spec.fileExt,
        dialogTitle: spec.fileDialogTitle ?? spec.title,
      );
  if (!context.mounted) return;
  if (!fileResult.success) {
    showSnack(context, fileResult.message ?? '导出到文件失败');
    return;
  }
  showSnack(
    context,
    fileResult.data == null ? '已取消导出' : '已导出到：\${fileResult.data}',
    behavior: SnackBarBehavior.floating,
  );
}

/// 导入动作：询问来源 → 读文本 → 解析 → 交给调用方回填。
class ImportActionSpec<T> {
  const ImportActionSpec({
    required this.title,
    required this.description,
    required this.fileDialogTitle,
    required this.acceptedExts,
    required this.pasteFromClipboard,
    required this.parse,
    this.successMessage,
    this.onImported,
  });

  final String title;
  final String description;
  final String fileDialogTitle;
  final List<String> acceptedExts;
  final Future<ExportImportResult<String>> Function() pasteFromClipboard;

  /// 解析（允许异步：角色卡导入要先解包并写图片）。
  final FutureOr<ExportImportResult<T>> Function(String content) parse;

  /// 解析成功后的提示；不传就由 [onImported] 自己决定什么时候弹。
  final String? successMessage;

  /// 解析成功、返回之前的收尾（角色卡要在这里恢复图片、回填并弹提示）。
  ///
  /// 在它跑完之前不会弹 [successMessage]，所以「正在导入图片… → 导入成功」
  /// 这种多段提示的顺序能保持原样。
  final Future<void> Function(T data)? onImported;
}

/// 执行一次导入，成功时返回解析结果（调用方负责回填表单）。
///
/// 用户取消、读取失败、解析失败都返回 null 并给出对应提示 ——
/// 与原来手写实现的三段式一致。
Future<T?> runImportAction<T>(
  BuildContext context,
  ImportActionSpec<T> spec,
) async {
  final ImportSource? source = await showImportSourceDialog(
    context: context,
    title: spec.title,
    description: spec.description,
  );
  if (source == null || !context.mounted) return null;

  final String? content;
  if (source == ImportSource.clipboard) {
    final ExportImportResult<String> pasteResult = await spec
        .pasteFromClipboard();
    if (!context.mounted) return null;
    if (!pasteResult.success) {
      showSnack(context, pasteResult.message ?? '读取剪贴板失败');
      return null;
    }
    content = pasteResult.data;
  } else {
    final ExportImportResult<String?> fileResult =
        await ExportFileUtils.importText(
          exts: spec.acceptedExts,
          dialogTitle: spec.fileDialogTitle,
        );
    if (!context.mounted) return null;
    if (!fileResult.success) {
      showSnack(context, fileResult.message ?? '读取文件失败');
      return null;
    }
    if (fileResult.data == null) return null; // 用户取消
    content = fileResult.data;
  }

  if (content == null || content.isEmpty) {
    if (!context.mounted) return null;
    showSnack(context, '没有可导入的内容');
    return null;
  }

  final ExportImportResult<T> imported = await spec.parse(content);
  if (!context.mounted) return null;
  if (!imported.success) {
    showSnack(context, imported.message ?? '导入失败');
    return null;
  }
  final T? parsed = imported.data;
  if (parsed == null) return null;
  await spec.onImported?.call(parsed);
  if (!context.mounted) return parsed;
  final String? message = spec.successMessage;
  if (message != null) {
    showSnack(context, message, behavior: SnackBarBehavior.floating);
  }
  return parsed;
}
