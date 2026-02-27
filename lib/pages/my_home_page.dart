import 'dart:io';

import 'package:flutter/material.dart';

import '../models/role.dart';
import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';
import 'role_editor_page.dart';

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final List<Role> roles = controller.roles;
        return Scaffold(
          appBar: AppBar(title: const Text('我家')),
          drawer: AppDrawer(controller: controller, current: AppSection.myHome),
          body: roles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('暂无角色，先创建一个吧。'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (BuildContext context) => RoleEditorPage(controller: controller),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('创建角色'),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(16),
                  buildDefaultDragHandles: false,
                  itemCount: roles.length,
                  onReorder: (int oldIndex, int newIndex) async {
                    await controller.reorderRoles(oldIndex, newIndex);
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final Role role = roles[index];
                    final String? square = role.images['square'];
                    return Card(
                      key: ValueKey<String>(role.id),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (BuildContext context) => RoleEditorPage(
                                controller: controller,
                                role: role,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              square != null && square.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        File(square),
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : const CircleAvatar(radius: 32, child: Icon(Icons.person_outline)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(role.name.isEmpty ? '未命名角色' : role.name),
                                    const SizedBox(height: 6),
                                    Text(
                                      role.intro.isEmpty ? '暂无介绍' : role.intro,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (role.tags.isNotEmpty) ...<Widget>[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: role.tags
                                            .map((String tag) => Chip(label: Text(tag)))
                                            .toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle),
                              ),
                              const SizedBox(width: 8),
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
                  builder: (BuildContext context) => RoleEditorPage(controller: controller),
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
