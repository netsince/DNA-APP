import 'package:material_ui/material_ui.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../utils/id_utils.dart';
import '../widgets/app_editor_frame.dart';
import '../widgets/fit_text.dart';
import '../widgets/form_draft.dart';
import '../widgets/form_fields.dart';

/// 新建会话：TA（必选）+ 世界背景 / 我的身份 / 备注（可选）。
///
/// 字段由 [FormDraft] + [FormFields] 的构件渲染 —— 与「更改信息」页共用
/// 同一套字段描述，两页不再各抄一遍下拉构造、错误落点与归一化。
class ConversationCreatePage extends StatefulWidget {
  const ConversationCreatePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ConversationCreatePage> createState() => _ConversationCreatePageState();
}

class _ConversationCreatePageState extends State<ConversationCreatePage> {
  final FormDraft _draft = FormDraft(textFields: const <String>['note']);
  final ScrollController _scrollController = ScrollController();

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

  Future<void> _create() async {
    // 必填校验落在字段上（不是 snackbar），并把视图带回该字段。
    final bool ok = _draft.validateRequired(<(String, String)>[
      ('ta', '请先选择一个 TA。'),
    ]);
    if (!ok) {
      setState(() {});
      _revealFirstError();
      return;
    }

    String id = newId();
    final Set<String> existing = widget.controller.conversations
        .map((Conversation c) => c.id)
        .toSet();
    while (existing.contains(id)) {
      id = newId();
    }

    final String taId = _draft.selection('ta')!;
    final Conversation conversation = Conversation(
      id: id,
      taId: taId,
      worldId: _draft.selection('world'),
      identityId: _draft.selection('identity'),
      note: _draft.text('note'),
      messages: const <ConversationMessage>[],
      backgroundMode: 'none',
      summaries: const <ConversationSummary>[],
      archived: false,
      isGroup: false,
      groupName: '',
      groupPrompt: '',
      memberTaIds: <String>[taId],
      activeTaId: taId,
    );

    await widget.controller.upsertConversation(conversation);
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
        title: const FitText('新建会话'),
        actions: const <Widget>[],
      ),
      // 主操作放回右下 FAB（拇指可达）；顶栏不再放同一个动作（审计回归 R4）。
      floatingActionButton: AppEditorFab(
        onPressed: _create,
        icon: const Icon(Icons.check),
        label: const FitText('创建会话'),
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
