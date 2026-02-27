import 'chat_models.dart';

TagMatch? findTag(String buffer, List<String> tags) {
  final String lower = buffer.toLowerCase();
  int bestIndex = -1;
  String? bestTag;
  for (final String tag in tags) {
    final int idx = lower.indexOf(tag);
    if (idx == -1) {
      continue;
    }
    if (bestIndex == -1 || idx < bestIndex) {
      bestIndex = idx;
      bestTag = tag;
    }
  }
  if (bestIndex == -1 || bestTag == null) {
    return null;
  }
  return TagMatch(index: bestIndex, tag: bestTag);
}

StreamParseState consumeStreamChunk({
  required Map<String, StreamParseState> streamStates,
  required Map<String, ThoughtEntry> thoughtsByMessageId,
  required String messageId,
  required String chunk,
}) {
  final StreamParseState state =
      streamStates.putIfAbsent(messageId, () => StreamParseState());
  state.buffer += chunk;
  const List<String> openTags = <String>['<think>', '<analysis>', '<thought>'];
  const List<String> closeTags = <String>['</think>', '</analysis>', '</thought>'];
  while (state.buffer.isNotEmpty) {
    if (!state.inThought) {
      final TagMatch? open = findTag(state.buffer, openTags);
      if (open == null) {
        state.visible += state.buffer;
        state.buffer = '';
        break;
      }
      if (open.index > 0) {
        state.visible += state.buffer.substring(0, open.index);
      }
      state.buffer = state.buffer.substring(open.index + open.tag.length);
      state.inThought = true;
    } else {
      final TagMatch? close = findTag(state.buffer, closeTags);
      if (close == null) {
        state.thought += state.buffer;
        state.buffer = '';
        break;
      }
      if (close.index > 0) {
        state.thought += state.buffer.substring(0, close.index);
      }
      state.buffer = state.buffer.substring(close.index + close.tag.length);
      state.inThought = false;
    }
  }
  thoughtsByMessageId[messageId] = ThoughtEntry(text: state.thought.trim());
  return state;
}

String stripThoughtTags(String text) {
  if (text.isEmpty) {
    return text;
  }
  const List<String> openTags = <String>['<think>', '<analysis>', '<thought>'];
  const List<String> closeTags = <String>['</think>', '</analysis>', '</thought>'];
  String buffer = text;
  bool inThought = false;
  final StringBuffer out = StringBuffer();
  while (buffer.isNotEmpty) {
    if (!inThought) {
      final TagMatch? open = findTag(buffer, openTags);
      if (open == null) {
        out.write(buffer);
        break;
      }
      if (open.index > 0) {
        out.write(buffer.substring(0, open.index));
      }
      buffer = buffer.substring(open.index + open.tag.length);
      inThought = true;
    } else {
      final TagMatch? close = findTag(buffer, closeTags);
      if (close == null) {
        break;
      }
      buffer = buffer.substring(close.index + close.tag.length);
      inThought = false;
    }
  }
  return out.toString();
}
