import 'package:dna/models/app_settings.dart';
import 'package:dna/models/app_settings_patch.dart';
import 'package:dna/services/settings_service.dart';

/// 设置这一域的**状态与读写**（拆出 `AppController` 的第五块，也是最后一块）。
///
/// 它只管三件事：持有当前 [AppSettings]、从存储加载、把改动落盘。存储细节
/// （71 条字段表、单键落盘、类型宽松读取）都在 [SettingsService] 里，这里不重复。
///
/// **写一个键只落一个键**：`patch` 走 `applySettingsPatch` + `saveOne`，
/// 不会把 78 个字段全序列化一遍（那是拆分前 `patchSettings` 的行为）。
///
/// 通知不在这里发：构造时传 `onChanged`，由 `AppController` 接到
/// `AppChange.settings` 分组。
class SettingsStore {
  SettingsStore({
    required SettingsService service,
    required void Function() onChanged,
  }) : _service = service,
       _onChanged = onChanged;

  final SettingsService _service;
  final void Function() _onChanged;

  AppSettings _value = AppSettings.empty();

  AppSettings get value => _value;

  /// 直接替换（加载、导入、重置用）。**不落盘、不通知** —— 需要落盘的场景
  /// 由调用方紧接着 `persist()`，需要通知的由 [AppController] 决定发哪一组。
  void replace(AppSettings next) => _value = next;

  /// 从存储加载（启动时一次）。
  Future<void> load() async {
    _value = await _service.load();
  }

  /// 全量落盘（导入 / 重置 / 迁移这类场景）。
  Future<void> persist() => _service.save(_value);

  /// 改一个键：先按 patch 规则算出新状态，**只落这一个键**，然后通知设置组。
  Future<void> patch(String key, Object? next) async {
    _value = applySettingsPatch(_value, key, next);
    // 取「改完之后」的值：复合对象（模型列表等）不会写成补丁前的旧值。
    await _service.saveOne(key, _value.toJson()[key]);
    _onChanged();
  }
}
