import 'package:material_ui/material_ui.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/id_utils.dart';
import '../widgets/app_editor_frame.dart';
import '../widgets/fit_text.dart';
import '../widgets/form_draft.dart';
import '../widgets/form_fields.dart';
import '../widgets/group_avatar.dart';

/// 新建群聊：群名称 / 群设定 / 世界背景 / 我的身份 / 群成员（必选）。
///
/// 字段由 [FormDraft] + [FormFields] 的构件渲染 —— 与「更改群聊信息」页
/// 共用同一套字段描述，两页不再各抄一遍下拉构造、错误落点与归一化。
class GroupCreatePage extends StatefulWidget {
  const GroupCreatePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends State<GroupCreatePage> {
  final FormDraft _draft = FormDraft(
    textFields: const <String>['groupName', 'prompt'],
    multiFields: const <String>['members'],
  );

  /// 群成员这一块的 key：成员是必填项，出错时把视口滚到这里
  /// （审计 3.5：校验结果要落在字段上，不能只弹一条 snackbar）。
  final GlobalKey _membersKey = GlobalKey();

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

  Future<void> _create() async {
    // 群成员必选：错误落在字段上（不是 snackbar），并把视口带回该字段。
    if (_draft.multiSelection('members').isEmpty) {
      setState(() => _draft.setError('members', '请至少选择一位群成员。'));
      _revealMembersError();
      return;
    }
    final List<String> memberIds = _draft.multiSelection('members').toList();
    String id = newId();
    final Set<String> existing = widget.controller.groupConversations
        .map((Conversation c) => c.id)
        .toSet();
    while (existing.contains(id)) {
      id = newId();
    }
    final Conversation conversation = Conversation(
      id: id,
      taId: memberIds.first,
      worldId: _draft.selection('world'),
      identityId: _draft.selection('identity'),
      note: '',
      messages: const <ConversationMessage>[],
      backgroundMode: 'none',
      summaries: const <ConversationSummary>[],
      archived: false,
      isGroup: true,
      groupName: _draft.text('groupName'),
      groupPrompt: _draft.text('prompt'),
      memberTaIds: memberIds,
      activeTaId: memberIds.first,
    );
    await widget.controller.upsertGroupConversation(conversation);
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
        title: const FitText('新建群聊'),
        actions: const <Widget>[],
      ),
      // 主操作放回右下 FAB（拇指可达）；顶栏不再放同一个动作（审计回归 R4）。
      floatingActionButton: AppEditorFab(
        onPressed: _create,
        icon: const Icon(Icons.check),
        label: const FitText('创建群聊'),
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
                emptyHint: '暂无世界背景，可在“世界”页面创建。',
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
                emptyHint: '暂无TA，请先在“我家”创建TA。',
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
