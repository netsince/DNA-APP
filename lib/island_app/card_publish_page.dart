import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/card_payload.dart';
import 'package:dna/island_app/card_publish_source.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/pages/ta_editor_page.dart';
import 'package:dna/services/export_file_utils.dart';
import 'package:dna/services/ta_export_import_service.dart';
import 'package:dna/theme/tokens.dart';

/// 发布角色卡：从本地角色卡里挑一个，**点一下就发**；也可以新建或导入。
///
/// 表单不再自己拼一套 —— 新建 / 导入走软件本体的角色编辑器（TaEditorPage），
/// 保存即发布；已有角色卡直接映射成 payload 提交。映射在 card_payload.dart 里，
/// 发布与编辑共用一份。
class CardPublishBody extends StatefulWidget {
  const CardPublishBody({super.key, this.source, this.publisher});

  /// 本地角色卡来源（窄接口）。为空时页面只给提示。
  final CardPublishSource? source;

  /// 发布回调（测试可注入）。为空时走 [ApiClient.publishCard]。
  final Future<void> Function(Map<String, dynamic> payload)? publisher;

  @override
  State<CardPublishBody> createState() => _CardPublishBodyState();
}

class _CardPublishBodyState extends State<CardPublishBody> {
  final TextEditingController _jsonController = TextEditingController();
  bool _showJson = false;

  /// 正在发布 / 已发布的角色卡 id（列表行上的状态）。
  String? _publishingId;
  final Set<String> _published = <String>{};

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _publish(TA ta) async {
    final Future<void> Function(Map<String, dynamic>)? publisher =
        widget.publisher;
    await (publisher ?? ApiClient.instance.publishCard)(
      taToPublishPayload(ta, images: await taImageDataUrls(ta)),
    );
  }

  /// 列表行：点一下就发。失败把服务端的原话带回来（图片比例、字段校验等）。
  Future<void> _publishExisting(TA ta) async {
    if (_publishingId != null) return;
    setState(() => _publishingId = ta.id);
    try {
      await _publish(ta);
      if (!mounted) return;
      setState(() => _published.add(ta.id));
      _toast('已提交，等待审核');
    } catch (e) {
      _toast('发布失败：$e');
    } finally {
      if (mounted) setState(() => _publishingId = null);
    }
  }

  /// 新建 / 编辑：打开软件本体的角色编辑器，保存 = 发布。
  Future<void> _openEditor(TA? initial) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaEditorPage(
          ta: initial,
          title: initial == null ? '发布角色卡' : '编辑并发布',
          saveLabel: '发布到社区',
          onSave: (TA ta) async {
            await _publish(ta);
            if (mounted) _toast('已提交，等待审核');
          },
        ),
      ),
    );
  }

  /// 快速导出 JSON（复制到剪贴板，不弹文件框）。
  Future<void> _exportJson(TA ta) async {
    try {
      final ExportImportResult<String> result =
          await TaExportImportService.exportCharacter(ta);
      if (!result.success || result.data == null) {
        _toast(result.message ?? '导出失败');
        return;
      }
      await Clipboard.setData(ClipboardData(text: result.data!));
      _toast('已复制角色卡 JSON 到剪贴板');
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  /// 从一段文本导入：解析成 TA 后打开编辑器确认（导入的卡常常缺封面）。
  Future<void> _importFromText(String text) async {
    if (text.trim().isEmpty) {
      _toast('没有可识别的内容');
      return;
    }
    final ExportImportResult<ImportResult> parsed =
        TaExportImportService.importCharacter(text);
    final TA? ta = parsed.data?.ta;
    if (ta == null) {
      _toast(parsed.message ?? '无法识别这份角色卡');
      return;
    }
    if (!mounted) return;
    await _openEditor(ta);
  }

  Future<void> _importFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    await _importFromText((data?.text ?? '').trim());
  }

  Future<void> _importFromFile() async {
    final ExportImportResult<String?> picked = await ExportFileUtils.importText(
      exts: const <String>['dnacard', 'json'],
      dialogTitle: '选择角色卡文件',
    );
    if (!mounted) return;
    if (!picked.success) {
      _toast(picked.message ?? '读取文件失败');
      return;
    }
    if (picked.data == null) return;
    await _importFromText(picked.data!);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<TA> cards = widget.source?.localCards() ?? const <TA>[];

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            widget.source == null
                ? '当前环境没有可读取的本地角色卡'
                : '选一张本地角色卡直接发布，或者新建 / 导入一份。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: () => _openEditor(null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建角色卡并发布'),
              ),
              OutlinedButton.icon(
                onPressed: _importFromClipboard,
                icon: const Icon(Icons.content_paste_go_outlined, size: 18),
                label: const Text('从剪贴板识别'),
              ),
              OutlinedButton.icon(
                onPressed: _importFromFile,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('导入 .dnacard'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _showJson = !_showJson),
                icon: const Icon(Icons.data_object, size: 18),
                label: const Text('从 JSON 识别'),
              ),
            ],
          ),
        ),
        if (_showJson)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _jsonController,
                  minLines: 6,
                  maxLines: 12,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '在此粘贴角色卡 JSON（.dnacard 信封或酒馆角色卡）…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                AppSpacing.hXs,
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => _importFromText(_jsonController.text),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('识别并继续'),
                  ),
                ),
              ],
            ),
          ),
        AppSpacing.hMd,
        if (cards.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              '或从本地角色卡开始',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        if (widget.source != null && cards.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: Center(
              child: Text(
                '你还没有创建过角色卡，先在「角色卡」里建一个吧',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final TA ta in cards) _row(context, ta),
      ],
    );
  }

  Widget _row(BuildContext context, TA ta) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool publishing = _publishingId == ta.id;
    final bool published = _published.contains(ta.id);

    return ListTile(
      title: Text(
        ta.name.isEmpty ? '未命名角色' : ta.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        <String>[
          if (ta.tags.isNotEmpty) ta.tags.take(3).map((String t) => '#$t').join(' '),
          if (ta.intro.isNotEmpty) ta.intro,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: '导出 JSON',
            icon: const Icon(Icons.ios_share, size: 20),
            onPressed: () => _exportJson(ta),
          ),
          if (publishing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (published)
            Icon(Icons.check, color: cs.primary)
          else
            FilledButton.tonal(
              onPressed: () => _publishExisting(ta),
              child: const Text('发布'),
            ),
        ],
      ),
    );
  }
}

/// 独立页面形态（从别处 push 进来时用）。
class CardPublishPage extends StatelessWidget {
  const CardPublishPage({super.key, this.source, this.publisher});

  final CardPublishSource? source;
  final Future<void> Function(Map<String, dynamic> payload)? publisher;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发布角色卡')),
      body: CardPublishBody(source: source, publisher: publisher),
    );
  }
}
