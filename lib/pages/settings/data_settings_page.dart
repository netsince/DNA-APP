import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/conversation.dart';
import '../../services/conversation_export_import_service.dart';
import '../../services/data_backup_service.dart';
import '../../services/ta_export_import_service.dart';
import '../../state/app_controller.dart';
import '../../utils/dialogs.dart';
import '../../utils/ui_feedback.dart';
import '../../widgets/conversation_export_import_dialogs.dart';
import 'package:dna/widgets/fit_text.dart';

class DataSettingsPage extends StatefulWidget {
  const DataSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<DataSettingsPage> createState() => _DataSettingsPageState();
}

class _DataSettingsPageState extends State<DataSettingsPage> {
  bool _exporting = false;
  bool _importing = false;
  bool _exportingConv = false;
  bool _importingConv = false;
  bool _autoBackup = true;

  String _ts() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${p(d.month)}${p(d.day)}_${p(d.hour)}${p(d.minute)}${p(d.second)}';
  }

  // ---- All data export ----

  Future<void> _exportAll() async {
    setState(() => _exporting = true);
    try {
      if (kIsWeb) {
        // Web 无文件系统：保持整体字节，由浏览器触发下载
        final r = await widget.controller.exportAllData();
        if (!mounted) return;
        if (!r.success || r.data == null) { showSnack(context, r.message ?? '导出失败'); return; }
        final out = await FilePicker.platform.saveFile(
          dialogTitle: '导出全部数据为 ZIP', fileName: 'DNA_${_ts()}.zip',
          type: FileType.custom, allowedExtensions: <String>['zip'], bytes: r.data!,
        );
        if (!mounted) return;
        showSnack(context, out == null ? '已取消导出' : '已导出：$out');
        return;
      }
      // IO 平台：流式写临时 ZIP（内存峰值仅单文件，避免 Android OOM）
      final tmp = File(path.join((await getTemporaryDirectory()).path, 'DNA_${_ts()}.zip'));
      final r = await widget.controller.exportAllDataToFile(tmp.path);
      if (!mounted) return;
      if (!r.success || r.data == null) { showSnack(context, r.message ?? '导出失败'); return; }
      // 移动端：分享临时文件；桌面：选保存路径后系统级复制
      if (Platform.isAndroid || Platform.isIOS) {
        await Share.shareXFiles(<XFile>[XFile(tmp.path)], subject: 'DNA 全部数据导出');
        return;
      }
      final out = await FilePicker.platform.saveFile(
        dialogTitle: '导出全部数据为 ZIP', fileName: 'DNA_${_ts()}.zip',
        type: FileType.custom, allowedExtensions: <String>['zip'],
      );
      if (out == null) return;
      final target = out.endsWith('.zip') ? out : '$out.zip';
      // File.copy 为系统级流式复制，不走 Dart 内存
      await File(tmp.path).copy(target);
      if (!mounted) return;
      showSnack(context, '已导出到：$target');
    } catch (e) { if (mounted) showSnack(context, '导出出错：$e');
    } finally { if (mounted) setState(() => _exporting = false); }
  }

  // ---- All data import ----

  Future<bool?> _pickMode({required String desc}) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const FitText('导入方式'),
      content: FitText(desc),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const FitText('仅追加')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const FitText('全部替换')),
      ],
    ),
  );

  Future<void> _showReport(DataImportReport r, {bool onlyConv = false}) async {
    final sb = StringBuffer();
    if (!onlyConv) { sb.writeln('角色：${r.tasCount}'); sb.writeln('世界：${r.worldsCount}'); }
    sb.writeln('对话：${r.conversationsCount}');
    if (r.replaced) {
      if (r.backupPath != null) {
        sb.writeln('\n替换前的数据已自动备份至：\n${r.backupPath}');
      } else if (r.backupError != null) {
        sb.writeln('\n⚠️ 自动备份失败：${r.backupError}');
      }
    }
    if (!mounted) return;
    await showInfoDialog(context: context, title: '导入完成', content: FitText(sb.toString()));
  }

  Future<void> _importAll() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择备份 ZIP', type: FileType.custom,
      allowedExtensions: <String>['zip'], withData: kIsWeb,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final replaceAll = await _pickMode(
      desc: '全部替换：清空现有数据后导入；替换前的数据会自动备份为一个 ZIP。\n\n仅追加：只添加新的角色 / 世界 / 对话，已有数据保留。',
    );
    if (replaceAll == null) return;
    setState(() => _importing = true);
    try {
      final ExportImportResult<DataImportReport> r;
      if (kIsWeb) {
        // Web 无文件路径，只能读取字节；内部同样走流式解码
        final bytes = f.bytes;
        if (bytes == null) { if (mounted) showSnack(context, '无法读取文件内容。'); return; }
        r = await widget.controller.importData(bytes, replaceAll: replaceAll);
      } else {
        // IO 平台：直接用文件路径流式导入，避免大 ZIP 整体载入内存（修复 Android OOM）
        final path = f.path;
        if (path == null) { if (mounted) showSnack(context, '无法读取文件内容。'); return; }
        r = await widget.controller.importDataFromPath(path, replaceAll: replaceAll);
      }
      if (!mounted) return;
      if (!r.success || r.data == null) { showSnack(context, r.message ?? '导入失败'); return; }
      await _showReport(r.data!);
    } catch (e) { if (mounted) showSnack(context, '导入出错：$e');
    } finally { if (mounted) setState(() => _importing = false); }
  }

  // ---- Conversation export ----

  String _convName(Conversation c) {
    if (c.isGroup) return c.groupName.trim().isNotEmpty ? c.groupName.trim() : '群聊';
    final n = widget.controller.getTaById(c.taId)?.name;
    return (n != null && n.isNotEmpty) ? n : '未命名对话';
  }

  Future<void> _exportConv() async {
    setState(() => _exportingConv = true);
    try {
      final convs = widget.controller.allConversations;
      final nameById = <String, String>{for (final c in convs) c.id: _convName(c)};
      final sel = await showConversationPickerDialog(
        context: context, conversations: convs, nameById: nameById,
      );
      if (!mounted || sel == null || sel.isEmpty) return;
      final opts = await showExportOptionsDialog(context: context);
      if (opts == null) return;
      final r = await widget.controller.exportConversationsById(
        sel, includeCharacterCards: opts.includeCharacterCards, format: opts.format,
      );
      if (!mounted) return;
      if (!r.success || r.data == null) { showSnack(context, r.message ?? '导出失败'); return; }
      await handleExportResult(context, r.data!);
    } catch (e) { if (mounted) showSnack(context, '导出出错：$e');
    } finally { if (mounted) setState(() => _exportingConv = false); }
  }

  // ---- Conversation import ----

  List<NeededCharacter> _buildNeeded(ConversationImportData data) {
    final list = <NeededCharacter>[];
    for (final taId in data.collectTaIds()) {
      final pkg = data.embeddedPackages[taId];
      String? cardName;
      if (pkg != null && pkg['character'] is Map) {
        final n = (pkg['character'] as Map)['name'];
        if (n is String && n.isNotEmpty) cardName = n;
      }
      list.add(NeededCharacter(originalTaId: taId, hasCard: pkg != null, cardName: cardName));
    }
    return list;
  }

  Future<void> _importConv() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择对话 JSON', type: FileType.custom,
      allowedExtensions: <String>['json'], withData: kIsWeb,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    // JSON 解析必须整体读入（jsonDecode 需要完整字符串），但 IO 平台直接
    // readAsString 避免 readAsBytes + utf8.decode 的两次字节拷贝。
    final String? json = kIsWeb
        ? (f.bytes != null ? utf8.decode(f.bytes!) : null)
        : (f.path != null ? await File(f.path!).readAsString() : null);
    if (json == null) { if (mounted) showSnack(context, '无法读取文件内容。'); return; }
    final parsed = widget.controller.parseConversationImportJson(json);
    if (!mounted) return;
    if (!parsed.success || parsed.data == null) { showSnack(context, parsed.message ?? '导入失败'); return; }
    final data = parsed.data!;
    final decisions = await showCharacterResolutionDialog(
      context: context, needed: _buildNeeded(data), existingTas: widget.controller.tas,
    );
    if (decisions == null) return;
    final replaceAll = await _pickMode(
      desc: '全部替换：清空现有对话后导入；替换前的对话会自动备份为一个 ZIP。\n\n仅追加：只添加新的对话，已有对话保留。',
    );
    if (replaceAll == null) return;
    setState(() => _importingConv = true);
    try {
      final r = await widget.controller.applyConversationImport(data, decisions, replaceAll: replaceAll);
      if (!mounted) return;
      if (!r.success || r.data == null) { showSnack(context, r.message ?? '导入失败'); return; }
      await _showReport(r.data!, onlyConv: true);
    } catch (e) { if (mounted) showSnack(context, '导入出错：$e');
    } finally { if (mounted) setState(() => _importingConv = false); }
  }

  @override
  void initState() {
    super.initState();
    _autoBackup = widget.controller.settings.autoBackup;
  }

  Future<void> _saveAutoBackup(bool v) =>
      widget.controller.saveAutoBackup(v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('数据管理')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 1. 每日自动备份 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.backup_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('每日自动备份', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '每天首次进入应用时自动备份至设备公共目录（滚动保留最近 5 天），卸载应用亦不丢失。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('开启每日静默自动备份'),
                    subtitle: kIsWeb
                        ? const FitText('当前平台不支持（Web 无本地文件系统）')
                        : const FitText('后台自动执行，全程无弹窗打扰'),
                    value: _autoBackup,
                    onChanged: kIsWeb
                        ? null
                        : (v) {
                            setState(() => _autoBackup = v);
                            _saveAutoBackup(v);
                          },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 2. 全量数据备份与还原 (ZIP) =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.archive_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('全量数据备份与还原 (ZIP)', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '将全部角色、世界设定与对话记录打包为单文件，支持跨设备迁移与完整还原。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: _exporting || _importing ? null : _exportAll,
                        icon: _exporting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_outlined),
                        label: FitText(_exporting ? '导出中...' : '导出全量备份 ZIP'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exporting || _importing ? null : _importAll,
                        icon: _importing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload_file_outlined),
                        label: FitText(_importing ? '导入中...' : '从 ZIP 恢复数据'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 3. 单项对话导出与导入 (JSON) =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.forum_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('单项对话导出与导入 (JSON)', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '选择单场对话导出为 JSON 文件（可内嵌角色卡）或单独导入，方便单剧本分享。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: _exportingConv || _importingConv ? null : _exportConv,
                        icon: _exportingConv
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_outlined),
                        label: FitText(_exportingConv ? '导出中...' : '导出指定对话'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportingConv || _importingConv ? null : _importConv,
                        icon: _importingConv
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload_file_outlined),
                        label: FitText(_importingConv ? '导入中...' : '从 JSON 导入对话'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
