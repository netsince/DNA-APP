import 'package:flutter/foundation.dart';
import 'package:tiktoken/tiktoken.dart';

import 'chat_models.dart';

class ChatTokenCounter {
  final Map<String, TokenCacheEntry> _tokenCache = <String, TokenCacheEntry>{};
  Tiktoken? _tokenEncoding;
  String? _tokenEncodingModel;

  Tiktoken _ensureEncoding(String model) {
    if (_tokenEncoding == null || _tokenEncodingModel != model) {
      try {
        _tokenEncoding = encodingForModel(model);
      } catch (_) {
        _tokenEncoding = getEncoding('cl100k_base');
      }
      _tokenEncodingModel = model;
      _tokenCache.clear();
    }
    return _tokenEncoding!;
  }

  int countTokens({
    required String model,
    required String messageId,
    required String text,
  }) {
    final TokenCacheEntry? cached = _tokenCache[messageId];
    if (cached != null && cached.text == text) {
      return cached.count;
    }
    if (text.isEmpty) {
      _tokenCache[messageId] = const TokenCacheEntry(text: '', count: 0);
      return 0;
    }

    // 对于长文本，使用近似计算避免阻塞主线程
    if (text.length > 10000 && !kDebugMode) {
      final int approxCount = (text.length / 4).ceil();
      _tokenCache[messageId] = TokenCacheEntry(text: text, count: approxCount);
      return approxCount;
    }

    final Tiktoken encoding = _ensureEncoding(model);
    final int count = encoding.encode(text).length;
    _tokenCache[messageId] = TokenCacheEntry(text: text, count: count);
    return count;
  }
}
