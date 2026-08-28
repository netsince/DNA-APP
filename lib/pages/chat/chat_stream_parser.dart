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

/// 返回 [buffer] 的最长后缀,该后缀是 [tags] 中某个标签的**真前缀**
/// (大小写不敏感,与 [findTag] 的匹配口径一致)。
///
/// 流式分块可能恰好把标签切成两半(如 `<thi` | `nk>`):
/// 若把整个 buffer 直接冲进正文,半个标签会泄漏给用户且永远无法回收。
/// 因此无完整标签命中时,必须把这个"可能是半个标签"的尾巴扣在 buffer 里,
/// 等下一个 chunk 拼上来再判定。
String _longestPartialTagTail(String buffer, List<String> tags) {
  final String lower = buffer.toLowerCase();
  int longest = 0;
  for (final String tag in tags) {
    // 尾部长度上限:不超过 buffer 长度,也不等于标签全长(等长即 findTag 已命中)。
    final int maxLen =
        tag.length - 1 < buffer.length ? tag.length - 1 : buffer.length;
    for (int len = maxLen; len > longest; len--) {
      final bool isPrefix =
          tag.startsWith(lower.substring(lower.length - len));
      if (isPrefix) {
        longest = len;
        break;
      }
    }
  }
  return longest == 0 ? '' : buffer.substring(buffer.length - longest);
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
        // 无完整开标签:扣住可能是半个开标签的尾巴,只输出安全前缀。
        final String tail = _longestPartialTagTail(state.buffer, openTags);
        if (tail.length == state.buffer.length) {
          break; // 整个 buffer 都可能是半个标签,等待后续 chunk。
        }
        state.visible +=
            state.buffer.substring(0, state.buffer.length - tail.length);
        state.buffer = tail;
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
        // 无完整闭标签:同样扣住半个闭标签的尾巴,避免 `</thin` 泄进思考文本。
        final String tail = _longestPartialTagTail(state.buffer, closeTags);
        if (tail.length == state.buffer.length) {
          break;
        }
        state.thought +=
            state.buffer.substring(0, state.buffer.length - tail.length);
        state.buffer = tail;
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

/// 流结束后调用:把仍滞留在 buffer 里的尾巴按当前状态落位。
///
/// holdback 机制会让半截标签滞留在 buffer 里等待下一 chunk;
/// 若流已结束,不会再有后续数据,这些字节就是字面文本,必须归还:
/// - 不在思考中 → 归还到可见正文;
/// - 思考未闭合 → 归还到思考内容(与旧行为一致:未闭合的思考整体归入 thought)。
///
/// 返回最终可见文本,并同步更新 [thoughtsByMessageId]。
String finalizeStreamState({
  required Map<String, StreamParseState> streamStates,
  required Map<String, ThoughtEntry> thoughtsByMessageId,
  required String messageId,
}) {
  final StreamParseState? state = streamStates[messageId];
  if (state == null) {
    return '';
  }
  if (state.buffer.isNotEmpty) {
    if (state.inThought) {
      state.thought += state.buffer;
    } else {
      state.visible += state.buffer;
    }
    state.buffer = '';
  }
  thoughtsByMessageId[messageId] = ThoughtEntry(text: state.thought.trim());
  return state.visible;
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
      // 思考内容整体丢弃——历史实现在这里误用 out.write 把内容回吐进正文,
      // 导致发送给模型的上下文混入思考文本。
      buffer = buffer.substring(close.index + close.tag.length);
      inThought = false;
    }
  }
  return out.toString();
}
