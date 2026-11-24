import '../../models/conversation.dart';
import '../../models/message_attachment.dart';
import 'chat_stream_parser.dart';

class ChatMessageBuilder {
  /// 匹配一段文本开头的「角色名+冒号」前缀(全/半角冒号均可,名字限 1-30 字,
  /// 不含换行与冒号)。仅作为输出侧安全网使用(见 [stripOwnSpeakerPrefix])。
  static final RegExp leadingSpeakerPrefix =
      RegExp(r'^\s*([^\n：:]{1,30})[：:]\s*');

  /// 输出侧安全网:若 [content] 以 [name] 自己的「名字：」前缀开头
  /// (全/半角冒号、冒号后可选空格均容忍),剥掉这一层并返回剩余文本;
  /// 否则原样返回。
  ///
  /// 注意:这是**兜底**而非主策略。主策略是 v2 群聊提示词架构——
  /// 历史不再用「名字：台词」格式示教模型,而是按聊天模板的角色通道映射
  /// (见 [historyEntryFor]),从结构上消除"模仿前缀"的诱因。
  static String stripOwnSpeakerPrefix(String content, String? name) {
    final String? own = name?.trim();
    if (own == null || own.isEmpty) {
      return content;
    }
    final RegExpMatch? match = leadingSpeakerPrefix.firstMatch(content);
    if (match == null) {
      return content;
    }
    return match.group(1)?.trim() == own ? content.substring(match.end) : content;
  }

  /// 群聊视角映射(v2 提示词架构的核心):把一条历史消息映射为发给模型的一条消息。
  ///
  /// 设计动机:旧方案把所有 AI 发言都格式化成「名字：台词」塞进同一条历史流,
  /// 这本身是在教模型"输出要带名字前缀",与系统提示的禁令自相矛盾。
  /// 新方案改由 **chat template 的角色语义**承载说话人信息:
  ///
  /// - 当前发言角色([perspectiveTaId])的历史发言 → `assistant` 消息,**不加任何标注**
  ///   ——模型在自己的通道里看到的全是自己说过的话,续写视角天然正确;
  /// - 其余所有人的发言(其他成员 + 人类用户)→ `user` 消息,内容以「[名字]」/
  ///   「[用户]」开头标注说话人。方括号标注是记录元数据,配合系统提示声明"不是台词格式"。
  ///
  /// 这样"谁在说话"由消息角色结构性表达,而不是靠文本约定,串角色与前缀模仿
  /// 的诱因从结构上消失。副作用与对策:
  /// - 相邻 user 消息需合并(Anthropic 要求严格交替;OpenAI 兼容端合并亦无害),
  ///   见 [mergeAdjacentSameRole];
  /// - 切换发言角色会改变历史的角色归属 → KV cache 全量失效一次,属可接受代价。
  static Map<String, dynamic> historyEntryFor({
    required ConversationMessage message,
    required bool groupPerspective,
    String? perspectiveTaId,
    String? Function(String? speakerTaId)? speakerNameResolver,
    String humanLabel = '用户',
    Map<String, String> imageDataUrls = const <String, String>{},
  }) {
    final String text =
        _withAttachmentText(message, stripThoughtTags(message.text));
    if (!groupPerspective) {
      // 单聊:原样映射,不做任何加工（附件文本已拼在 text 里）。
      return <String, dynamic>{
        'role': message.role,
        'content': _withImages(message, text, imageDataUrls),
      };
    }
    final String? sid = message.speakerTaId;
    if (message.role == 'assistant' &&
        (sid == null || sid.isEmpty || sid == perspectiveTaId)) {
      // 当前角色本人的发言(speakerTaId 为空的存量数据回退归入当前角色):
      // 自己的声音,绝不加标注。
      return <String, dynamic>{'role': 'assistant', 'content': text};
    }
    if (message.role == 'user') {
      return <String, dynamic>{
        'role': 'user',
        'content': _withImages(message, '[$humanLabel] $text', imageDataUrls),
      };
    }
    // 其他成员的发言 → user 通道 + 方括号标注。
    final String? name = speakerNameResolver?.call(sid);
    final String label = (name == null || name.isEmpty) ? '成员' : name;
    return <String, dynamic>{
      'role': 'user',
      'content': _withImages(message, '[$label] $text', imageDataUrls),
    };
  }

