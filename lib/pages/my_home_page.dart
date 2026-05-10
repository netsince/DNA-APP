import 'dart:io';

import 'package:flutter/material.dart';

import '../models/ta.dart';
import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';
import 'ta_editor_page.dart';

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key, required this.controller});

  final AppController controller;

  void _createTa(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => TaEditorPage(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我家')),
      drawer: AppDrawer(controller: controller, current: AppSection.myHome),
      body: _TaListBody(controller: controller),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createTa(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TaListBody extends StatelessWidget {
  const _TaListBody({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    // 缓存 theme 数据
    final TextTheme textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final List<TA> tas = controller.tas;

        if (tas.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('暂无TA，先创建一个吧。'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            TaEditorPage(controller: controller),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('创建TA'),
                ),
              ],
            ),
          );
        }

        return ReorderableListView.builder(
          padding: const EdgeInsets.all(16),
          buildDefaultDragHandles: false,
          itemCount: tas.length,
          onReorder: (int oldIndex, int newIndex) async {
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
                    Text(ta.name.isEmpty ? '未命名TA' : ta.name),
                    const SizedBox(height: 6),
                    Text(
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
                            .map((String tag) => Chip(label: Text(tag)))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              ReorderableDragStartListener(
                index: 0,
                child: const Icon(Icons.drag_handle),
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
