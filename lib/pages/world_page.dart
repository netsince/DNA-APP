import 'package:flutter/material.dart';

import '../models/world.dart';
import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';
import 'world_editor_page.dart';

class WorldPage extends StatelessWidget {
  const WorldPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final List<World> worlds = controller.worlds;
        return Scaffold(
          appBar: AppBar(title: const Text('世界')),
          drawer: AppDrawer(controller: controller, current: AppSection.world),
          body: worlds.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('暂无世界观，先创建一个吧。'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (BuildContext context) => WorldEditorPage(controller: controller),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('创建世界'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: worlds.length,
                  itemBuilder: (BuildContext context, int index) {
                    final World world = worlds[index];
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
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => WorldEditorPage(controller: controller),
                ),
              );
            },
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}
