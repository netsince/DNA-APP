import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../widgets/group_avatar.dart';
import 'package:dna/widgets/fit_text.dart';
import '../widgets/app_editor_frame.dart';

class GroupEditPage extends StatefulWidget {
  const GroupEditPage({
    super.key,
    required this.controller,
    required this.group,
  });

  final AppController controller;
  final Conversation group;

  @override
  State<GroupEditPage> createState() => _GroupEditPageState();
}

class _GroupEditPageState extends State<GroupEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _promptController;
  late String? _selectedWorldId;
  late String? _selectedIdentityId;
  late final Set<String> _selectedTaIds;

  /// 群成员卡的 key：成员必填，出错时把视口滚到这张卡片
  /// （审计 3.5：校验结果要落在字段上，不能只弹一条 snackbar）。
  final GlobalKey _membersKey = GlobalKey();

  /// 群成员未选时的错误文案（null = 无错误）。
  String? _membersError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.groupName);
    _promptController = TextEditingController(text: widget.group.groupPrompt);
    _selectedWorldId = widget.group.worldId;
    _selectedIdentityId = widget.group.identityId;
    _selectedTaIds = Set<String>.from(widget.group.memberTaIds);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  /// 把「群成员」这张卡片滚进视口。
  void _revealMembersError() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final BuildContext? membersContext = _membersKey.currentContext;
      if (!mounted || membersContext == null) {
        return;
      }
      await Scrollable.ensureVisible(
        membersContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
    });
  }

  Future<void> _save() async {
    if (_selectedTaIds.isEmpty) {
      setState(() => _membersError = '请至少选择一位群成员。');
      _revealMembersError();
      return;
    }
    final List<String> memberIds = _selectedTaIds.toList();
    final Conversation updated = widget.group.copyWith(
      taId: memberIds.first,
      groupName: _nameController.text.trim(),
      groupPrompt: _promptController.text.trim(),
      worldId: (_selectedWorldId == null || _selectedWorldId!.isEmpty)
          ? null
          : _selectedWorldId,
      // 身份用空串表示「不选择」：copyWith 的 null 会被当成「不修改」，
      // 传 null 等于永远清不掉已选身份（getIdentityById 对空串同样返回 null）。
      identityId: _selectedIdentityId ?? '',
      memberTaIds: memberIds,
      activeTaId: _selectedTaIds.contains(widget.group.activeTaId)
          ? widget.group.activeTaId
          : memberIds.first,
    );
    await widget.controller.upsertGroupConversation(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List<TA> tas = widget.controller.activeTas;
    final List<World> worlds = widget.controller.activeWorlds;
    final List<UserIdentity> identities = widget.controller.identities;
    final List<TA> selectedTas =
        tas.where((TA t) => _selectedTaIds.contains(t.id)).toList();

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
        padding: AppEditorLayout.bodyPadding(context),
        children: <Widget>[
          _section(
            title: '群名称',
            children: <Widget>[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '群名称（可选）'),
              ),
            ],
          ),
          _section(
            title: '群设定',
            children: <Widget>[
              TextField(
                controller: _promptController,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '群设定文本',
                  hintText: '用于群聊的系统设定，和世界背景并存。',
                ),
              ),
            ],
          ),
          _section(
            title: '世界背景（可选）',
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
            key: _membersKey,
            title: '群成员（至少选一位）',
            children: <Widget>[
              if (_membersError != null) ...<Widget>[
                FitText(
                  _membersError!,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                AppSpacing.hSm,
              ],
              if (tas.isEmpty)
                const FitText('暂无TA，请先在"我家"创建TA。')
              else
                Column(
                  children: tas.map((TA ta) {
                    final bool checked = _selectedTaIds.contains(ta.id);
                    return CheckboxListTile(
                      value: checked,
                      title: FitText(
                        ta.name.isEmpty ? '未命名TA' : ta.name,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            _selectedTaIds.add(ta.id);
                            _membersError = null;
                          } else {
                            _selectedTaIds.remove(ta.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              if (selectedTas.isNotEmpty) ...<Widget>[
                AppSpacing.hSm,
                Row(
                  children: <Widget>[
                    const FitText('群头像预览：'),
                    AppSpacing.wSm,
                    GroupAvatar(tas: selectedTas, size: 56),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 一个无容器的字段分组（审计 3.3 / 4.2）：照 lib/widgets/setting_section.dart
  /// 的写法，标题用 titleSmall + onSurfaceVariant，组间只靠 AppSpacing.xl 分节。
  Widget _section({
    Key? key,
    required String title,
    required List<Widget> children,
  }) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      key: key,
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
