import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import 'chat_models.dart';

class ChatState {
  ChatState();

  Conversation? conversation;
  Color? accent;

  bool sending = false;
  bool searching = false;
  bool showTokenCounts = false;
  int searchMatchIndex = -1;

  final Map<String, GlobalKey> messageKeys = <String, GlobalKey>{};
  final Map<String, ThoughtEntry> thoughtsByMessageId = <String, ThoughtEntry>{};
  final Map<String, StreamParseState> streamParseStates = <String, StreamParseState>{};

  bool summaryInProgress = false;
  int summaryTaskId = 0;
  int? cancelledSummaryTaskId;
  PendingSummary? pendingSummary;

  bool rangeSummaryInProgress = false;
  bool inspirationInProgress = false;
  String inspirationPrompt = '';
  final List<String> inspirationOptions = <String>[];

  final Map<String, List<String>> retryAlternatives = <String, List<String>>{};
  final Set<String> retryDisabled = <String>{};
}
