import 'dart:convert';

import 'package:archive/archive.dart';

import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import 'export_file_utils.dart';
import 'ta_export_import_models.dart';

/// 把一段会话导出成 **人类可读的 Markdown**（以及可选的 EPUB 文本结构）。
///
/// 与已有的「JSON 备份导出」互补：
/// * JSON 用于换机/备份，机器读；
/// * Markdown 用于阅读、投稿、丢进 Typora/Obsidian，人读。
///
/// 格式约定：
/// ```
/// # 标题
/// > 角色 / 世界 / 消息数 / 导出时间
///
/// **角色名** · 2026-11-20 18:30
/// 正文（括号旁白原样保留）
/// ```
class ConversationMarkdownExport {
  ConversationMarkdownExport._();

  /// 生成 Markdown 文本。
  ///
  /// [taNames] 用来把 `speakerTaId` 还原成名字；找不到时退回「TA」。
  /// [userLabel] 是用户这一方的称呼（身份名，未设置时用「我」）。
  static String build({
    required Conversation conversation,
    required Map<String, String> taNames,
    required String title,
    String userLabel = '我',
    String? worldName,
    String? strategySummary,
    bool includeMetadata = true,
    bool includeTimestamps = true,
    bool includeSummaries = true,
  }) {
    final StringBuffer out = StringBuffer();
    out.writeln('# $title');
    out.writeln();

    if (includeMetadata) {
      final List<String> meta = <String>[];
      if (worldName != null && worldName.trim().isNotEmpty) {
        meta.add('世界：$worldName');
      }
      meta.add('消息：${conversation.messages.length} 条');
      meta.add('导出：${_stamp(DateTime.now())}');
      if (strategySummary != null && strategySummary.trim().isNotEmpty) {
        meta.add('写法：$strategySummary');
      }
      out.writeln('> ${meta.join('  ·  ')}');
      out.writeln();
      out.writeln('---');
      out.writeln();
    }

    for (final ConversationMessage m in conversation.messages) {
      if (m.kind == 'summary') {
        if (!includeSummaries) continue;
        out.writeln('> **剧情摘要**：${m.text.trim()}');
        out.writeln();
        continue;
      }

      final bool mine = m.role == 'user';
      final String speaker = mine
          ? userLabel
          : (m.speakerTaId != null
              ? (taNames[m.speakerTaId] ?? taNames[conversation.taId] ?? 'TA')
              : (taNames[conversation.taId] ?? 'TA'));

      final String time = includeTimestamps
          ? '  ·  ${_stamp(DateTime.fromMillisecondsSinceEpoch(m.timestamp))}'
          : '';
      out.writeln('**$speaker**$time');
      out.writeln();
      out.writeln(m.text.trim());
      out.writeln();
    }

    out.writeln('---');
    out.writeln();
    out.writeln('*由 DNA 导出*');
    return out.toString();
  }

  /// 生成 EPUB 用的 XHTML 章节（不含 OPF/NAV，由 [buildEpubParts] 组装）。
  static List<String> buildEpubChapters({
    required Conversation conversation,
    required Map<String, String> taNames,
    required String title,
    String userLabel = '我',
  }) {
    final List<ConversationMessage> msgs = conversation.messages
        .where((ConversationMessage m) => m.kind != 'summary')
        .toList();

    // 每 ~40 条切一章，避免单章过大
    const int perChapter = 40;
    final List<String> chapters = <String>[];
    for (int i = 0; i < msgs.length; i += perChapter) {
      final List<ConversationMessage> slice =
          msgs.sublist(i, (i + perChapter).clamp(0, msgs.length));
      final StringBuffer body = StringBuffer();
      body.writeln('<h2>第 ${chapters.length + 1} 节</h2>');
      for (final ConversationMessage m in slice) {
        final bool mine = m.role == 'user';
        final String speaker = mine
            ? userLabel
            : (m.speakerTaId != null
                ? (taNames[m.speakerTaId] ?? taNames[conversation.taId] ?? 'TA')
                : (taNames[conversation.taId] ?? 'TA'));
        body.writeln('<p class="${mine ? 'me' : 'ta'}">');
        body.writeln('<span class="speaker">${_esc(speaker)}</span><br/>');
        body.writeln(_esc(m.text.trim()).replaceAll('\n', '<br/>'));
        body.writeln('</p>');
      }
      chapters.add(body.toString());
    }
    if (chapters.isEmpty) {
      chapters.add('<h2>$title</h2><p>（没有可导出的消息）</p>');
    }
    return chapters;
  }

  /// 落盘 / 分享 Markdown。
  static Future<String?> exportMarkdown({
    required Conversation conversation,
    required Map<String, String> taNames,
    required String title,
    String userLabel = '我',
    String? worldName,
    String? strategySummary,
  }) async {
    final String md = build(
      conversation: conversation,
      taNames: taNames,
      title: title,
      userLabel: userLabel,
      worldName: worldName,
      strategySummary: strategySummary,
    );
    final String fileName = ExportFileUtils.buildFileName(
      name: title,
      fallbackName: '对话',
      ext: 'md',
    );
    final ExportImportResult<String?> r = await ExportFileUtils.exportText(
      content: md,
      fileName: fileName,
      ext: 'md',
      dialogTitle: '导出为 Markdown',
    );
    if (!r.success) {
      debugPrint('markdown export failed: ${r.message}');
      return null;
    }
    return r.data;
  }