  /// 把图片附件接成多模态内容部分。
  ///
  /// 没有图片、或图片数据没准备好（读盘失败/超出本次请求的图片配额）时，
  /// 原样返回字符串 —— 纯文本请求永远保持最兼容的形态。
  static Object _withImages(
    ConversationMessage message,
    String text,
    Map<String, String> imageDataUrls,
  ) {
    if (message.attachments.isEmpty || imageDataUrls.isEmpty) return text;
    final List<Map<String, dynamic>> parts = <Map<String, dynamic>>[];
    if (text.isNotEmpty) {
      parts.add(<String, dynamic>{'type': 'text', 'text': text});
    }
    for (final MessageAttachment a in message.attachments) {
      if (!a.isImage) continue;
      final String? url = imageDataUrls[a.ref];
      if (url == null) continue;
      parts.add(<String, dynamic>{
        'type': 'image_url',
        'image_url': <String, dynamic>{'url': url},
      });
    }
    if (parts.length <= 1) return text;
    return parts;
  }

  /// 把附件内容拼进这条消息的文本。
  ///
  /// * **文本类附件**：把抽取出的内容整段塞进去（任何模型都能读）；
  /// * **图片**：先只留一行说明，真正的多模态 part 由请求层按模型能力组装；
  ///   这样纯文本模型至少知道「用户附了张图」，而不是对着一句空话回答；
  /// * **其他文件**（暂时喂不进去的，比如 PDF/压缩包）：同样留一行说明。
  ///
  /// 这条规则只影响「发给模型的内容」，消息本身存的仍是用户原话 + 附件元数据。
  static String _withAttachmentText(
    ConversationMessage message,
    String text,
  ) {
    if (message.attachments.isEmpty) return text;
    final StringBuffer sb = StringBuffer(text);
    for (final MessageAttachment a in message.attachments) {
      if (a.isText) {
        final String body = a.textPreview ?? '';
        if (body.trim().isEmpty) continue;
        // 只发前 kAttachmentPreviewChars 字：要在文本里说清楚「这是节选」，
        // 否则模型会当成全文读完，用户也以为整份文件都进去了。
        final bool truncated = a.textChars > body.length;
        sb
          ..write('\n\n[附件「')
          ..write(a.name)
          ..write(truncated
              ? '」内容开始（全文 ${a.textChars} 字，这里只给前 ${body.length} 字）]\n'
              : '」内容开始]\n')
          ..write(body)
          ..write('\n[附件「')
          ..write(a.name)
          ..write('」内容结束]');
      } else if (a.isImage) {
        sb
          ..write('\n\n[用户附了一张图片：')
          ..write(a.name)
          ..write(']');
      } else {
        sb
          ..write('\n\n[用户附加了文件：')
          ..write(a.name)
          ..write(']');
      }
    }
    return sb.toString();
  }

  /// 摘要作为一条 system 消息注入时的前缀。
  ///
  /// 「不代表你的身份」这半句是**护栏**：摘要是一段纯文本，模型很容易把它当成
  /// 自己的第一人称经历（历史上摘要还是按用户视角生成的），于是把用户的身份认成自己。
  static const String summarySystemPrefix = '对话摘要（第三方客观记录，不代表你的身份）：\n';

  /// 摘要（纯文本）里的说话人标签：人类 = 「用户」，AI = **各自的角色名**。
  ///
  /// 与 [historyEntryFor] 是同一件事的两面：发给模型的历史用**消息通道**表达说话人，
  /// 而摘要是一段纯文本，只能用**名字**表达。这里曾经一律写「助手」——
  /// 等于把所有 AI 成员糊成同一个人，而模型被教过的约定是「assistant = 我自己」
  /// （见 chat_system_prompt 的群聊规则），于是摘要里的「助手：」会被读成它自己的台词，
  /// 别人的话和它自己的话互相张冠李戴：这正是"生成摘要后角色错乱"的根源之一。
  static String summarySpeakerLabel({
    required ConversationMessage message,
    String? fallbackAssistantName,
    String? Function(String? speakerTaId)? speakerNameResolver,
    String humanLabel = '用户',
  }) {
    if (message.role == 'user') {
      return humanLabel;
    }
    final String? named = speakerNameResolver?.call(message.speakerTaId);
    if (named != null && named.trim().isNotEmpty) {
      return named.trim();
    }
    // 存量数据可能没有 speakerTaId：退回当前角色名，实在没有就叫「成员」。
    final String? fallback = fallbackAssistantName?.trim();
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    return '成员';
  }

  /// 把一段对话拼成摘要用的文本：每行「说话人：内容」。
  ///
  /// 说话人一律用真实名字（人类为「用户」），不再用「助手」这种会与通道约定打架的泛称。
  static String buildSummaryTranscript(
    List<ConversationMessage> messages, {
    String? fallbackAssistantName,
    String? Function(String? speakerTaId)? speakerNameResolver,
    String humanLabel = '用户',
  }) {
    return messages
        .map((ConversationMessage m) {
          final String label = summarySpeakerLabel(
            message: m,
            fallbackAssistantName: fallbackAssistantName,
            speakerNameResolver: speakerNameResolver,
            humanLabel: humanLabel,
          );
          return '$label：${m.text}';
        })
        .join('\n');
  }

