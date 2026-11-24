import 'package:dna/services/storage_usage_service.dart';

/// 存储页的**展示文案**。
///
/// 这些分类名以前写在 `storage_usage_service.dart` 里（服务直接产出中文串），
/// 于是「算存储」的模块同时也决定了界面怎么说 —— 改文案要去服务里翻、
/// 服务单测也要断言字符串。
///
/// 搬到这里之后分层是：**服务给数据（[StorageCategory]），页面给措辞**。
String storageCategoryLabel(StorageCategory category) => switch (category) {
  StorageCategory.conversations => '会话',
  StorageCategory.characters => '角色卡',
  StorageCategory.worlds => '世界',
  StorageCategory.cache => '缓存',
  StorageCategory.downloads => '下载',
  StorageCategory.attachments => '附件',
  StorageCategory.other => '其他',
};
