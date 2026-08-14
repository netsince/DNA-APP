import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/user_identity.dart';
import '../models/world.dart';

/// 备份清单
class DataBackupManifest {
  const DataBackupManifest({
    required this.version,
    required this.exportedAt,
    required this.app,
    this.type = 'full',
  });

  final int version;
  final String exportedAt;
  final String app;

  /// 备份类型：'full'（全量：角色/世界/对话）或 'conversations'（仅对话）
  final String type;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'exportedAt': exportedAt,
        'app': app,
        'type': type,
      };

  factory DataBackupManifest.fromJson(Map<String, dynamic> json) {
    return DataBackupManifest(
      version: (json['version'] as int?) ?? 1,
      exportedAt: (json['exportedAt'] as String?) ?? '',
      app: (json['app'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'full',
    );
  }
}

/// 解析后的备份数据（图片懒加载：仅在落盘时逐个解压，避免整包进内存）
class ParsedBackup {
  const ParsedBackup({
    required this.manifest,
    required this.tas,
    required this.worlds,
    required this.conversations,
    required this.identities,
    required this.imageBytes,
    this.dispose,
  });

  final DataBackupManifest manifest;
  final List<TA> tas; // 其中的 images 为相对文件名
  final List<World> worlds;
  final List<Conversation> conversations;
  final List<UserIdentity> identities;

  /// 相对文件名 -> 懒加载的图片字节。IO 平台从文件流按需解压，
  /// 避免所有图片同时驻留内存；访问后即可释放引用。
  final Map<String, List<int> Function()> imageBytes;

  /// 解析完成后释放底层文件流等资源（IO 平台文件流需要显式关闭）。
  final Future<void> Function()? dispose;
}

/// 导入结果报告
class DataImportReport {
  const DataImportReport({
    required this.replaced,
    required this.tasCount,
    required this.worldsCount,
    required this.conversationsCount,
    this.identitiesCount = 0,
    this.backupPath,
    this.backupError,
  });

  final bool replaced;
  final int tasCount;
  final int worldsCount;
  final int conversationsCount;
  final int identitiesCount;
  final String? backupPath;
  final String? backupError;
}
