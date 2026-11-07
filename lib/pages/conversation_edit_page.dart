import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../utils/ui_feedback.dart';
import 'package:dna/widgets/fit_text.dart';
import '../widgets/app_editor_frame.dart';

class ConversationEditPage extends StatefulWidget {
  const ConversationEditPage({
    super.key,
    required this.controller,
    required this.conversation,
  });

  final AppController controller;
  final Conversation conversation;

  @override
  State<ConversationEditPage> createState() => _ConversationEditPageState();
}

class _ConversationEditPageState extends State<ConversationEditPage> {
  late String? _selectedTaId;
  late String? _selectedWorldId;
  late String? _selectedIdentityId;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _selectedTaId = widget.conversation.taId;
    _selectedWorldId = widget.conversation.worldId;
    _selectedIdentityId = widget.conversation.identityId;
    _noteController = TextEditingController(text: widget.conversation.note);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedTaId == null || _selectedTaId!.isEmpty) {
      showSnack(context, '请选择TA。');
      return;
    }
    final Conversation updated = widget.conversation.copyWith(
      taId: _selectedTaId!,
      worldId: (_selectedWorldId == null || _selectedWorldId!.isEmpty)
          ? null
          : _selectedWorldId,
      // 身份用空串表示「不选择」：copyWith 的 null 会被当成「不修改」，
      // 传 null 等于永远清不掉已选身份（getIdentityById 对空串同样返回 null）。
      identityId: _selectedIdentityId ?? '',
      note: _noteController.text.trim(),
    );
    await widget.controller.upsertConversation(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List<TA> tas = widget.controller.activeTas;
    final List<World> worlds = widget.controller.activeWorlds;
    final List<UserIdentity> identities = widget.controller.identities;

    return Scaffold(
      appBar: AppBar(
        title: const FitText('更改信息'),
        actions: <Widget>[
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check),
            tooltip: '保存',
          ),
        ],
      ),
      body: ListView(
        padding: AppEditorLayout.bodyPadding(context),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FitText('选择TA（必选）', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (tas.isEmpty)
                    const FitText('暂无TA，请先在"我家"创建TA。')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTaId,
                      decoration: const InputDecoration(labelText: 'TA'),
                      items: tas
                          .map(
                            (TA ta) => DropdownMenuItem<String>(
                              value: ta.id,
                              child: FitText(ta.name.isEmpty ? '未命名TA' : ta.name),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) =>
                          setState(() => _selectedTaId = value),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FitText('选择世界背景（可选）', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (worlds.isEmpty)
                    const FitText('暂无世界背景，可在"世界"页面创建。')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedWorldId ?? '',
                      decoration: const InputDecoration(labelText: '世界背景'),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(
                          value: '',
                          child: FitText('不选择'),
                        ),
                        ...worlds.map(
                          (World world) => DropdownMenuItem<String>(
                            value: world.id,
                            child: FitText(
                              world.name.isEmpty ? '未命名世界' : world.name,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (String? value) {
                        setState(() {
                          _selectedWorldId =
                              (value == null || value.isEmpty) ? null : value;
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (identities.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FitText('我的身份（可选）', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedIdentityId ?? '',
                      decoration: const InputDecoration(labelText: '身份'),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(
                          value: '',
                          child: FitText('不选择'),
                        ),
                        ...identities.map(
                          (UserIdentity idt) => DropdownMenuItem<String>(
                            value: idt.id,
                            child: FitText(
                              idt.name.isEmpty ? '未命名身份' : idt.name,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (String? value) {
                        setState(() {
                          _selectedIdentityId =
                              (value == null || value.isEmpty) ? null : value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FitText('备注', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(labelText: '可选备注'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: AppEditorFab(
        onPressed: _save,
        icon: const Icon(Icons.check),
        label: const FitText('保存'),
      ),
    );
  }
}
