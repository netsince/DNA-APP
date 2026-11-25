import 'package:material_ui/material_ui.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../widgets/app_editor_frame.dart';
import '../widgets/fit_text.dart';
import '../widgets/form_draft.dart';
import '../widgets/form_fields.dart';

/// 更改会话信息：TA（必选）+ 世界背景 / 我的身份 / 备注（可选）。
///
/// 与「新建会话」共用同一套字段描述（[FormDraft] + [FormFields]），
/// 差别只有：进来先用现有会话回填、保存走 copyWith。
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
  final FormDraft _draft = FormDraft(textFields: const <String>['note']);
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _draft.select('ta', widget.conversation.taId);
    _draft.select('world', widget.conversation.worldId);
    _draft.select('identity', widget.conversation.identityId);
    _draft.controller('note').text = widget.conversation.note;
  }

  @override
  void dispose() {
    _draft.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 把视口带回第一个出错的字段（这一页唯一的必填项在最上面）。
  void _revealFirstError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _save() async {
    final bool ok = _draft.validateRequired(<(String, String)>[
      ('ta', '请先选择一个 TA。'),
    ]);
    if (!ok) {
      setState(() {});
      _revealFirstError();
      return;
    }

    final Conversation updated = widget.conversation.copyWith(
      taId: _draft.selection('ta')!,
      worldId: _draft.selection('world'),
      // 身份用空串表示「不选择」：copyWith 的 null 会被当成「不修改」，
      // 传 null 等于永远清不掉已选身份（getIdentityById 对空串同样返回 null）。
      identityId: _draft.selection('identity') ?? '',
      note: _draft.text('note'),
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
        actions: const <Widget>[],
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
          FormSection(
            title: '选择TA（必选）',
            children: <Widget>[
              FormEntitySelect(
                draft: _draft,
                id: 'ta',
                label: 'TA',
                emptyHint: '暂无TA，请先在“我家”创建TA。',
                options: <FormOption>[
                  for (final TA ta in tas)
                    (
                      value: ta.id,
                      label: ta.name.isEmpty ? '未命名TA' : ta.name,
                    ),
                ],
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          FormSection(
            title: '选择世界背景（可选）',
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
                        label: identity.name.isEmpty ? '未命名身份' : identity.name,
                      ),
                  ],
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          FormSection(
            title: '备注',
            children: <Widget>[
              FormTextField(draft: _draft, id: 'note', label: '可选备注'),
            ],
          ),
        ],
      ),
    );
  }
}
