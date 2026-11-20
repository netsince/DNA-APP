/// 一条消息携带的附件描述（**只存元数据**，字节在 [AttachmentStore] 里）。
///
/// 为什么字节不塞进消息 JSON：
/// * 消息会被频繁序列化（Hive、导出、摘要），几 MB 的 base64 会让读写变慢；
/// * 同一份文件可能被多轮引用，字节该按内容去重存一份，而不是每条消息各存一份。
class MessageAttachment {
  const MessageAttachment({
    required this.ref,
    required this.name,
    required this.mime,
    required this.size,
    required this.kind,
    this.textPreview,
    this.textChars = 0,
  });

  /// 内容寻址引用：`<sha256>.<ext>`，同时充当「这份字节只存一次」的凭据。
  final String ref;

  /// 原始文件名（展示用）。
  final String name;

  /// MIME 类型（`image/png`、`text/plain` 等）。
  final String mime;

  /// 字节数（原文件大小，不是压缩后）。
  final int size;

  /// `'image'` | `'text'` | `'file'`。
  ///
  /// 只有 image 需要模型支持视觉；text 是「已经抽成文字」的（任何模型都能用）；
  /// file 是「目前喂不进去」的（比如 PDF 扫描件），只作为记录与展示。
  final String kind;

  /// 文本类附件抽取出的前若干字符（发请求时拼进 prompt；同时也是气泡预览）。
  final String? textPreview;

  /// 文本类附件的全文长度（用于 token 估算；预览可能被截断）。
  final int textChars;

  bool get isImage => kind == 'image';
  bool get isText => kind == 'text';

  /// 人类可读的大小，如 `1.2 MB`。
  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ref': ref,
        'name': name,
        'mime': mime,
        'size': size,
        'kind': kind,
        if (textPreview != null) 'textPreview': textPreview,
        if (textChars > 0) 'textChars': textChars,
      };

  static MessageAttachment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> json = raw.map(
      (Object? k, Object? v) => MapEntry<String, dynamic>(k.toString(), v),
    );
    final Object? ref = json['ref'];
    if (ref is! String || ref.isEmpty) return null;
    return MessageAttachment(
      ref: ref,
      name: (json['name'] as String?) ?? '附件',
      mime: (json['mime'] as String?) ?? 'application/octet-stream',
      size: (json['size'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] as String?) ?? 'file',
      textPreview: json['textPreview'] as String?,
      textChars: (json['textChars'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() => 'MessageAttachment($name, $kind, $sizeLabel)';
}

/// 从 JSON 里安全解析附件列表（旧数据没有这个字段 → 空列表，不崩）。
List<MessageAttachment> parseAttachments(Object? raw) {
  if (raw is! List) return const <MessageAttachment>[];
  final List<MessageAttachment> out = <MessageAttachment>[];
  for (final Object? item in raw) {
    final MessageAttachment? a = MessageAttachment.fromJson(item);
    if (a != null) out.add(a);
  }
  return List<MessageAttachment>.unmodifiable(out);
}
