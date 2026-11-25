/// 设置目录：设置主页与搜索页读的那份数据的**适配层**。
///
/// 数据的真相在 `spec/settings_tree.dart`（一处声明，三处消费：
/// 主页分组、搜索索引、页面字段渲染）。本文件只把它包装成设置主页需要的
/// 形状，不再自己维护一份入口清单。
///
/// 历史：这里曾经是唯一数据源，且索引粒度只到「入口页」——用户搜「开场动画」
/// 搜不到，因为那是「外观与聊天界面」里的一个开关。那个边界的成因和这次
/// 结构性重构的目标，见 `spec/settings_spec.dart` 的文件头。
library;

import 'package:material_ui/material_ui.dart';

import '../../services/auth_service.dart';
import '../../state/app_controller.dart';
import '../../utils/platform_capabilities.dart';
import 'spec/settings_fields_page.dart';
import 'spec/settings_spec.dart';
import 'spec/settings_tree.dart';

/// 一个设置入口（供设置主页渲染）。
class SettingsEntry {
  SettingsEntry(this.spec, this._controller);

  final SettingsEntrySpec spec;
  final AppController _controller;

  IconData? get icon => spec.icon;

  String get title => spec.title;

  String get subtitle => spec.subtitle;

  /// 平台能力不满足时入口仍然显示（置灰），但不参与搜索。
  bool get enabled => settingsGateOpen(spec.gate);

  /// 该入口对应的页面。
  Widget page() => buildSettingsEntryPage(spec, _controller);
}

/// 一个设置分组：标题 + 一张卡片里的若干入口。
class SettingsGroup {
  const SettingsGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.entries,
  });

  /// 稳定标识（分组名会翻译，id 不会）。
  final SettingsGroupId id;

  final String title;

  final IconData icon;

  final List<SettingsEntry> entries;
}

/// 当前可见的设置分组，顺序由 [settingsGroups] 决定。
///
/// 分组按 [SettingsGroupId] 归并（不是按分组名）：分组名只是显示文案，
/// 本地化之后仍然对得上号。
List<SettingsGroup> settingsCatalog(AppController controller) {
  final SettingsRuntime runtime = SettingsRuntime(
    settings: controller.settings,
  );
  final Map<SettingsGroupId, List<SettingsEntry>> byGroup =
      <SettingsGroupId, List<SettingsEntry>>{};
  for (final SettingsEntrySpec spec in settingsTree) {
    if (spec.visibleWhen != null && !spec.visibleWhen!(runtime)) continue;
    byGroup
        .putIfAbsent(spec.groupId, () => <SettingsEntry>[])
        .add(SettingsEntry(spec, controller));
  }
  final List<SettingsGroup> groups = <SettingsGroup>[];
  for (final SettingsGroupSpec group in settingsGroups) {
    final List<SettingsEntry>? entries = byGroup[group.id];
    if (entries == null || entries.isEmpty) continue;
    groups.add(
      SettingsGroup(
        id: group.id,
        title: group.title,
        icon: group.icon,
        entries: entries,
      ),
    );
  }
  return groups;
}

/// 把一条入口声明变成页面。
///
/// [focusItemId] 只在字段页有意义：从搜索跳进来时，命中的那一条会展开并
/// 滚到可见位置。
Widget buildSettingsEntryPage(
  SettingsEntrySpec spec,
  AppController controller, {
  String? focusItemId,
}) {
  switch (spec) {
    case FieldsEntry entry:
      return _FieldsEntryHost(
        entry: entry,
        controller: controller,
        focusItemId: focusItemId,
      );
    case CustomEntry entry:
      return entry.builder(controller);
  }
}

/// 字段页宿主：负责在进入页面前解析一次异步能力（生物识别是否真的可用）。
///
/// 为什么放在这里而不是渲染器里：渲染器要保持纯同步（声明 → 控件），
/// 异步能力探测属于「宿主职责」。等探测有结果后再渲染，避免用户先看到
/// 一组隐藏的开关、再突然出现。
class _FieldsEntryHost extends StatefulWidget {
  const _FieldsEntryHost({
    required this.entry,
    required this.controller,
    this.focusItemId,
  });

  final FieldsEntry entry;
  final AppController controller;
  final String? focusItemId;

  @override
  State<_FieldsEntryHost> createState() => _FieldsEntryHostState();
}

class _FieldsEntryHostState extends State<_FieldsEntryHost> {
  bool _biometricEnrolled = false;
  bool? _ttsModelsReady;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolveRuntime();
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 解析一次运行态：先补齐宿主自己知道的能力，再交给声明里的钩子。
  Future<void> _resolveRuntime() async {
    bool enrolled = false;
    if (PlatformCapabilities.biometricAuthSupported) {
      enrolled = await AuthService.canCheckBiometrics();
    }
    SettingsRuntime base = SettingsRuntime(
      settings: widget.controller.settings,
      biometricEnrolled: enrolled,
    );
    final SettingsRuntimeResolver? resolver = widget.entry.resolveRuntime;
    if (resolver != null) {
      base = await resolver(widget.controller, base);
    }
    if (!mounted) return;
    setState(() {
      _biometricEnrolled = base.biometricEnrolled;
      _ttsModelsReady = base.ttsModelsReady;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 探测未完成时先按平台能力给一个乐观初值（支持就用 true），
    // 避免受支持设备上先闪一下「不可用」提示。
    final bool enrolled = _resolved
        ? _biometricEnrolled
        : PlatformCapabilities.biometricAuthSupported;
    return SettingsFieldsPage(
      entry: widget.entry,
      controller: widget.controller,
      biometricEnrolled: enrolled,
      ttsModelsReady: _ttsModelsReady,
      focusItemId: widget.focusItemId,
    );
  }
}
