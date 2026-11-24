/// 附件引用的**格式与纯函数**：IO 端与 Web 端共用同一份。
///
/// 原来 `attachment_storage_io.dart` 与 `attachment_storage_stub.dart` 各抄一遍
/// （正则、扩展名归一化、分片前缀、合法性判断），靠注释「两端必须用同一套规则」
/// 维持一致 —— 这正是会漂移的地方：扩展名会进引用，两边一旦不一致，同一份内容
/// 会被存成两个引用，去重白做。
library;

/// 合法引用：64 位小写十六进制 sha256 + '.' + 扩展名。
///
/// 顺带把路径穿越挡在门外（引用会从消息 JSON / 导入的备份里读回来，
/// 不是本机自己产生的也得当不可信数据处理）。
final RegExp kAttachmentRefPattern = RegExp(r'^[0-9a-f]{64}\.[a-z0-9]+$');

/// ext 归一化：小写、只留字母数字（`.PNG`→`png`、`jp!g`→`jpg`），空则 `bin`。
///
/// 扩展名来自用户文件名，必须洗一遍再用进路径（否则 `../`、空格、
/// 中文标点都会进文件名）。
String normalizeAttachmentExt(String ext) {
  final String cleaned = ext.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return cleaned.isEmpty ? 'bin' : cleaned;
}

/// 引用落在哪个前缀分片（sha256 前 2 位）。
///
/// **Web 端没有目录**，那边返回同一套前缀只是为了 API 与 IO 端一致，
/// 让调用方代码可以完全一样 —— 别以为 stub 真的在分片。
String shardOfRef(String ref) {
  if (ref.length < 2) return '00';
  return ref.substring(0, 2);
}

/// 引用是否合法（同时也是读取/删除前的路径穿越防线）。
bool isValidAttachmentRef(String ref) => kAttachmentRefPattern.hasMatch(ref);