  /// 把会话打成一个合法 EPUB3（可用任何电子书阅读器打开）。
  ///
  /// 结构：`mimetype`（必须第一个且不压缩）→ `META-INF/container.xml`
  /// → `OEBPS/{content.opf,nav.xhtml,style.css,chapterN.xhtml}`。
  static Uint8List buildEpubBytes({
    required Conversation conversation,
    required Map<String, String> taNames,
    required String title,
    String userLabel = '我',
    String author = 'DNA ULTRA',
    String language = 'zh-CN',
  }) {
    final List<String> chapters = buildEpubChapters(
      conversation: conversation,
      taNames: taNames,
      title: title,
      userLabel: userLabel,
    );
    final String uid = 'urn:uuid:dna-${conversation.id}';
    final String stamp = DateTime.now().toUtc().toIso8601String();

    final StringBuffer manifest = StringBuffer();
    final StringBuffer spine = StringBuffer();
    final StringBuffer nav = StringBuffer();
    for (int i = 0; i < chapters.length; i++) {
      final int n = i + 1;
      manifest.writeln(
          '    <item id="ch$n" href="chapter$n.xhtml" media-type="application/xhtml+xml"/>');
      spine.writeln('    <itemref idref="ch$n"/>');
      nav.writeln('      <li><a href="chapter$n.xhtml">第 $n 节</a></li>');
    }

    final String opf = '<?xml version="1.0" encoding="utf-8"?>\n'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">\n'
        '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
        '    <dc:identifier id="bookid">$uid</dc:identifier>\n'
        '    <dc:title>${_esc(title)}</dc:title>\n'
        '    <dc:language>$language</dc:language>\n'
        '    <dc:creator>${_esc(author)}</dc:creator>\n'
        '    <meta property="dcterms:modified">$stamp</meta>\n'
        '  </metadata>\n'
        '  <manifest>\n'
        '    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\n'
        '    <item id="css" href="style.css" media-type="text/css"/>\n'
        '$manifest'
        '  </manifest>\n'
        '  <spine>\n'
        '$spine'
        '  </spine>\n'
        '</package>\n';

    final String navDoc = '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="$language">\n'
        '<head><title>${_esc(title)}</title></head>\n'
        '<body>\n'
        '  <nav epub:type="toc">\n'
        '    <h1>${_esc(title)}</h1>\n'
        '    <ol>\n'
        '$nav'
        '    </ol>\n'
        '  </nav>\n'
        '</body>\n'
        '</html>\n';

    const String css = 'body { font-family: serif; line-height: 1.7; margin: 1.2em; }\n'
        'h1 { font-size: 1.4em; }\n'
        'h2 { font-size: 1.1em; margin-top: 1.6em; }\n'
        'p { margin: 0.4em 0 0.9em; }\n'
        'p.me { text-align: right; color: #333; }\n'
        'p.ta { text-align: left; }\n'
        'span.speaker { font-weight: bold; font-size: 0.85em; color: #666; }\n';

    const String container = '<?xml version="1.0" encoding="utf-8"?>\n'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        '  <rootfiles>\n'
        '    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>\n'
        '  </rootfiles>\n'
        '</container>\n';

    final Archive archive = Archive();
    void add(String path, String data, {bool store = false}) {
      final List<int> bytes = utf8.encode(data);
      final ArchiveFile file = ArchiveFile(path, bytes.length, bytes);
      if (store) file.compression = CompressionType.none;
      archive.addFile(file);
    }

    // mimetype 必须是第一个条目且不压缩（EPUB 规范硬要求）
    add('mimetype', 'application/epub+zip', store: true);
    add('META-INF/container.xml', container);
    add('OEBPS/content.opf', opf);
    add('OEBPS/nav.xhtml', navDoc);
    add('OEBPS/style.css', css);
    for (int i = 0; i < chapters.length; i++) {
      final int n = i + 1;
      add(
        'OEBPS/chapter$n.xhtml',
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="$language">\n'
        '<head><title>${_esc(title)} · 第 $n 节</title>\n'
        '<link rel="stylesheet" type="text/css" href="style.css"/></head>\n'
        '<body>\n'
        '${chapters[i]}\n'
        '</body>\n'
        '</html>\n',
      );
    }

    final List<int> zipped = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipped);
  }

  /// 导出 EPUB；返回落盘路径，取消/失败返回 null。
  static Future<String?> exportEpub({
    required Conversation conversation,
    required Map<String, String> taNames,
    required String title,
    String userLabel = '我',
  }) async {
    final Uint8List bytes = buildEpubBytes(
      conversation: conversation,
      taNames: taNames,
      title: title,
      userLabel: userLabel,
    );
    if (bytes.isEmpty) return null;
    final String fileName = ExportFileUtils.buildFileName(
      name: title,
      fallbackName: '对话',
      ext: 'epub',
    );
    final ExportImportResult<String?> r = await ExportFileUtils.exportBytes(
      bytes: bytes,
      fileName: fileName,
      ext: 'epub',
      dialogTitle: '导出为 EPUB',
    );
    if (!r.success) {
      debugPrint('epub export failed: ${r.message}');
      return null;
    }
    return r.data;
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  static String _esc(String s) => const HtmlEscape().convert(s);
}
