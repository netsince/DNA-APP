// 聊天附件存储入口 —— **内容寻址**（content-addressed）。
//
// 「按内容寻址」= 拿文件内容的 sha256 当文件名：同一份字节不管被发送多少次、
// 被多少条消息引用，磁盘上永远只存一份。这样做的理由：
//   * 空间：撤回重发、回溯重填、同一张图出现在多个会话里，都只占一份体积；
//   * 时间：保存前先看目标文件在不在，命中就直接返回，不用再写一遍几十 MB；
//   * 一致性：引用就是内容的指纹，同一份内容必然是同一个引用（天然幂等），
//     消息里只存 '<sha256>.<ext>' 这种短字符串，不存 base64 大块字节。
//
// 通过条件导出加载平台实现：
// - IO 平台（Android/iOS/桌面）：字节落盘
//   <应用文档目录>/attachments/<sha256 前 2 位>/<sha256>.<ext>；
// - Web 平台：字节存 IndexedDB（Hive box 'attachments'），引用格式与 IO 端一致。
//
// 两端引用格式完全一样，所以消息 JSON 跨端可读；但字节不随引用走，
// 换端/换机后需要重新上传（与 ImageStorage 的取舍相同）。
export 'attachment_storage_stub.dart'
    if (dart.library.io) 'attachment_storage_io.dart';

// 单条消息最多带几个附件。真身在 models/attachment_draft.dart（附件草稿与输入区
// 都在用它），这里**再导出同一份声明**而不是另写一个常量：调用方只 import 本入口
// 就能拿到全部上限，同时与草稿共用同一个真值，不会出现「两处各写 3、哪天一处
// 改成 4」的分叉（导出同一份声明也不会产生同名歧义）。
export '../models/attachment_draft.dart' show kMaxAttachmentsPerMessage;
