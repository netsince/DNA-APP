import 'package:flutter/material.dart';

import '../models/world.dart';
import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';
import 'world_editor_page.dart';

class WorldPage extends StatefulWidget {
  const WorldPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> {
  bool _showArchived = false;

  void _toggleArchived() {
    setState(() => _showArchived = !_showArchived);
  }

  void _createWorld() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => WorldEditorPage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? '世界归档' : '世界'),
        actions: <Widget>[
          IconButton(
            tooltip: _showArchived ? '查看世界' : '查看归档',
            onPressed: _toggleArchived,
            icon: Icon(_showArchived ? Icons.public_outlined : Icons.archive_outlined),
          ),
          if (!_showArchived)
            IconButton(
              tooltip: '创建世界',
              onPressed: _createWorld,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      drawer: AppDrawer(controller: widget.controller, current: AppSection.world),
      body: _WorldListBody(
        controller: widget.controller,
        showArchived: _showArchived,
        onCreateWorld: _createWorld,
      ),
      floatingActionButton: !_showArchived
          ? FloatingActionButton(
              onPressed: _createWorld,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _WorldListBody extends StatelessWidget {
  const _WorldListBody({
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
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(showArchived ? '还没有归档世界。' : '暂无世界背景，先创建一个吧。'),
                const SizedBox(height: 12),
                if (!showArchived)
                  FilledButton.icon(
                    onPressed: onCreateWorld,
                    icon: const Icon(Icons.add),
                    label: const Text('创建世界'),
                  ),
              ],
            ),
          );
        }

        return ReorderableListView.builder(
          padding: const EdgeInsets.all(16),
          buildDefaultDragHandles: false,
          itemCount: worlds.length,
          onReorder: (int oldIndex, int newIndex) async {
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
  const _WorldItem({
    super.key,
    required this.controller,
    required this.world,
  });

  final AppController controller;
  final World world;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => WorldEditorPage(
                controller: controller,
                world: world,
              ),
            ),
          );
        },
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
                    Text(world.name.isEmpty ? '未命名世界' : world.name),
                    const SizedBox(height: 6),
                    Text(
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
                            .map((String tag) => Chip(label: Text(tag)))
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
                  }
                },
                itemBuilder: (BuildContext context) {
                  if (world.archived) {
                    return <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'unarchive',
                        child: ListTile(
                          leading: Icon(Icons.unarchive_outlined),
                          title: Text('恢复'),
                        ),
                      ),
                    ];
                  }
                  return <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'archive',
                      child: ListTile(
                        leading: Icon(Icons.archive_outlined),
                        title: Text('归档'),
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
