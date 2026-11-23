import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../widgets/app_editor_frame.dart';
import '../widgets/fit_text.dart';
import '../widgets/form_draft.dart';
import '../widgets/form_fields.dart';
import '../widgets/group_avatar.dart';

/// 更改群聊信息：群名称 / 群设定 / 世界背景 / 我的身份 / 群成员（必选）。
///
/// 与「新建群聊」共用同一套字段描述（[FormDraft] + [FormFields]），
/// 差别只有：进来先用现有群聊回填、保存走 copyWith。
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
  final FormDraft _draft = FormDraft(
    textFields: const <String>['groupName', 'prompt'],
    multiFields: const <String>['members'],
  );

  /// 群成员这一块的 key：成员必填，出错时把视口滚到这里
  /// （审计 3.5：校验结果要落在字段上，不能只弹一条 snackbar）。
  final GlobalKey _membersKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _draft.controller('groupName').text = widget.group.groupName;
    _draft.controller('prompt').text = widget.group.groupPrompt;
    // 未选时下拉要显示「不选择」（原页面 initialValue 就是空串）：用 setSingleRaw
    // 播种，保住空串这个「未选」表示；用户一旦交互，FormEntitySelect 会把空串
    // 归一成 null，保存时再按原逻辑落 null。
    _draft.setSingleRaw('world', widget.group.worldId ?? '');
    _draft.setSingleRaw('identity', widget.group.identityId ?? '');
    _draft.setMulti('members', widget.group.memberTaIds);
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  /// 把「群成员」这一块滚进视口。
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
    // 群成员必选：错误落在字段上（不是 snackbar），并把视口带回该字段。
    if (_draft.multiSelection('members').isEmpty) {
      setState(() => _draft.setError('members', '请至少选择一位群成员。'));
      _revealMembersError();
      return;
    }
    final List<String> memberIds = _draft.multiSelection('members').toList();
    // 世界背景的「不选择」是空串，按原页面归一成 null 再交给 copyWith
    // （copyWith 的 null = 不修改，与旧实现同一行为）。
    final String? worldId = _draft.selection('world');
    final Conversation updated = widget.group.copyWith(
      taId: memberIds.first,
      groupName: _draft.text('groupName'),
      groupPrompt: _draft.text('prompt'),
      worldId: (worldId == null || worldId.isEmpty) ? null : worldId,
      // 身份用空串表示「不选择」：copyWith 的 null 会被当成「不修改」，
      // 传 null 等于永远清不掉已选身份（getIdentityById 对空串同样返回 null）。
      identityId: _draft.selection('identity') ?? '',
      memberTaIds: memberIds,
      activeTaId:
          _draft.multiSelection('members').contains(widget.group.activeTaId)
              ? widget.group.activeTaId
              : memberIds.first,
    );
    await widget.controller.upsertGroupConversation(updated);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List<TA> tas = widget.controller.activeTas;
    final List<World> worlds = widget.controller.activeWorlds;
    final List<UserIdentity> identities = widget.controller.identities;
    final Set<String> memberIds = _draft.multiSelection('members');
    final List<TA> selectedTas =
        tas.where((TA t) => memberIds.contains(t.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const FitText('更改信息'),
        actions: const <Widget>[],
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
          FormSection(
            title: '群名称',
            children: <Widget>[
              FormTextField(
                draft: _draft,
                id: 'groupName',
                label: '群名称（可选）',
              ),
            ],
          ),
          FormSection(
            title: '群设定',
            children: <Widget>[
              FormTextField(
                draft: _draft,
                id: 'prompt',
                label: '群设定文本',
                hint: '用于群聊的系统设定，和世界背景并存。',
                minLines: 3,
                maxLines: 8,
              ),
            ],
          ),
          FormSection(
            title: '世界背景（可选）',
            children: <Widget>[
              FormEntitySelect(
                draft: _draft,
                id: 'world',
                label: '世界背景',
                allowNone: true,
                emptyHint: '暂无世界背景，可在"世界"页面创建。',
                options: <FormOption>[
                  for (final World world in worlds)
                    (
                      value: world.id,
                      label: world.name.isEmpty ? '未命名世界' : world.name,
                    ),
                ],
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          if (identities.isNotEmpty)
            FormSection(
              title: '我的身份（可选）',
              children: <Widget>[
                FormEntitySelect(
                  draft: _draft,
                  id: 'identity',
                  label: '身份',
                  allowNone: true,
                  options: <FormOption>[
                    for (final UserIdentity identity in identities)
                      (
                        value: identity.id,
                        label:
                            identity.name.isEmpty ? '未命名身份' : identity.name,
                      ),
                  ],
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          FormSection(
            key: _membersKey,
            title: '群成员（至少选一位）',
            children: <Widget>[
              // 错误单独一行、落在成员块顶部（与原页面同一落点）。
              if (_draft.error('members') != null) ...<Widget>[
                FitText(
                  _draft.error('members')!,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                AppSpacing.hSm,
              ],
              FormEntityMulti(
                draft: _draft,
                id: 'members',
                emptyHint: '暂无TA，请先在"我家"创建TA。',
                options: <FormOption>[
                  for (final TA ta in tas)
                    (
                      value: ta.id,
                      label: ta.name.isEmpty ? '未命名TA' : ta.name,
                    ),
                ],
                onChanged: () => setState(() {
                  // 选中任何一位就清掉「至少选一位」的旧错误（与原页面一致）。
                  if (_draft.multiSelection('members').isNotEmpty) {
                    _draft.clearError('members');
                  }
                }),
              ),
              // 整组头像预览：FormEntityMulti.trailingOf 是「每个选项一格」的
              // slot，装不下「整组选中成员」的合成头像（依赖整个 selection），
              // 故保留原位置单独一行，视觉与原来完全一致。
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
}
