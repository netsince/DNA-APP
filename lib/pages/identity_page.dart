import 'package:flutter/material.dart';

import '../models/user_identity.dart';
import '../state/app_controller.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_drawer.dart';
import 'identity_editor_page.dart';
import 'package:dna/widgets/fit_text.dart';

class IdentityPage extends StatefulWidget {
  const IdentityPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<IdentityPage> createState() => _IdentityPageState();
}

class _IdentityPageState extends State<IdentityPage> {
  void _createIdentity() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            IdentityEditorPage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      controller: widget.controller,
      current: AppSection.identity,
      appBar: AppBar(
        title: const FitText('身份'),
        actions: <Widget>[
          IconButton(
            tooltip: '创建身份',
            onPressed: _createIdentity,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _IdentityListBody(
        controller: widget.controller,
        onCreateIdentity: _createIdentity,
      ),
      bottomNavigationBar: widget.controller.settings.showBottomNav
          ? AppBottomNav(controller: widget.controller, current: AppSection.identity)
          : null,
      floatingActionButton: FloatingActionButton(
        onPressed: _createIdentity,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _IdentityListBody extends StatelessWidget {
  const _IdentityListBody({
    required this.controller,
    required this.onCreateIdentity,
  });

  final AppController controller;
  final VoidCallback onCreateIdentity;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final List<UserIdentity> identities = controller.identities;

        if (identities.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const FitText('暂无身份，先创建一个吧。'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onCreateIdentity,
                  icon: const Icon(Icons.add),
                  label: const FitText('创建身份'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: identities.length,
          itemBuilder: (BuildContext context, int index) {
            final UserIdentity identity = identities[index];
            return _IdentityItem(
              key: ValueKey<String>(identity.id),
              controller: controller,
              identity: identity,
            );
          },
        );
      },
    );
  }
}

class _IdentityItem extends StatelessWidget {
  const _IdentityItem({
    super.key,
    required this.controller,
    required this.identity,
  });

  final AppController controller;
  final UserIdentity identity;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => IdentityEditorPage(
                controller: controller,
                identity: identity,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const CircleAvatar(child: Icon(Icons.person_outline)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FitText(identity.name.isEmpty ? '未命名身份' : identity.name),
                    const SizedBox(height: 6),
                    FitText(
                      identity.persona.isEmpty ? '暂无设定' : identity.persona,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (identity.intro.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      FitText(
                        identity.intro,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
  }
}
