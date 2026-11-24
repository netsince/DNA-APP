import 'package:dna/services/storage_texts.dart';
import 'package:dna/services/storage_usage_service.dart';

/// [StorageTexts] 的中文实现（存储页用它，服务不再持有任何中文）。
class StorageTextsZh implements StorageTexts {
  const StorageTextsZh();

  @override
  String conversationGroup() => '群聊';

  @override
  String conversationTitleFallback() => '未命名对话';

  @override
  String messageCount(int count) => '$count 条消息';

  @override
  String summaryCount(int count) => '$count 段摘要';

  @override
  String unnamedCharacter() => '未命名角色';

  @override
  String unnamedWorld() => '未命名世界';

  @override
  String databaseReadFailed(Object error) => '读取本地数据库失败：$error';

  @override
  String ttsModel() => '端侧语音模型';

  @override
  String ttsCacheName(int count) => '合成语音缓存（$count 个音频）';

  @override
  String ttsCacheNote() => '听过的台词，再听不用重新合成';

  @override
  String attachmentHashOnlyNote() => '附件（只有哈希名）';

  @override
  String attachmentChatNote() => '聊天附件';

  @override
  String backupsNote() => '自动备份（可以自己删）';

  @override
  String legacySttName() => '旧版语音输入模型（已废弃）';

  @override
  String legacySttNote(int count) => '$count 个文件，可以删';

  @override
  String dbFileNote() => '数据库文件';

  @override
  String hiveBoxItemName(String label, String boxName) =>
      '$label（$boxName.hive）';

  @override
  String identityData() => '身份数据';

  @override
  String settingsData() => '设置数据';

  @override
  String attachmentIndexWeb() => '附件索引（网页版）';

  @override
  String unownedCharacterNote() => '认不出属于哪个角色';

  @override
  String missingCharacterNote() => '找不到对应的角色卡';

  @override
  String indexOverheadName(String boxes) => '索引与空闲空间（$boxes.hive）';

  @override
  String indexOverheadNote() => '数据库文件的固定开销，不算在任何一条内容里';

  @override
  String characterNoteImages(int count) => '图片 $count 张';

  @override
  String characterNoteMusic(int count) => '背景音乐 $count 首';

  @override
  String characterNoteData(int bytes) =>
      '资料 ${formatStorageBytes(bytes)}';

  @override
  String characterNoMedia() => '没有图片/音乐';
}
