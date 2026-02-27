import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/id_utils.dart';
import '../models/conversation.dart';
import '../models/role.dart';
import '../models/service_results.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import 'chat/chat_models.dart';
import 'chat/chat_snapshot_store.dart';
import 'chat/chat_stream_parser.dart';
import 'chat/chat_token_counter.dart';
import 'chat/chat_message_slice.dart';
import 'chat/chat_message_builder.dart';
import 'chat/chat_system_prompt.dart';
import 'chat/chat_state.dart';
import 'chat/chat_controller.dart';
import 'chat/widgets/chat_app_bar.dart';
import 'chat/widgets/chat_input_bar.dart';
import 'chat/widgets/chat_message_list.dart';

part 'chat/chat_state_mixin.dart';
part 'chat/chat_ui_helpers.dart';
part 'chat/chat_search.dart';
part 'chat/chat_payload_builders.dart';
part 'chat/chat_summary.dart';
part 'chat/chat_stream_handlers.dart';
part 'chat/chat_actions.dart';
part 'chat/chat_actions_send.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.controller, required this.conversationId});
  final AppController controller;
  final String conversationId;
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
        ChatActions {
  Future<void> _ensureOpeningMessage() async {
    if (_conversation.messages.isNotEmpty) {
      return;
    }
    final Role? role = _role;
    if (role == null || role.opening.trim().isEmpty) {
      return;
    }
    final ConversationMessage opening = ConversationMessage(
      id: newId(),
      role: 'assistant',
      text: role.opening.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _conversation = _conversation.copyWith(messages: <ConversationMessage>[opening]);
    await widget.controller.upsertConversation(_conversation);
    if (!mounted) {
      return;
    }
    setState(() {});
  }
  Future<void> _loadAccent() async {
    final Role? role = _role;
    final String? path = role?.images['square'];
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return;
    }
    final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(
      FileImage(File(path)),
      size: const Size(128, 128),
      maximumColorCount: 8,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _accent = palette.dominantColor?.color;
    });
  }
  void _scrollToBottom() {
    _chatController.scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final Role? role = _role;
    final Color schemeColor = _accent ?? Theme.of(context).colorScheme.primary;
    final Color userBubble = schemeColor.withValues(alpha: 0.18);
    final Color assistantBubble = Theme.of(context).colorScheme.surfaceContainerHighest;
    final Size size = MediaQuery.of(context).size;
    final bool useLandscape = size.width >= size.height;
    final String? bgPath = useLandscape ? role?.images['landscape'] : role?.images['portrait'];
    final bool useImageBg = _conversation.backgroundMode == 'image' && bgPath != null && bgPath.isNotEmpty;
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
        role: role,
      ),
      body: Stack(
        children: <Widget>[
          if (useImageBg)
            Positioned.fill(
              child: Image.file(
                File(bgPath),
                fit: BoxFit.cover,
              ),
            ),
          if (useImageBg)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
              ),
            ),
          Column(
            children: <Widget>[
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
                  tokenCountForMessage: (String messageId, String text) {
                    return _tokenCounter.countTokens(
                      model: widget.controller.settings.selectedModel,
                      messageId: messageId,
                      text: text,
                    );
                  },
                  summaryById: _summaryById,
                  onStartSummary: _startSummaryFromPrompt,
                  onDismissSummary: _dismissSummaryPrompt,
                  onShowMessageMenu: _showMessageMenu,
                  summaryInProgress: _summaryInProgress,
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.auto_awesome, size: 16),
                          const SizedBox(width: 6),
                          const Text('正在生成摘要...'),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _cancelSummary,
                            child: const Text('停止'),
                          ),
                        ],
                      ),
                    ),
                  ),
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
              ),
            ],
          ),
        ],
      ),
    );
  }
}

