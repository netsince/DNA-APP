import 'dart:io';

import 'package:flutter/material.dart';

import '../models/ta.dart';
import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  List<TA> _displayTas = <TA>[];
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _refreshTas();
      _initialized = true;
    }
  }

  void _refreshTas() {
    final List<TA> all = widget.controller.activeTas;
    final List<TA> shuffled = List<TA>.of(all)..shuffle();
    setState(() => _displayTas = shuffled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('社区'),
        actions: <Widget>[
          IconButton(
            tooltip: '侧边栏',
            onPressed: () {},
            icon: const Icon(Icons.view_sidebar_outlined),
          ),
        ],
      ),
      drawer: AppDrawer(controller: widget.controller, current: AppSection.community),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (BuildContext context, Widget? _) {
          if (_displayTas.isEmpty) {
            return const Center(
              child: Text('暂无角色数据，请先在「我家」中创建角色。'),
            );
          }
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth;
              final int crossAxisCount = width >= 600 ? 3 : 2;
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemCount: _displayTas.length,
                itemBuilder: (BuildContext context, int index) {
                  return _TaCommunityCard(ta: _displayTas[index]);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _TaCommunityCard extends StatelessWidget {
  const _TaCommunityCard({required this.ta});

  final TA ta;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String? squarePath = ta.images['square'];
    final bool hasImage = squarePath != null && squarePath.isNotEmpty && File(squarePath).existsSync();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: hasImage
                  ? Image.file(
                      File(squarePath),
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person_outline,
                        size: 48,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      ta.name.isNotEmpty ? ta.name : '未命名',
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        ta.intro.isNotEmpty ? ta.intro : '暂无简介',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