  /// 合并相邻的同角色消息(自后向前并入前一条,以 \n 连接,保持顺序稳定)。
  ///
  /// 群聊视角映射会产生连续多条 user 消息;Anthropic 要求 user/assistant
  /// 严格交替,OpenAI 兼容端点对连续同角色也兼容但合并后语义一致且更省请求结构。
  /// 必须在追加本轮真实 user 输入([buildMessagesFrom] 的 extraUserText)**之前**
  /// 调用,避免把新输入并进历史。
  static void mergeAdjacentSameRole(List<Map<String, dynamic>> payload) {
    for (int i = payload.length - 1; i > 0; i--) {
      if (payload[i]['role'] == payload[i - 1]['role']) {
        payload[i - 1]['content'] =
            '${payload[i - 1]['content']}\n${payload.removeAt(i)['content']}';
      }
    }
  }

  static List<Map<String, dynamic>> buildMessagesFrom({
    required String systemPrompt,
    required List<ConversationMessage> messages,
    String? summaryText,
    String? summaryPrefix,
    String? extraUserText,
    String? extraSystemTail,
    bool groupPerspective = false,
    String? perspectiveTaId,
    String? Function(String? speakerTaId)? speakerNameResolver,
    String? authorNote,
    int authorNoteInterval = 0,
    String? loreText,
    Map<String, String> imageDataUrls = const <String, String>{},
  }) {
    // 缓存友好布局：静态 system prompt 在前，摘要随后，历史按追加顺序排列，
    // 动态内容（Lorebook 词条、Author's Note）统一放在历史之后。
    // 这样 system + 摘要 + 历史的组合前缀保持稳定，最大化 KV cache 命中。
    // （群聊视角下切换发言角色会使角色归属变化、缓存失效一次，属已知代价。）
    final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[];
    if (systemPrompt.trim().isNotEmpty) {
      payload.add(<String, dynamic>{'role': 'system', 'content': systemPrompt.trim()});
    }
    if (summaryText != null &&
        summaryText.trim().isNotEmpty &&
        summaryPrefix != null &&
        summaryPrefix.isNotEmpty) {
      payload.add(<String, dynamic>{
        'role': 'system',
        'content': '$summaryPrefix${summaryText.trim()}',
      });
    }
    for (final ConversationMessage message in messages) {
      if (message.kindEnum != MessageKind.message) {
        continue;
      }
      payload.add(historyEntryFor(
        message: message,
        groupPerspective: groupPerspective,
        perspectiveTaId: perspectiveTaId,
        speakerNameResolver: speakerNameResolver,
        imageDataUrls: imageDataUrls,
      ));
    }
    if (groupPerspective) {
      mergeAdjacentSameRole(payload);
    }
    // 动态尾部：Lorebook 激活词条（按需注入，不污染前缀）。
    if (loreText != null && loreText.trim().isNotEmpty) {
      payload.add(<String, dynamic>{'role': 'system', 'content': loreText.trim()});
    }
    // 动态尾部：作者注释 Author's Note。interval > 0 时以固定位置注入，
    // 避免深度注入导致历史中部前缀不稳定。
    if (authorNote != null &&
        authorNote.trim().isNotEmpty &&
        authorNoteInterval > 0) {
      payload.add(<String, dynamic>{'role': 'system', 'content': authorNote.trim()});
    }
    // 极少数入口（「继续说」）需要在最尾部追加一条 **system** 指令：
    // 语义是「对模型的额外要求」，不是用户发言，所以不能走 extraUserText（那条是 user）。
    if (extraSystemTail != null && extraSystemTail.trim().isNotEmpty) {
      payload.add(<String, dynamic>{
        'role': 'system',
        'content': extraSystemTail.trim(),
      });
    }
    if (extraUserText != null && extraUserText.trim().isNotEmpty) {
      payload.add(<String, dynamic>{'role': 'user', 'content': extraUserText.trim()});
    }
    return payload;
  }

  /// 生成 Lorebook 动态尾部的 system 消息（为空返回 null）。
  /// 供 [buildMessagesFrom] 与手工组装 payload 的入口（如"继续"）复用。
  static Map<String, dynamic>? loreSystemMessage(String loreText) {
    if (loreText.trim().isEmpty) {
      return null;
    }
    return <String, dynamic>{'role': 'system', 'content': loreText.trim()};
  }
}
