import 'package:flutter/material.dart';

import '../models/world.dart';
import '../state/app_controller.dart';
import '../widgets/app_container.dart';
import '../widgets/app_section.dart';
import 'delete_confirm_page.dart';
import 'delete_preview_builders.dart';
import 'world_editor_page.dart';
import '../theme/tokens.dart';
import 'package:dna/widgets/app_empty_state.dart';
import 'package:dna/widgets/fit_text.dart';

/// 世界栏目装配。
SectionPageData worldSection(AppController controller) {
  final ValueNotifier<bool> showArchived = ValueNotifier<bool>(false);

  void createWorld(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            WorldEditorPage(controller: controller),
      ),
    );
  }

  return SectionPageData(
    section: AppSection.world,
    showArchived: showArchived,
    appBar: (BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: showArchived,
      builder: (BuildContext context, bool archived, Widget? _) => AppBar(
        title: FitText(archived ? '世界归档' : '世界'),
        actions: <Widget>[
          IconButton(
            tooltip: archived ? '查看世界' : '查看归档',
            onPressed: () => showArchived.value = !archived,
            icon: Icon(
              archived ? Icons.public_outlined : Icons.archive_outlined,
            ),
          ),
          if (!archived)
            IconButton(
              tooltip: '创建世界',
              onPressed: () => createWorld(context),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
    ),
    body: (BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: showArchived,
      builder: (BuildContext context, bool archived, Widget? _) =>
          WorldListBody(
            controller: controller,
            showArchived: archived,
            onCreateWorld: () => createWorld(context),
          ),
    ),
    fab: (BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: showArchived,
      builder: (BuildContext context, bool archived, Widget? _) => !archived
          // FAB 即源容器:圆形按钮放大为整页编辑器。
          ? AppContainer<bool>(
              closedShape: const CircleBorder(),
              closedBuilder: (BuildContext context, VoidCallback open) =>
                  FloatingActionButton(
                    onPressed: open,
                    child: const Icon(Icons.add),
                  ),
              openBuilder: (BuildContext context, VoidCallback close) =>
                  WorldEditorPage(controller: controller),
            )
          : const SizedBox.shrink(),
    ),
  );
}

class WorldListBody extends StatelessWidget {
  const WorldListBody({
    super.key,
    required this.controller,
    required this.showArchived,
    required this.onCreateWorld,
  });

  final AppController controller;
  final bool showArchived;
  final VoidCallback onCreateWorld;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final List<World> worlds = controller.worlds
            .where((World w) => w.archived == showArchived)
            .toList();

        if (worlds.isEmpty) {
          return AppEmptyState(
            icon: showArchived ? Icons.archive_outlined : Icons.public_outlined,
            title: showArchived ? '还没有归档世界。' : '暂无世界背景，先创建一个吧。',
            actionLabel: showArchived ? null : '创建世界',
            actionIcon: showArchived ? null : Icons.add,
            onAction: showArchived ? null : onCreateWorld,
          );
        }

        return ReorderableListView.builder(
          padding: AppInsets.card,
          buildDefaultDragHandles: false,
          itemCount: worlds.length,
          onReorder: (int oldIndex, int newIndex) async {
            // ignore: deprecated_member_use
            await controller.reorderWorlds(oldIndex, newIndex);
          },
          itemBuilder: (BuildContext context, int index) {
            final World world = worlds[index];
            return _WorldItem(
              key: ValueKey<String>(world.id),
              controller: controller,
              world: world,
            );
          },
        );
      },
    );
  }
}

class _WorldItem extends StatelessWidget {
  const _WorldItem({super.key, required this.controller, required this.world});

  final AppController controller;
  final World world;

  @override
  Widget build(BuildContext context) {
    // OpenContainer 不吃 cardTheme 外边距:手动补偿原 Card 底边距。
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppContainer<bool>(
        closedBuilder: (BuildContext context, VoidCallback open) => InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const CircleAvatar(child: Icon(Icons.public_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      FitText(world.name.isEmpty ? '未命名世界' : world.name),
                      const SizedBox(height: 4),
                      FitText(
                        world.summary.isEmpty ? '暂无简介' : world.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (world.tags.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: world.tags
                              .map((String tag) => Chip(label: FitText(tag)))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                ReorderableDragStartListener(
                  index: world.archived ? -1 : 0,
                  child: const Icon(Icons.drag_handle),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  onSelected: (String value) async {
                    if (value == 'archive') {
                      await controller.setWorldArchived(
                        id: world.id,
                        archived: true,
                      );
                    } else if (value == 'unarchive') {
                      await controller.setWorldArchived(
                        id: world.id,
                        archived: false,
                      );
                    } else if (value == 'delete') {
                      if (!context.mounted) return;
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute<bool>(
                          builder: (BuildContext context) => DeleteConfirmPage(
                            controller: controller,
                            title: '删除世界',
                            entityName: world.name,
                            validNames: <String>[world.name],
                            promptHint: '请完整输入世界名「${world.name}」以确认删除',
                            contentBuilder: (BuildContext ctx) =>
                                buildWorldPreviewSections(ctx, world),
                            onDelete: () =>
                                controller.deleteWorldWithBackup(world.id),
                            requireName:
                                controller.settings.requireNameToDelete,
                          ),
                        ),
                      );
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    if (world.archived) {
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
        openBuilder: (BuildContext context, VoidCallback close) =>
            WorldEditorPage(controller: controller, world: world),
      ),
    );
  }
}
