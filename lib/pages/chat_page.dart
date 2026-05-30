import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/id_utils.dart';
import '../utils/api_guard.dart';
import '../utils/dialogs.dart';
import '../utils/ui_feedback.dart';
import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/service_results.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../widgets/group_avatar.dart';
import 'chat/chat_models.dart';
import 'chat/chat_snapshot_store.dart';
import 'chat/chat_stream_parser.dart';
import 'chat/chat_token_counter.dart';
import 'chat/chat_message_slice.dart';
import 'chat/chat_message_builder.dart';
import 'chat/chat_system_prompt.dart';
import 'chat/state/chat_state.dart';
import 'chat/state/chat_controller.dart';
import 'chat/ui/widgets/chat_app_bar.dart';
import 'chat/ui/widgets/chat_input_bar.dart';
import 'chat/ui/widgets/chat_message_list.dart';

part 'chat/state/chat_state_mixin.dart';
part 'chat/ui/chat_ui_helpers.dart';
part 'chat/ui/chat_search.dart';
part 'chat/builders/chat_payload_builders.dart';
part 'chat/chat_summary.dart';
part 'chat/builders/chat_stream_handlers.dart';
part 'chat/actions/chat_actions.dart';
part 'chat/actions/chat_actions_send.dart';
part 'chat/actions/chat_actions_inspiration.dart';
part 'chat/actions/chat_actions_snapshots.dart';
part 'chat/actions/chat_actions_summary_ui.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.controller,
    required this.conversationId,
    this.isGroup = false,
  });

  final AppController controller;
  final String conversationId;
  final bool isGroup;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with
        ChatStateMixin,
        ChatUiHelpers,
        ChatSearchHelpers,
        ChatPayloadBuilders,
        ChatSummaryHelpers,
        ChatStreamHandlers,
        ChatActions,
        ChatActionsSend,
        ChatActionsInspiration,
        ChatActionsSnapshots,
        ChatActionsSummaryUi {
  // 缓存回调函数避免重建
  late final _TokenCountCallback _tokenCountCallback = _TokenCountCallback(
    counter: _tokenCounter,
    getModel: () => widget.controller.settings.selectedModel,
  );

  @override
  Future<void> _ensureOpeningMessage() async {
    if (_isGroup) {
      return;
    }
    if (_conversation.messages.isNotEmpty) {
      return;
    }
    final TA? ta = _ta;
    if (ta == null || ta.opening.trim().isEmpty) {
      return;
    }
    final ConversationMessage opening = ConversationMessage(
      id: newId(),
      role: 'assistant',
      text: ta.opening.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      speakerTaId: ta.id,
    );
    _conversation = _conversation.copyWith(messages: <ConversationMessage>[opening]);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Future<void> _loadAccent() async {
    final TA? ta = _ta;
    final String? path = ta?.images['square'];
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return;
    }

    try {
      // 使用 compute 在后台线程处理图片颜色提取
      final Color? dominantColor = await compute<_ExtractColorParams, Color?>(
        _extractDominantColor,
        _ExtractColorParams(path: path),
      );

      if (!mounted || dominantColor == null) {
        return;
      }
      setState(() {
        _accent = dominantColor;
      });
    } catch (e) {
      debugPrint('Failed to load accent color: $e');
    }
  }

  @override
  void _scrollToBottom() {
    _chatController.scrollToBottom();
  }

  void _onInputTap() {
    // 点击输入框时，延迟滚动以确保键盘弹出后底部消息可见
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _scrollToBottom();
      }
    });
  }

  TA? _lastAssistantSpeaker() {
    for (int i = _conversation.messages.length - 1; i >= 0; i--) {
      final ConversationMessage message = _conversation.messages[i];
      if (message.kind != 'message' || message.role != 'assistant') {
        continue;
      }
      final String? taId = message.speakerTaId;
      if (taId != null && taId.isNotEmpty) {
        return widget.controller.getTaById(taId);
      }
      return _activeTa;
    }
    return null;
  }

  Widget _buildGroupBackground(bool useLandscape) {
    final TA? speaker = _lastAssistantSpeaker();
    final String? path = useLandscape ? speaker?.images['landscape'] : speaker?.images['portrait'];
    final ImageProvider? image = path != null ? _getCachedImage(path) : null;
    final bool hasImage = image != null;

    final Widget child = hasImage
        ? Image(
            image: image,
            key: ValueKey<String>('ta:$path'),
            fit: BoxFit.cover,
          )
        : LayoutBuilder(
            key: const ValueKey<String>('group-avatar'),
            builder: (BuildContext context, BoxConstraints constraints) {
              final double size = constraints.maxWidth < constraints.maxHeight
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              return Center(
                child: GroupAvatar(
                  tas: _memberTas,
                  size: size * 0.72,
                  radius: 18,
                ),
              );
            },
          );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: child,
    );
  }

  Future<void> _showMemberPicker() async {
    if (!_isGroup) {
      return;
    }
    final List<TA> allTas = widget.controller.activeTas;
    final List<TA> candidates = allTas.where((TA t) => !_memberTaIds.contains(t.id)).toList();
    if (candidates.isEmpty) {
      if (!mounted) {
        return;
      }
      showSnack(context, '没有可添加的TA了。');
      return;
    }
    final Set<String> selected = <String>{};
    final List<String>? updated = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setDialogState) {
            return AlertDialog(
              title: const Text('添加群成员'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (BuildContext context, int index) {
                    final TA ta = candidates[index];
                    final bool checked = selected.contains(ta.id);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (bool? value) {
                        setDialogState(() {
                          if (value == true) {
                            selected.add(ta.id);
                          } else {
                            selected.remove(ta.id);
                          }
                        });
                      },
                      title: Text(ta.name.isEmpty ? '未命名TA' : ta.name),
                    );
                  },
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty ? null : () => Navigator.of(context).pop(selected.toList()),
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );
    if (updated == null || updated.isEmpty) {
      return;
    }
    final List<String> merged = <String>[
      ..._memberTaIds,
      ...updated.where((String id) => !_memberTaIds.contains(id)),
    ];
    _conversation = _conversation.copyWith(memberTaIds: merged);
    await widget.controller.upsertGroupConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  ImageProvider? _avatarForTa(TA ta) {
    final String? path = ta.images['square'];
    if (path == null || path.isEmpty) {
      return null;
    }
    return _getCachedImage(path);
  }

  Widget _buildSpeakerBar(Color primaryContainer, Color surfaceContainerHighest, TextTheme textTheme) {
    if (!_isGroup) {
      return const SizedBox.shrink();
    }
    final List<TA> tas = _memberTas;
    if (tas.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Text('发言控制'),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tas.length,
                separatorBuilder: (_, int index) => const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  final TA ta = tas[index];
                  final bool active = ta.id == _activeTaId;
                  final ImageProvider? avatar = _avatarForTa(ta);
                  return GestureDetector(
                    onTap: () => _triggerTaReply(ta),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: active
                              ? primaryContainer
                              : surfaceContainerHighest,
                          foregroundImage: avatar,
                          child: avatar == null
                              ? Text(
                                  ta.name.isNotEmpty ? ta.name[0] : '?',
                                  style: textTheme.labelMedium,
                                )
                              : null,
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          width: 56,
                          child: Text(
                            ta.name.isEmpty ? '未命名' : ta.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          IconButton(
            onPressed: _showMemberPicker,
            tooltip: '添加成员',
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 缓存 Theme 数据避免重复查找
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextTheme textTheme = theme.textTheme;
    final Size screenSize = MediaQuery.sizeOf(context);

    final TA? ta = _ta;
    final Color schemeColor = _accent ?? colorScheme.primary;
    final Color userBubble = schemeColor.withValues(alpha: 0.18);
    final Color assistantBubble = colorScheme.surfaceContainerHighest;
    final bool useLandscape = screenSize.width >= screenSize.height;
    final String? bgPath = useLandscape ? ta?.images['landscape'] : ta?.images['portrait'];
    final bool useImageBg = _conversation.backgroundMode == 'image' &&
        ((_isGroup) || (bgPath != null && bgPath.isNotEmpty));
    final String searchQuery = _searchController.text.trim();
    final List<int> searchMatches =
        _searching && searchQuery.isNotEmpty ? _computeSearchMatches(searchQuery) : <int>[];

    return Scaffold(
      appBar: ChatAppBar(
        searching: _searching,
        searchController: _searchController,
        searchMatchIndex: _searchMatchIndex,
        searchMatchesCount: searchMatches.length,
        onSearchChanged: _updateSearch,
        onNavigateMatch: _navigateMatch,
        onToggleSearch: _toggleSearch,
        onScrollToBottom: _scrollToBottom,
        onToggleBackground: _toggleBackground,
        backgroundMode: _conversation.backgroundMode,
        ta: ta,
        titleOverride: _isGroup
            ? (_conversation.groupName.trim().isNotEmpty ? _conversation.groupName.trim() : '群聊')
            : null,
      ),
      body: Stack(
        children: <Widget>[
          if (useImageBg)
            Positioned.fill(
              child: _isGroup
                  ? _buildGroupBackground(useLandscape)
                  : (() {
                      final ImageProvider? image = _getCachedImage(bgPath!);
                      if (image == null) return const SizedBox.shrink();
                      return Image(
                        image: image,
                        fit: BoxFit.cover,
                      );
                    })(),
            ),
          if (useImageBg)
            Positioned.fill(
              child: Container(
                color: colorScheme.surface.withValues(alpha: 0.75),
              ),
            ),
          Column(
            children: <Widget>[
              _buildSpeakerBar(colorScheme.primaryContainer, colorScheme.surfaceContainerHighest, textTheme),
              Expanded(
                child: ChatMessageList(
                  conversation: _conversation,
                  scrollController: _scrollController,
                  messageKeys: _messageKeys,
                  userBubble: userBubble,
                  assistantBubble: assistantBubble,
                  showTokenCounts: _showTokenCounts,
                  searchQuery: searchQuery,
                  thoughtsByMessageId: _thoughtsByMessageId,
                  tokenCountForMessage: _tokenCountCallback.call,
                  summaryById: _summaryById,
                  onStartSummary: _startSummaryFromPrompt,
                  onDismissSummary: _dismissSummaryPrompt,
                  onShowMessageMenu: _showMessageMenu,
                  summaryInProgress: _summaryInProgress,
                  showSpeakerLabels: _isGroup,
                  taNameForId: (String? id) => widget.controller.getTaById(id ?? '')?.name,
                  visibleThoughtMessageIds: _visibleThoughtMessageIds,
                ),
              ),
              if (_sending)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: assistantBubble,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text('对方正在输入...'),
                    ),
                  ),
                ),
              if (_summaryInProgress)
                _SummaryProgressBar(
                  onCancel: _cancelSummary,
                  color: colorScheme.surfaceContainerHigh,
                  borderColor: colorScheme.outlineVariant,
                ),
              ChatInputBar(
                inputController: _inputController,
                sending: _sending,
                inspirationInProgress: _inspirationInProgress,
                rangeSummaryInProgress: _rangeSummaryInProgress,
                summaryInProgress: _summaryInProgress,
                searching: _searching,
                showTokenCounts: _showTokenCounts,
                onSend: _send,
                onStartInspiration: _startInspiration,
                onManageSnapshots: _manageSnapshots,
                onToggleSearch: _toggleSearch,
                onToggleTokens: () => setState(() => _showTokenCounts = !_showTokenCounts),
                onForceSummary: _forceSummaryPrompt,
                onRangeSummary: _summarizeRecentRange,
                onTap: _onInputTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// 用于 compute 的参数类
class _ExtractColorParams {
  _ExtractColorParams({required this.path});
  final String path;
}

// 在后台线程提取主色调
Future<Color?> _extractDominantColor(_ExtractColorParams params) async {
  try {
    final File file = File(params.path);
    if (!file.existsSync()) {
      return null;
    }
    final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(
      FileImage(file),
      size: const Size(64, 64), // 减小尺寸以加快处理
      maximumColorCount: 4, // 减少颜色数量
    );
    return palette.dominantColor?.color;
  } catch (e) {
    return null;
  }
}

// 缓存 token 计数回调
class _TokenCountCallback {
  _TokenCountCallback({
    required this.counter,
    required this.getModel,
  });

  final ChatTokenCounter counter;
  final String Function() getModel;

  int call(String messageId, String text) {
    return counter.countTokens(
      model: getModel(),
      messageId: messageId,
      text: text,
    );
  }
}

// 独立的摘要进度条组件
class _SummaryProgressBar extends StatelessWidget {
  const _SummaryProgressBar({
    required this.onCancel,
    required this.color,
    required this.borderColor,
  });

  final VoidCallback onCancel;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.auto_awesome, size: 16),
              const SizedBox(width: 6),
              const Text('正在生成摘要...'),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onCancel,
                child: const Text('停止'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
