import 'dart:io';

import 'package:flutter/material.dart';

import '../models/ta.dart';
import '../state/app_controller.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_drawer.dart';
import 'delete_confirm_page.dart';
import 'delete_preview_builders.dart';
import 'ta_editor_page.dart';
import 'package:dna/widgets/fit_text.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _showArchived = false;

  void _toggleArchived() {
    setState(() => _showArchived = !_showArchived);
  }

  void _createTa() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => TaEditorPage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      controller: widget.controller,
      current: AppSection.myHome,
      appBar: AppBar(
        title: FitText(_showArchived ? 'TA归档' : '我家'),
        actions: <Widget>[
          IconButton(
            tooltip: _showArchived ? '查看TA' : '查看归档',
            onPressed: _toggleArchived,
            icon: Icon(_showArchived ? Icons.people_outline : Icons.archive_outlined),
          ),
          if (!_showArchived)
            IconButton(
              tooltip: '创建TA',
              onPressed: _createTa,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: _TaListBody(
        controller: widget.controller,
        showArchived: _showArchived,
        onCreateTa: _createTa,
      ),
      bottomNavigationBar: widget.controller.settings.showBottomNav
          ? AppBottomNav(controller: widget.controller, current: AppSection.myHome)
          : null,
      floatingActionButton: !_showArchived
          ? FloatingActionButton(
              onPressed: _createTa,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _TaListBody extends StatelessWidget {
  const _TaListBody({
    required this.controller,
    required this.showArchived,
    required this.onCreateTa,
  });

  final AppController controller;
  final bool showArchived;
  final VoidCallback onCreateTa;

  @override
  Widget build(BuildContext context) {
    // 缓存 theme 数据
    final TextTheme textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final List<TA> tas = controller.tas
            .where((TA t) => t.archived == showArchived)
            .toList();

        if (tas.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FitText(showArchived ? '还没有归档TA。' : '暂无TA，先创建一个吧。'),
                const SizedBox(height: 12),
                if (!showArchived)
                  FilledButton.icon(
                    onPressed: onCreateTa,
                    icon: const Icon(Icons.add),
                    label: const FitText('创建TA'),
                  ),
              ],
            ),
          );
        }

        return ReorderableListView.builder(
          padding: const EdgeInsets.all(16),
          buildDefaultDragHandles: false,
          itemCount: tas.length,
          onReorder: (int oldIndex, int newIndex) async { // ignore: deprecated_member_use
            await controller.reorderTas(oldIndex, newIndex);
          },
          itemBuilder: (BuildContext context, int index) {
            final TA ta = tas[index];
            return _TaItem(
              key: ValueKey<String>(ta.id),
              controller: controller,
              ta: ta,
              textTheme: textTheme,
            );
          },
        );
      },
    );
  }
}

class _TaItem extends StatelessWidget {
  const _TaItem({
    super.key,
    required this.controller,
    required this.ta,
    required this.textTheme,
  });

  final AppController controller;
  final TA ta;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final String? square = ta.images['square'];
    final bool hasImage = square != null && square.isNotEmpty;

    return Card(
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => TaEditorPage(
                controller: controller,
                ta: ta,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              hasImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(square),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        // 限制图片解码大小，避免内存问题
                        cacheWidth: 128,
                        cacheHeight: 128,
                      ),
                    )
                  : const CircleAvatar(
                      radius: 32,
                      child: Icon(Icons.person_outline),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FitText(ta.name.isEmpty ? '未命名TA' : ta.name),
                    const SizedBox(height: 6),
                    FitText(
                      ta.intro.isEmpty ? '暂无介绍' : ta.intro,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (ta.tags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ta.tags
                            .map((String tag) => Chip(label: FitText(tag)))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              ReorderableDragStartListener(
                index: ta.archived ? -1 : 0,
                child: const Icon(Icons.drag_handle),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (String value) async {
                  if (value == 'archive') {
                    await controller.setTaArchived(
                      id: ta.id,
                      archived: true,
                    );
                  } else if (value == 'unarchive') {
                    await controller.setTaArchived(
                      id: ta.id,
                      archived: false,
                    );
                  } else if (value == 'delete') {
                    if (!context.mounted) {
                      return;
                    }
                    final bool? deleted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (BuildContext context) => DeleteConfirmPage(
                          controller: controller,
                          title: '删除角色',
                          entityName: ta.name,
                          validNames: <String>[ta.name],
                          promptHint: '请完整输入角色名「${ta.name}」以确认删除',
                          contentBuilder: (BuildContext ctx) =>
                              buildTaPreviewSections(ctx, ta),
                          onDelete: () => controller.deleteTaWithBackup(ta.id),
                          requireName: controller.settings.requireNameToDelete,
                        ),
                      ),
                    );
                    if (deleted == true && context.mounted) {
                      // 删除页已自行提示，这里无需额外操作。
                    }
                  }
                },
                itemBuilder: (BuildContext context) {
                  if (ta.archived) {
                    return <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'unarchive',
                        child: ListTile(
                          leading: Icon(Icons.unarchive_outlined),
                          title: FitText('恢复'),
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: FitText('删除'),
                        ),
                      ),
                    ];
                  }
                  return <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'archive',
                      child: ListTile(
                        leading: Icon(Icons.archive_outlined),
                        title: FitText('归档'),
                      ),
                    ),
                  ];
                },
                child: const Icon(Icons.more_vert),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
