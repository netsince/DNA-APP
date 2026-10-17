import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/world_import_sink.dart';
import 'package:dna/models/world.dart';
import 'package:dna/theme/tokens.dart';

/// 发布世界卡：从本地世界里挑一个，发到社区。
///
/// 发布走的是**裸 World.toJson()**，不是 WorldExportImportService.exportWorld
/// 的带信封格式 —— 服务端只读顶层的 name / summary / tags / entries，套一层
/// world:{...} 它就读不到了。
class WorldPublishPage extends StatefulWidget {
  const WorldPublishPage({super.key, this.source, this.publisher});

  /// 本地世界来源（窄接口）。为空时页面只给提示。
  final WorldPublishSource? source;

  /// 发布回调（测试可注入）。为空时走 [ApiClient.publishWorld]。
  final Future<Map<String, dynamic>> Function(String rawJson)? publisher;

  @override
  State<WorldPublishPage> createState() => _WorldPublishPageState();
}

class _WorldPublishPageState extends State<WorldPublishPage> {
  String? _publishingId;
  String? _publishedId;

  Future<void> _publish(World world) async {
    if (_publishingId != null) return;
    setState(() => _publishingId = world.id);
    try {
      final String raw = jsonEncode(world.toJson());
      final Future<Map<String, dynamic>> Function(String)? publish =
          widget.publisher;
      final Map<String, dynamic> result = publish != null
          ? await publish(raw)
          : await ApiClient.instance.publishWorld(raw);
      if (!mounted) return;
      setState(() => _publishedId = world.id);
      final bool reused = result['reused'] == true;
      _toast(reused ? '这个世界之前已经提交过，正在审核中' : '已提交，等待审核');
    } catch (e) {
      if (!mounted) return;
      _toast('发布失败：$e');
    } finally {
      if (mounted) setState(() => _publishingId = null);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final List<World> worlds =
        widget.source?.localWorlds() ?? const <World>[];
    return Scaffold(
      appBar: AppBar(title: const Text('发布世界卡')),
      body: worlds.isEmpty ? _empty(context) : _list(context, worlds),
    );
  }

  Widget _empty(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.public_off_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            AppSpacing.hMd,
            Text(
              widget.source == null
                  ? '当前环境没有可读取的本地世界'
                  : '你还没有创建过世界，先在「世界」里建一个吧',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<World> worlds) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return ListView.separated(
      itemCount: worlds.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final World w = worlds[index];
        final bool publishing = _publishingId == w.id;
        final bool published = _publishedId == w.id;
        return ListTile(
          title: Text(w.name.isEmpty ? '未命名世界' : w.name),
          subtitle: Text(
            <String>[
              if (w.entries.isNotEmpty) '${w.entries.length} 词条',
              if (w.summary.isNotEmpty) w.summary,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: publishing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : published
                  ? Icon(Icons.check, color: cs.primary)
                  : FilledButton.tonal(
                      onPressed: () => _publish(w),
                      child: const Text('发布'),
                    ),
        );
      },
    );
  }
}
