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
import '../../state/app_controller.dart';
import '../../utils/dialogs.dart';
import '../../utils/ui_feedback.dart';
import '../../widgets/conversation_export_import_dialogs.dart';

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

  String _ts() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${p(d.month)}${p(d.day)}_${p(d.hour)}${p(d.minute)}${p(d.second)}';
  }

  // ---- All data export ----

  Future<void> _exportAll() async {
    setState(() => _exporting = true);
    try {
      final r = await widget.controller.exportAllData();
      if (!mounted) return;
      if (!r.success || r.data == null) { showSnack(context, r.message ?? '导出失败'); return; }
      final data = r.data!;
      if (!kIsWeb && Platform.isIOS) {
        final tmp = File(path.join((await getTemporaryDirectory()).path, 'DNA_${_ts()}.zip'));
        await tmp.writeAsBytes(data);
        if (!mounted) return;
        await Share.shareXFiles(<XFile>[XFile(tmp.path)], subject: 'DNA 全部数据导出');
        return;
      }
      final out = await FilePicker.platform.saveFile(
        dialogTitle: '导出全部数据为 ZIP', fileName: 'DNA_${_ts()}.zip',
        type: FileType.custom, allowedExtensions: <String>['zip'], bytes: data,
      );
      if (out == null) return;
      var saved = out;
      if (!kIsWeb && !Platform.isAndroid) {
        final f = File(out.endsWith('.zip') ? out : '$out.zip');
        await f.writeAsBytes(data);
        saved = f.path;
      }
      if (!mounted) return;
      showSnack(context, '已导出到：$saved');
    } catch (e) { if (mounted) showSnack(context, '导出出错：$e');
    } finally { if (mounted) setState(() => _exporting = false); }
  }

  // ---- All data import ----

  Future<bool?> _pickMode({required String desc}) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('导入方式'),
      content: Text(desc),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('仅追加')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('全部替换')),
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
    await showInfoDialog(context: context, title: '导入完成', content: Text(sb.toString()));
  }

  Future<void> _importAll() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择备份 ZIP', type: FileType.custom,
      allowedExtensions: <String>['zip'], withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) { if (mounted) showSnack(context, '无法读取文件内容。'); return; }
    final replaceAll = await _pickMode(
      desc: '全部替换：清空现有数据后导入；替换前的数据会自动备份为一个 ZIP。\n\n仅追加：只添加新的角色 / 世界 / 对话，已有数据保留。',
    );
    if (replaceAll == null) return;
    setState(() => _importing = true);
    try {
      final r = await widget.controller.importData(bytes, replaceAll: replaceAll);
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
      allowedExtensions: <String>['json'], withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) { if (mounted) showSnack(context, '无法读取文件内容。'); return; }
    final parsed = widget.controller.parseConversationImportJson(utf8.decode(bytes));
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('全部数据', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('将全部数据（角色、世界、对话，不含设置）打包为 ZIP 文件，或从 ZIP 导入。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _exporting || _importing ? null : _exportAll,
                icon: _exporting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.archive_outlined),
                label: Text(_exporting ? '导出中...' : '导出全部数据'),
              ),
              OutlinedButton.icon(
                onPressed: _exporting || _importing ? null : _importAll,
                icon: _importing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file_outlined),
                label: Text(_importing ? '导入中...' : '从 ZIP 导入'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('仅对话', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('导出为 JSON（可内嵌角色卡）或 Markdown，方便阅读与分享。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _exportingConv || _importingConv ? null : _exportConv,
                icon: _exportingConv
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.forum_outlined),
                label: Text(_exportingConv ? '导出中...' : '导出对话'),
              ),
              OutlinedButton.icon(
                onPressed: _exportingConv || _importingConv ? null : _importConv,
                icon: _importingConv
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file_outlined),
                label: Text(_importingConv ? '导入中...' : '从 JSON 导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
