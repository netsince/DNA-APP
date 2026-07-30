import 'package:flutter/material.dart';

import '../models/user_identity.dart';
import '../state/app_controller.dart';
import '../utils/id_utils.dart';
import '../widgets/adaptive_text_field.dart';
import 'package:dna/widgets/fit_text.dart';

class IdentityEditorPage extends StatefulWidget {
  const IdentityEditorPage({super.key, required this.controller, this.identity});

  final AppController controller;
  final UserIdentity? identity;

  @override
  State<IdentityEditorPage> createState() => _IdentityEditorPageState();
}

class _IdentityEditorPageState extends State<IdentityEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _personaController;
  late final TextEditingController _introController;
  late String _identityId;

  @override
  void initState() {
    super.initState();
    final UserIdentity? identity = widget.identity;
    _identityId = identity?.id ?? newId();
    _nameController = TextEditingController(text: identity?.name ?? '');
    _personaController = TextEditingController(text: identity?.persona ?? '');
    _introController = TextEditingController(text: identity?.intro ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _personaController.dispose();
    _introController.dispose();
    super.dispose();
  }

  UserIdentity _buildCurrentIdentity() {
    return UserIdentity(
      id: _identityId,
      name: _nameController.text.trim(),
      persona: _personaController.text.trim(),
      intro: _introController.text.trim(),
    );
  }

  Future<void> _save() async {
    final UserIdentity identity = _buildCurrentIdentity();
    await widget.controller.upsertIdentity(identity);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FitText(widget.identity == null ? '创建身份' : '编辑身份'),
        actions: <Widget>[
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            tooltip: '保存',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('身份信息', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: '身份名称'),
                  ),
                  const SizedBox(height: 12),
                  AdaptiveTextField(
                    controller: _personaController,
                    decoration: const InputDecoration(
                      labelText: '人设',
                      hintText: '描述你的身份、性格、说话方式等',
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdaptiveTextField(
                    controller: _introController,
                    decoration: const InputDecoration(labelText: '介绍'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save_outlined),
        label: const FitText('保存身份'),
      ),
    );
  }
}
