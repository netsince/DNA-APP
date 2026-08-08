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
        // tiktoken 仅内置 OpenAI 模型；对 deepseek / zhipu / qwen 等
        // BPE 系中文模型回退 cl100k_base 作合理近似，保证预算跨模型可预测。
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
      final int approxCount = approximateTokens(text);
      _tokenCache[messageId] = TokenCacheEntry(text: text, count: approxCount);
      return approxCount;
    }

    final Tiktoken encoding = _ensureEncoding(model);
    final int count = encoding.encode(text).length;
    _tokenCache[messageId] = TokenCacheEntry(text: text, count: count);
    return count;
  }

  /// CJK 感知的长文本 token 近似：中文（含 CJK 标点）按约 1 token/字，
  /// 其余按约 4 字符/token。比统一的 length/4 在中文为主的对话里更接近真实值。
  static int approximateTokens(String text) {
    int cjk = 0;
    for (int i = 0; i < text.length; i++) {
      final int code = text.codeUnitAt(i);
      if ((code >= 0x3400 && code <= 0x9FFF) || // CJK 统一表意文字
          (code >= 0xF900 && code <= 0xFAFF) || // CJK 兼容表意文字
          (code >= 0x3000 && code <= 0x303F) || // CJK 标点
          (code >= 0xFF00 && code <= 0xFFEF)) {
        // 全角字符
        cjk++;
      }
    }
    return cjk + ((text.length - cjk) / 4).ceil();
  }
}
