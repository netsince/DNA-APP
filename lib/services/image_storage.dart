// TA 图片存储抽象入口。
//
// 通过条件导出加载平台实现：
// - IO 平台（Android/iOS/桌面）：图片落盘 `<doc>/tas/`，引用 = 绝对路径
// - Web 平台：图片字节存 IndexedDB（Hive box），引用 = 逻辑文件名 `<taId>_<slot>.<ext>`
//
// 两端导出的备份 ZIP 均为「相对文件名 + 字节」的跨端格式，
// 因此通过 ImageStorage 的 readBytes / saveBytes 可做到手机 ↔ Web 双向互导。
export 'image_storage_stub.dart'
    if (dart.library.io) 'image_storage_io.dart';
