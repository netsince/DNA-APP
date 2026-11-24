/// 存储报告里所有**面向用户**的措辞。
///
/// `StorageUsageService` 只认这个接口、不认中文：它算字节、分类、明细，措辞由
/// 调用方（页面）提供。以前服务直接产出「合成语音缓存（3 个音频）」这种句子，
/// 于是改文案要去服务里翻、服务单测也要断言字符串 —— 算数据的模块同时决定了
/// 界面怎么说。
///
/// 这里故意用「方法 + 参数」而不是「字符串模板」：需要拼接的动态部分（数量、
/// 字节数、box 名）由服务算好传进来，措辞与拼接顺序留在实现方。
abstract interface class StorageTexts {
  // ---- 会话 ----
  String conversationGroup();
  String conversationTitleFallback();
  String messageCount(int count);
  String summaryCount(int count);

  // ---- 兜底名 ----
  String unnamedCharacter();
  String unnamedWorld();

  // ---- 读库失败 ----
  String databaseReadFailed(Object error);

  // ---- 端侧语音模型 / 缓存 ----
  String ttsModel();
  String ttsCacheName(int count);
  String ttsCacheNote();

  // ---- 附件 / 备份 ----
  String attachmentHashOnlyNote();
  String attachmentChatNote();
  String backupsNote();

  // ---- 旧版语音输入 ----
  String legacySttName();
  String legacySttNote(int count);

  // ---- 数据库文件 ----
  String dbFileNote();
  String hiveBoxItemName(String label, String boxName);
  String identityData();
  String settingsData();
  String attachmentIndexWeb();

  // ---- 角色卡目录里的孤儿文件 ----
  String unownedCharacterNote();
  String missingCharacterNote();

  // ---- 索引与空闲空间 ----
  String indexOverheadName(String boxes);
  String indexOverheadNote();

  // ---- 角色卡备注 ----
  String characterNoteImages(int count);
  String characterNoteMusic(int count);
  String characterNoteData(int bytes);
  String characterNoMedia();
}
