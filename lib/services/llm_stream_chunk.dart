/// 流式补全的类型化分片(C1:sealed chunk 协议)。
///
/// 取代历史上"错误走 '[ERROR]' 前缀、思考走内联 think 标签"的字符串哨兵:
/// 四种分片类型互不相交,Dart 密封类保证消费端 switch 穷尽性检查。
///
/// 注意:模型自己在 content 里输出的字面思考标签(如 think/analysis/thought)
/// 仍由 chat_stream_parser 的状态机处理——本协议承载的是**通道语义**
/// (如 DeepSeek 的 reasoning_content 字段),而非文本标记。
sealed class LlmStreamChunk {
  const LlmStreamChunk();
}

/// 可见正文分片。
class LlmContentChunk extends LlmStreamChunk {
  const LlmContentChunk(this.text);

  final String text;
}

/// 思考过程分片(来自厂商独立字段,如 reasoning_content / thinking_delta)。
class LlmReasoningChunk extends LlmStreamChunk {
  const LlmReasoningChunk(this.text);

  final String text;
}

/// 非致命提示(如回复因达到 max_tokens 被截断)。不影响已产出的正文。
class LlmNoticeChunk extends LlmStreamChunk {
  const LlmNoticeChunk(this.message);

  final String message;
}

/// 致命错误分片:流以此收场,消费方应停止等待并展示 [message]。
class LlmErrorChunk extends LlmStreamChunk {
  const LlmErrorChunk(this.message);

  final String message;
}
