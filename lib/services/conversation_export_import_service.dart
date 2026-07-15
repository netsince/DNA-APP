import 'dart:convert';

import '../models/conversation.dart';
import '../models/ta.dart';
import 'ta_export_import_service.dart';

/// 对话导出格式
enum ConversationExportFormat {
  json,
  markdown,
}

/// 导出结果（文本内容与建议文件名）
class ConversationExportResult {
  const ConversationExportResult({
    required this.content,
    required this.suggestedFileName,
  });

  final String content;
  final String suggestedFileName;
}

/// 导入时某个角色需要的决议信息（供 UI 展示）
class NeededCharacter {
  const NeededCharacter({
    required this.originalTaId,
    required this.hasCard,
    this.cardName,
  });

  final String originalTaId;
  final bool hasCard;

  /// 内嵌角色卡的名称（无卡时为 null）
  final String? cardName;
}

/// 导入时的角色决议
class CharacterImportDecision {
  const CharacterImportDecision({
    required this.originalTaId,
    required this.importAsNew,
    this.existingTaId,
  });

  /// 是否将内嵌角色卡作为新角色导入（false 表示使用已有角色）
  final bool importAsNew;

  /// 原始角色 ID（对话中引用的 ID）
  final String originalTaId;

  /// 当 importAsNew 为 false 时，映射到已有角色的 ID
  final String? existingTaId;
}

/// 解析后的对话导入数据（图片尚未落盘）
class ConversationImportData {
  const ConversationImportData({
    required this.conversations,
    /// 原始角色 ID -> 本应用导出包 JSON（含内嵌图片与溯源信息）
    required this.embeddedPackages,
  });

  final List<Conversation> conversations;
  final Map<String, Map<String, dynamic>> embeddedPackages;

  /// 收集所有对话引用到的角色 ID（单聊 taId + 群聊 memberTaIds）
  Set<String> collectTaIds() {
    final Set<String> ids = <String>{};
    for (final Conversation c in conversations) {
      if (c.taId.isNotEmpty) ids.add(c.taId);
      for (final String m in c.memberTaIds) {
        if (m.isNotEmpty) ids.add(m);
      }
    }
    return ids;
  }
}

/// 对话导出导入服务
///
/// 导出：
/// - JSON：结构化数据，可选择性内嵌角色卡（含图片 base64 与溯源信息），便于再次导入。
/// - Markdown：人类可读文稿，按真实说话人姓名渲染，便于分享阅读。
///
/// 导入（仅 JSON）：解析后由调用方完成角色决议（导入卡 / 替换已有），本服务只负责
/// 构建结构化数据，不擅自决定角色归属。
class ConversationExportImportService {
  static const int _version = 1;
  static const String _app = 'dna-client';

  static String _timestamp() {
    final DateTime d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${p(d.month)}${p(d.day)}_${p(d.hour)}${p(d.minute)}${p(d.second)}';
  }

