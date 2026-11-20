/// 已移除的「离线语音输入（STT）」在升级后的清理。
///
/// 旧版本把识别模型下载到 `<应用文档目录>/sherpa_models/<model.id>`（每个
/// 74MB~511MB），并在 SharedPreferences 里留了 6 个设置键。功能删除后这些
/// 文件既没人读也没人删 —— 升级用户会白占几百 MB。
///
/// 这里做**一次性**清理：删目录 + 清键 + 置标记。只跑一次，之后每次启动
/// 只是一次 SharedPreferences 字典查找，没有磁盘 IO。
library;
export 'removed_stt_cleanup_stub.dart'
    if (dart.library.io) 'removed_stt_cleanup_io.dart';