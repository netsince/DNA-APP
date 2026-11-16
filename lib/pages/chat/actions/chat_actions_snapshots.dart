part of '../../chat_page.dart';

mixin ChatActionsSnapshots on ChatStateMixin {
  Future<List<ChatSnapshot>> _loadSnapshots() async {
    return _snapshotStore.loadSnapshots(_conversation.id);
  }

  Future<void> _saveSnapshots(List<ChatSnapshot> snapshots) async {
    await _snapshotStore.saveSnapshots(_conversation.id, snapshots);
  }

  Future<void> _manageSnapshots() async {
    final List<ChatSnapshot> snapshots = await _loadSnapshots();
    if (!mounted) {
      return;
    }
    // 存档管理是一个**管理列表**（浏览 + 选择 + 新建），不是需要立刻拍板的
    // 决定：按审计 3.2 从 dialog 挪到可滚动的大号 bottom sheet。
    // 真正该用 dialog 的是下面「确认加载存档」那一步 —— 它会覆盖当前对话。
    final String? action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return Theme(
          data: _accentTheme,
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              // 上限 70% 屏高：存档多时 sheet 内部滚动，不铺满整屏。
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      0,
                      AppSpacing.xl,
                      AppSpacing.md,
                    ),
                    child: FitText(
                      '存档管理',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  Flexible(
                    child: snapshots.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl,
                              vertical: AppSpacing.lg,
                            ),
                            child: FitText('暂无存档'),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: snapshots.length,
                            itemBuilder: (BuildContext context, int index) {
                              final ChatSnapshot snapshot = snapshots[index];
                              final DateTime time =
                                  DateTime.fromMillisecondsSinceEpoch(
                                snapshot.timestamp,
                              );
                              return ListTile(
                                title: FitText(snapshot.name),
                                subtitle: FitText(time.toString().substring(0, 19)),
                                onTap: () =>
                                    Navigator.of(sheetContext).pop('load:$index'),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.md,
                      AppSpacing.xl,
                      AppSpacing.xl,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: const FitText('取消'),
                          ),
                        ),
                        AppSpacing.wMd,
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop('create'),
                            child: const FitText('新建存档'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (action == null) {
      return;
    }
    if (action == 'create') {
      if (!mounted) return;
      final String defaultName = '存档 ${DateTime.now().toString().substring(0, 19)}';
      final String? name = await showTextInputDialog(
        context: context,
        title: '创建存档',
        hintText: '输入存档名称',
        initialValue: defaultName,
        accentColor: _accent,
      );
      if (name == null || name.trim().isEmpty) {
        return;
      }
      snapshots.insert(
        0,
        ChatSnapshot(
          id: newId(),
          name: name.trim(),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          data: _conversation.toJson(),
        ),
      );
      await _saveSnapshots(snapshots);
      if (!mounted) {
        return;
      }
      showSnack(context, '存档已保存。');
      return;
    }
    if (action.startsWith('load:')) {
      if (!mounted) return;
      final int index = int.tryParse(action.split(':').last) ?? -1;
      if (index < 0 || index >= snapshots.length) {
        return;
      }
      final bool confirmed = await showConfirmDialog(
        context: context,
        title: '确认加载存档',
        content: '将覆盖当前对话并无法撤销，确定要继续吗？',
        accentColor: _accent,
      );
      if (!confirmed) {
        return;
      }
      final Map<String, dynamic> data = Map<String, dynamic>.from(snapshots[index].data);
      data['id'] = _conversation.id;
      _conversation = Conversation.fromJson(data);
      await widget.controller.upsertConversation(_conversation);
      if (!mounted) {
        return;
      }
      setState(() {});
      _scrollToBottom();
    }
  }
}