  static String _formatTimestamp(int ts) {
    if (ts <= 0) return '';
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(ts);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

  /// 收集对话引用到的角色 ID
  static Set<String> collectTaIds(List<Conversation> conversations) =>
      ConversationImportData(conversations: conversations, embeddedPackages: const {})
          .collectTaIds();

  /// 导出对话为文本（JSON 或 Markdown）
  static Future<ConversationExportResult> buildConversationExport({
    required List<Conversation> conversations,
    required Map<String, TA> tasById,
    required ConversationExportFormat format,
    required bool includeCharacterCards,
  }) async {
    if (format == ConversationExportFormat.markdown) {
      final String md = _buildMarkdown(conversations, tasById);
      return ConversationExportResult(
        content: md,
        suggestedFileName: 'DNA_conversation_${_timestamp()}.md',
      );
    }

    // JSON：构建内嵌角色卡（可选）
    final Map<String, Map<String, dynamic>> characters =
        <String, Map<String, dynamic>>{};
    if (includeCharacterCards) {
      for (final String taId in collectTaIds(conversations)) {
        final TA? ta = tasById[taId];
        if (ta == null) continue;
        final ExportImportResult<String> exported =
            await TaExportImportService.exportCharacter(ta);
        if (exported.success && exported.data != null) {
          final Object? decoded = jsonDecode(exported.data!);
          if (decoded is Map<String, dynamic>) {
            characters[taId] = decoded;
          }
        }
      }
    }

    final Map<String, dynamic> envelope = <String, dynamic>{
      'app': _app,
      'type': 'conversations',
      'version': _version,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'format': 'json',
      'includeCharacterCards': includeCharacterCards,
      'characters': characters,
      'conversations':
          conversations.map((Conversation c) => c.toJson()).toList(),
    };

    final String json = const JsonEncoder.withIndent('  ').convert(envelope);
    return ConversationExportResult(
      content: json,
      suggestedFileName: 'DNA_conversation_${_timestamp()}.json',
    );
  }

  /// 解析 JSON 导入内容
  static ExportImportResult<ConversationImportData> parseConversationImport(
    String jsonString,
  ) {
    try {
      final Object? decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return const ExportImportResult(
          success: false,
          message: '无效的对话文件格式',
        );
      }

      // 兼容两种顶层结构：
      // 1. 本应用导出包（含 app/type/conversations）
      // 2. 直接是 conversations 数组
      List<dynamic> rawConversations;
      Map<String, Map<String, dynamic>> embeddedPackages =
          <String, Map<String, dynamic>>{};

      if (decoded['conversations'] is List) {
        rawConversations = decoded['conversations'] as List<dynamic>;
        final Object? chars = decoded['characters'];
        if (chars is Map) {
          chars.forEach((dynamic key, dynamic value) {
            if (key is String && value is Map<String, dynamic>) {
              embeddedPackages[key] = value;
            }
          });
        }
      } else if (decoded case List<dynamic> list) {
        rawConversations = list;
      } else {
        return const ExportImportResult(
          success: false,
          message: '不支持的文件格式：既不是对话导出包，也不是对话数组',
        );
      }

      final List<Conversation> conversations = rawConversations
          .whereType<Map<String, dynamic>>()
          .map(Conversation.fromJson)
          .toList();

      if (conversations.isEmpty) {
        return const ExportImportResult(
          success: false,
          message: '文件中没有可导入的对话',
        );
      }

      return ExportImportResult(
        success: true,
        data: ConversationImportData(
          conversations: conversations,
          embeddedPackages: embeddedPackages,
        ),
      );
    } catch (e) {
      return ExportImportResult(success: false, message: '解析失败：$e');
    }
  }

  /// 构建可读的 Markdown 文稿
  static String _buildMarkdown(
    List<Conversation> conversations,
    Map<String, TA> tasById,
  ) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < conversations.length; i++) {
      if (i > 0) sb.writeln('\n---\n');
      final Conversation c = conversations[i];
      _appendConversationMarkdown(sb, c, tasById);
    }
    return sb.toString();
  }

  static void _appendConversationMarkdown(
    StringBuffer sb,
    Conversation c,
    Map<String, TA> tasById,
  ) {
    final String title = c.isGroup
        ? (c.groupName.trim().isNotEmpty ? c.groupName.trim() : '群聊')
        : (tasById[c.taId]?.name.isNotEmpty == true
            ? tasById[c.taId]!.name
            : '对话');
    sb.writeln('# $title');
    if (c.note.trim().isNotEmpty) {
      sb.writeln('> ${c.note.trim()}');
    }
    sb.writeln();

    final String fallbackName = c.isGroup
        ? '角色'
        : (tasById[c.taId]?.name.isNotEmpty == true
            ? tasById[c.taId]!.name
            : '角色');

    for (final ConversationMessage m in c.messages) {
      if (m.kind == 'summary_prompt') {
        // 系统提示，不渲染到可读文稿
        continue;
      }
      final String time = _formatTimestamp(m.timestamp);
      final String speaker;
      if (m.role == 'user') {
        speaker = '你';
      } else if (c.isGroup && m.speakerTaId != null && m.speakerTaId!.isNotEmpty) {
        speaker = tasById[m.speakerTaId]?.name.isNotEmpty == true
            ? tasById[m.speakerTaId]!.name
            : fallbackName;
      } else {
        speaker = fallbackName;
      }

      final String prefix = time.isNotEmpty ? '**$speaker** · $time' : '**$speaker**';
      if (m.kind == 'summary') {
        sb.writeln('> 📝 摘要：${m.text.trim()}');
      } else {
        sb.writeln('$prefix：');
        sb.writeln(m.text.trim());
      }
      sb.writeln();
    }
  }
}
