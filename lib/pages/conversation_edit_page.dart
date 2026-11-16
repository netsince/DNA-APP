import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
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
  final ScrollController _scrollController = ScrollController();

  /// TA 必选：未选时就地报错（审计 3.5），并把视口带回该字段。
  String? _taError;

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
    _scrollController.dispose();
    super.dispose();
  }

  /// 把视口带回第一个出错的字段（这一页唯一的必填项在最上面）。
  void _revealFirstError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _save() async {
    if (_selectedTaId == null || _selectedTaId!.isEmpty) {
      setState(() => _taError = '请先选择一个 TA。');
      _revealFirstError();
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
        ],
      ),
      // 主操作放回右下 FAB（拇指可达）；顶栏不再放同一个动作（审计回归 R4）。
      floatingActionButton: AppEditorFab(
        onPressed: _save,
        icon: const Icon(Icons.check),
        label: const FitText('保存'),
      ),
      body: ListView(
        controller: _scrollController,
        padding: AppEditorLayout.bodyPadding(context),
        children: <Widget>[
          _section(
            title: '选择TA（必选）',
            children: <Widget>[
              if (tas.isEmpty)
                const FitText('暂无TA，请先在"我家"创建TA。')
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedTaId,
                  decoration: InputDecoration(
                    labelText: 'TA',
                    errorText: _taError,
                  ),
                  items: tas
                      .map(
                        (TA ta) => DropdownMenuItem<String>(
                          value: ta.id,
                          child: FitText(
                            ta.name.isEmpty ? '未命名TA' : ta.name,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) => setState(() {
                    _selectedTaId = value;
                    if (value != null && value.isNotEmpty) {
                      _taError = null;
                    }
                  }),
                ),
            ],
          ),
          _section(
            title: '选择世界背景（可选）',
            children: <Widget>[
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
                      _selectedWorldId = (value == null || value.isEmpty)
                          ? null
                          : value;
                    });
                  },
                ),
            ],
          ),
          if (identities.isNotEmpty)
            _section(
              title: '我的身份（可选）',
              children: <Widget>[
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
          _section(
            title: '备注',
            children: <Widget>[
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: '可选备注'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 一个无容器的字段分组（审计 3.3 / 4.2）：照 lib/widgets/setting_section.dart
  /// 的写法，用标题字号 + 间距分节，不再每组套一张 Card。
  Widget _section({
    required String title,
    required List<Widget> children,
  }) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FitText(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: AppWeight.medium,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          AppSpacing.hSm,
          ...children,
        ],
      ),
    );
  }
}
