import '../../models/conversation.dart';
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
  static Map<String, String> historyEntryFor({
    required ConversationMessage message,
    required bool groupPerspective,
    String? perspectiveTaId,
    String? Function(String? speakerTaId)? speakerNameResolver,
    String humanLabel = '用户',
  }) {
    final String text = stripThoughtTags(message.text);
    if (!groupPerspective) {
      // 单聊:原样映射,不做任何加工。
      return <String, String>{'role': message.role, 'content': text};
    }
    final String? sid = message.speakerTaId;
    if (message.role == 'assistant' &&
        (sid == null || sid.isEmpty || sid == perspectiveTaId)) {
      // 当前角色本人的发言(speakerTaId 为空的存量数据回退归入当前角色):
      // 自己的声音,绝不加标注。
      return <String, String>{'role': 'assistant', 'content': text};
    }
    if (message.role == 'user') {
      return <String, String>{'role': 'user', 'content': '[$humanLabel] $text'};
    }
    // 其他成员的发言 → user 通道 + 方括号标注。
    final String? name = speakerNameResolver?.call(sid);
    final String label = (name == null || name.isEmpty) ? '成员' : name;
    return <String, String>{'role': 'user', 'content': '[$label] $text'};
  }

  /// 合并相邻的同角色消息(自后向前并入前一条,以 \n 连接,保持顺序稳定)。
  ///
  /// 群聊视角映射会产生连续多条 user 消息;Anthropic 要求 user/assistant
  /// 严格交替,OpenAI 兼容端点对连续同角色也兼容但合并后语义一致且更省请求结构。
  /// 必须在追加本轮真实 user 输入([buildMessagesFrom] 的 extraUserText)**之前**
  /// 调用,避免把新输入并进历史。
  static void mergeAdjacentSameRole(List<Map<String, String>> payload) {
    for (int i = payload.length - 1; i > 0; i--) {
      if (payload[i]['role'] == payload[i - 1]['role']) {
        payload[i - 1]['content'] =
            '${payload[i - 1]['content']}\n${payload.removeAt(i)['content']}';
      }
    }
  }

  static List<Map<String, String>> buildMessagesFrom({
    required String systemPrompt,
    required List<ConversationMessage> messages,
    String? summaryText,
    String? summaryPrefix,
    String? extraUserText,
    bool groupPerspective = false,
    String? perspectiveTaId,
    String? Function(String? speakerTaId)? speakerNameResolver,
    String? authorNote,
    int authorNoteInterval = 0,
    String? loreText,
  }) {
    // 缓存友好布局：静态 system prompt 在前，摘要随后，历史按追加顺序排列，
    // 动态内容（Lorebook 词条、Author's Note）统一放在历史之后。
    // 这样 system + 摘要 + 历史的组合前缀保持稳定，最大化 KV cache 命中。
    // （群聊视角下切换发言角色会使角色归属变化、缓存失效一次，属已知代价。）
    final List<Map<String, String>> payload = <Map<String, String>>[];
    if (systemPrompt.trim().isNotEmpty) {
      payload.add(<String, String>{'role': 'system', 'content': systemPrompt.trim()});
    }
    if (summaryText != null &&
        summaryText.trim().isNotEmpty &&
        summaryPrefix != null &&
        summaryPrefix.isNotEmpty) {
      payload.add(<String, String>{
        'role': 'system',
        'content': '$summaryPrefix${summaryText.trim()}',
      });
    }
    for (final ConversationMessage message in messages) {
      if (message.kind != 'message') {
        continue;
      }
      payload.add(historyEntryFor(
        message: message,
        groupPerspective: groupPerspective,
        perspectiveTaId: perspectiveTaId,
        speakerNameResolver: speakerNameResolver,
      ));
    }
    if (groupPerspective) {
      mergeAdjacentSameRole(payload);
    }
    // 动态尾部：Lorebook 激活词条（按需注入，不污染前缀）。
    if (loreText != null && loreText.trim().isNotEmpty) {
      payload.add(<String, String>{'role': 'system', 'content': loreText.trim()});
    }
    // 动态尾部：作者注释 Author's Note。interval > 0 时以固定位置注入，
    // 避免深度注入导致历史中部前缀不稳定。
    if (authorNote != null &&
        authorNote.trim().isNotEmpty &&
        authorNoteInterval > 0) {
      payload.add(<String, String>{'role': 'system', 'content': authorNote.trim()});
    }
    if (extraUserText != null && extraUserText.trim().isNotEmpty) {
      payload.add(<String, String>{'role': 'user', 'content': extraUserText.trim()});
    }
    return payload;
  }

  /// 生成 Lorebook 动态尾部的 system 消息（为空返回 null）。
  /// 供 [buildMessagesFrom] 与手工组装 payload 的入口（如"继续"）复用。
  static Map<String, String>? loreSystemMessage(String loreText) {
    if (loreText.trim().isEmpty) {
      return null;
    }
    return <String, String>{'role': 'system', 'content': loreText.trim()};
  }
}
