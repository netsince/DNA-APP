/// 设置项的声明类型（配置驱动设置页的地基）。
///
/// ## 不变量
///
/// **任何可写设置都必须在设置树里有一条声明**，页面不再直接读写
/// `controller.settings`。声明的 key 必须是 `AppSettings.toJson()` 的键，
/// 类型必须与 `settingsKeyKinds` 一致 —— 两者都被
/// `test/settings_spec_test.dart` 逐条对账。
///
/// ## 为什么是 sealed 而不是「一个类 + type 枚举 + 一堆可空字段」
///
/// 后者允许「开关带着 min/max」「枚举没有 options」这类非法状态存在，
/// 渲染器每处都得再 if 一遍。sealed 让渲染器的 switch 是穷尽的：以后新增
/// 一种字段类型，所有未处理的地方**编译期报错**。
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/app_settings.dart';
import '../../../state/app_controller.dart';

/// 渲染时可见的「设置 + 运行态」快照。
///
/// 为什么不只是 AppSettings：有些可用性判断需要异步能力探测（例如
/// 设备是否已录入指纹），那不是持久化状态，不该塞进 AppSettings。
/// 由页面在渲染前解析一次，随声明谓词一起传下去。
class SettingsRuntime {
  const SettingsRuntime({
    required this.settings,
    this.biometricEnrolled = false,
    this.ttsModelsReady,
  });

  final AppSettings settings;

  /// 设备是否真的能完成生物识别（平台支持 + 已录入）。
  final bool biometricEnrolled;

  /// 端侧语音模型是否已就绪。
  ///
  /// null = 还没探测 / 该页面不关心。**不要**用 false 表示未知：那里
  /// [false] 是「确实没就绪」，会让依赖它的开关被置灰。
  final bool? ttsModelsReady;

  /// 是否有端侧模型正在下载（见 `ModelDownloads`）。
  ///
  /// 为 true 时，依赖「下载目标」的选项要置灰：中途换模型/换源会让完成后的
  /// 就绪标记与当前选择对不上。
}

/// 进入页面时解析一次运行态（异步能力探测 + 必要的一次性校正）。
///
/// 输入是宿主已解析好的基础运行态（含 biometricEnrolled），返回补全后的。
/// 之所以是「一次性」而不是每次 build 都跑：探测要读文件/查平台，
/// 放进 build 会变成每帧一次 IO。
typedef SettingsRuntimeResolver = Future<SettingsRuntime> Function(
  AppController controller,
  SettingsRuntime base,
);

/// 设置分组的**稳定标识**。
///
/// 它是身份，不是文案：分组名会随语言变，id 永远不变。分组顺序、图标、标题
/// 全部从 [SettingsGroupSpec] 派生，任何地方都不许再用中文字符串当 key
/// （那会在本地化时静默失配）。
enum SettingsGroupId {
  ai,
  dialogue,
  memory,
  voice,
  appearance,
  dataSecurity,
  community,
  about,
}

/// 一个分组的外观与文案。
///
/// 本地化时只改这里的 [title]，分组顺序与图标都不动。
class SettingsGroupSpec {
  const SettingsGroupSpec({
    required this.id,
    required this.title,
    required this.icon,
  });

  final SettingsGroupId id;

  /// 显示文案（会翻译）。
  final String title;

  final IconData icon;
}

/// 设置项的可用性门槛（由平台能力决定）。
enum SettingsGate { always, tts, biometric }

/// 值的写入时机。
///
/// 现在三种写法混用（开关一拨即存、滑杆拖动每帧存、文本框回车才存），
/// 不写进声明的话，迁移后交互会悄悄变。
enum SettingsSaveMode {
  /// 每次变化立刻落盘。
  immediate,

  /// 拖动结束（或点击提交）才落盘。
  onRelease,

  /// 按下回车/失焦才落盘。
  onSubmit,
}

/// 枚举项用哪种控件呈现。
enum ChoiceLayout {
  /// 2-3 个选项：分段按钮（可带图标）。
  segmented,

  /// 4 个以上选项，每项需要一句说明：单选行。
  radioList,

  /// 选项很多、不需要说明：下拉菜单。
  dropdown,
}

/// 数值项用哪种控件呈现。
enum NumberEditor {
  /// 收起态只显示「名称 + 当前值」，展开后是步进器。
  collapsibleStepper,

  /// 常驻滑杆（需要即时预览，如字号档、气泡透明度）。
  slider,

  /// 大范围数值，走文本输入。
  textField,
}

/// 枚举项的一个选项。
class ChoiceOption<T> {
  const ChoiceOption({
    required this.value,
    required this.label,
    this.icon,
    this.subtitle,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// 单选行模式下的补充说明（一行）。
  final String? subtitle;
}

/// 一条设置项的公共部分：标识、文案、可见性。
sealed class SettingItemSpec {
  const SettingItemSpec({
    required this.id,
    required this.title,
    this.subtitle,
    this.hint,
    this.searchable = true,
    this.showTitle = true,
    this.subtitleOf,
    this.visibleWhen,
    this.enabledWhen,
    this.gate = SettingsGate.always,
  });

  /// 稳定标识（`分组.字段`），搜索定位、测试断言、埋点都用它。
  final String id;

  /// 字段标题（建议 ≤ 8 字）。
  final String title;

  /// 一句话价值（建议 ≤ 20 字），单行。
  final String? subtitle;

  /// 更长的补充说明（收起态不显示，展开后才看到）。
  final String? hint;

  /// 是否参与搜索。提示行、纯装饰性动作项应为 false。
  final bool searchable;

  /// 随运行态变化的副标题。
  ///
  /// 旧页面里有几处副标题是「状态指示」——模型就绪 / 未就绪各一句
  /// （TTS、语音输入）。声明里的 [subtitle] 是常量，表达不了这种两态，
  /// 所以给一个可选钩子；返回非 null 时优先于 [subtitle]。
  final String Function(SettingsRuntime runtime)? subtitleOf;

  /// 是否把 [title] 画在控件上方。
  ///
  /// 有些分段控件紧跟在分组标题下面（旧页面就是这么排的），此时再画一遍
  /// 字段标题只会重复。true = 正常画，false = 只当检索/无障碍用的元数据。
  final bool showTitle;

  /// 整项是否出现（不满足时**不渲染**）。
  final bool Function(SettingsRuntime runtime)? visibleWhen;

  /// 整项是否可用（不满足时渲染但置灰）。
  final bool Function(SettingsRuntime runtime)? enabledWhen;

  /// 平台能力门槛。
  final SettingsGate gate;

  /// 参与搜索的文本片段。
  ///
  /// **不设 aliases**：标签本身就是最全的检索面（标题 + 副标题 + 补充 + 选项
  /// 文案 + 分组名 + 稳定 id）。再挂一份手写别名就是第二份真相 —— 改文案时
  /// 没人会同步它，翻译时还要再翻一遍。真出现「按用户说法搜不到」的具体案例，
  /// 再针对那一条加测试和入口，而不是现在预留一堆猜测。
  List<String> get searchTerms => <String>[title, ?subtitle, ?hint];
}

/// 带值的设置项：有 `key`，可读写。
sealed class SettingValueItem<T> extends SettingItemSpec {
  const SettingValueItem({
    required super.id,
    required super.title,
    super.subtitle,
    super.subtitleOf,
    super.hint,
    super.searchable,
    super.showTitle,
    super.visibleWhen,
    super.enabledWhen,
    super.gate,
    required this.key,
    required this.defaultValue,
    this.saveMode = SettingsSaveMode.immediate,
    this.writeOverride,
  });

  /// `AppSettings.toJson()` 的键，**唯一真相**。
  final String key;

  /// 声明层面的默认值；用于校验「树里声明了这个 key」与「它真的能读出来」。
  final T defaultValue;

  final SettingsSaveMode saveMode;

  /// 需要副作用（重建主题、初始化引擎、切换模型…）时挂这里；
  /// 正常情况下为 null，写通道自动处理。
  final Future<void> Function(AppController controller, T value)? writeOverride;
}

/// 开关。
class SettingToggle extends SettingValueItem<bool> {
  const SettingToggle({
    required super.id,
    required super.title,
    super.subtitle,
    super.subtitleOf,
    super.hint,
    super.searchable,
    super.showTitle,
    super.visibleWhen,
    super.enabledWhen,
    super.gate,
    required super.key,
    super.defaultValue = false,
    super.saveMode,
    super.writeOverride,
    this.inlineNote,
  });

  /// 行内短说明（≤ 10 字），右对齐到开关左侧的同一行。
  ///
  /// 与 [SettingItemSpec.hint] 的区别：hint 另起一行，适合一句话；这里不占额外
  /// 行高，只放「仅本条」「不推荐」这类极短限定。
  final String? inlineNote;
}

/// 互斥枚举。
class SettingChoice<T> extends SettingValueItem<T> {
  const SettingChoice({
    required super.id,
    required super.title,
    super.subtitle,
    super.subtitleOf,
    super.hint,
    super.searchable,
    super.showTitle,
    super.visibleWhen,
    super.enabledWhen,
    super.gate,
    required super.key,
    required super.defaultValue,
    required this.options,
    this.layout = ChoiceLayout.segmented,
    super.saveMode,
    super.writeOverride,
  });

  final List<ChoiceOption<T>> options;
  final ChoiceLayout layout;

  @override
  List<String> get searchTerms => <String>[
    ...super.searchTerms,
    for (final ChoiceOption<T> o in options) o.label,
    for (final ChoiceOption<T> o in options) ?o.subtitle,
  ];
}

/// 数值项公共部分。
sealed class SettingNumber<T extends num> extends SettingValueItem<T> {
  const SettingNumber({
    required super.id,
    required super.title,
    super.subtitle,
    super.subtitleOf,
    super.hint,
    super.searchable,
    super.showTitle,
    super.visibleWhen,
    super.enabledWhen,
    super.gate,
    required super.key,
    required super.defaultValue,
    required this.min,
    required this.max,
    required this.step,
    this.unit,
    this.zeroLabel,
    this.labelOf,
    this.editor = NumberEditor.collapsibleStepper,
    super.saveMode,
    super.writeOverride,
  });

  final T min;
  final T max;
  final T step;

  /// 数值 → 显示文案。为 null 时按「数值 + 单位」显示。
  ///
  /// 用于语义化档位（字号档 0..5 显示成「跟随系统 / 小 / 标准 / 大 …」），
  /// 否则界面上只能看到裸数字。
  final String Function(T value)? labelOf;

  /// 单位（轮 / 条 / Token / 字）。拼在数值后面。
  final String? unit;

  /// 值为 0 时显示的文字（「不限」「不持续」）。
  final String? zeroLabel;

  final NumberEditor editor;
}

/// 整数数值项。
class SettingInt extends SettingNumber<int> {
  const SettingInt({
    required super.id,
    required super.title,
    super.subtitle,
    super.subtitleOf,
    super.hint,
    super.searchable,
    super.showTitle,
    super.visibleWhen,
    super.enabledWhen,
    super.gate,
    required super.key,
    required super.defaultValue,
    required super.min,
    required super.max,
    super.step = 1,
    super.unit,
    super.zeroLabel,
    super.labelOf,
    super.editor,
    super.saveMode,
    super.writeOverride,
  });
}

/// 浮点数值项。
class SettingDouble extends SettingNumber<double> {
  const SettingDouble({
    required super.id,
    required super.title,
    super.subtitle,
    super.subtitleOf,
    super.hint,
    super.searchable,
    super.showTitle,
    super.visibleWhen,
    super.enabledWhen,
    super.gate,
    required super.key,
    required super.defaultValue,
    required super.min,
    required super.max,
    super.step = 0.1,
    super.unit,
    super.zeroLabel,
    super.labelOf,
    super.editor,
    super.saveMode,
    super.writeOverride,
    this.decimals = 2,
  });

  /// 折叠态与气泡里显示的小数位。0 = 整数显示（如 Top-K）。
  final int decimals;
}

/// 动作项（按钮：备份、恢复、检查更新、下载模型）。没有 key —— 它不改设置值。
class SettingAction extends SettingItemSpec {
  const SettingAction({
    required super.id,
    required super.title,
    super.subtitle,
    super.subtitleOf,
    super.hint,
    super.searchable,
    super.showTitle,
    super.visibleWhen,
    super.enabledWhen,
    super.gate,
    required this.builder,
  });

  final Widget Function(BuildContext context, AppController controller) builder;
}

/// 只读展示项（当前模型、缓存占用、版本号）。不可写，但可被搜索到。
class SettingInfo extends SettingItemSpec {
  const SettingInfo({
    required super.id,
    required super.title,
    super.subtitle,
    super.subtitleOf,
    super.hint,
    super.searchable,
    super.showTitle,
    super.visibleWhen,
    super.enabledWhen,
    super.gate,
    required this.read,
  });

  final String Function(AppSettings settings) read;
}

/// 页面内的一个分组（对应 `SettingSection`）。
class SettingSectionSpec {
  const SettingSectionSpec({
    required this.id,
    required this.title,
    this.icon,
    this.description,
    this.trailing,
    this.items = const <SettingItemSpec>[],
  });

  final String id;

  /// 分组标题（建议 ≤ 6 字）。
  final String title;

  final IconData? icon;

  /// 一句话说明（≤ 20 字）。
  final String? description;

  /// 分组标题右侧的附加标记（如 Beta 徽标）。
  final Widget? trailing;

  final List<SettingItemSpec> items;
}

/// 设置目录里的一个入口 = 一个页面。
sealed class SettingsEntrySpec {
  const SettingsEntrySpec({
    required this.id,
    required this.groupId,
    required this.title,
    required this.subtitle,
    this.icon,
    this.visibleWhen,
    this.gate = SettingsGate.always,
  });

  /// 入口标识（稳定，不翻译）。
  final String id;

  /// 所属分组（稳定标识；分组名与图标见 [SettingsGroupSpec]）。
  final SettingsGroupId groupId;

  /// 入口标题。
  final String title;

  /// 入口副标题（单行，≤ 20 字）。
  final String subtitle;

  /// 入口图标（列表项 leading）。
  final IconData? icon;

  /// 整条入口何时出现。
  final bool Function(SettingsRuntime runtime)? visibleWhen;

  final SettingsGate gate;
}

/// 由字段树生成的页面。
class FieldsEntry extends SettingsEntrySpec {
  const FieldsEntry({
    required super.id,
    required super.groupId,
    required super.title,
    required super.subtitle,
    super.icon,
    super.visibleWhen,
    super.gate,
    required this.sections,
    this.resolveRuntime,
  });

  final List<SettingSectionSpec> sections;

  /// 进入页面时解析一次运行态；为 null 时用宿主给的默认值。
  ///
  /// 典型用法：TTS 页在这里探测「端侧模型是否已就绪」，并顺手把
  /// 「模型没了但开关还开着」的脏状态写回去（旧页面 _refresh 的行为）。
  final SettingsRuntimeResolver? resolveRuntime;
}

/// 保留手写页面的入口（编辑器、动作页、信息页）。
class CustomEntry extends SettingsEntrySpec {
  const CustomEntry({
    required super.id,
    required super.groupId,
    required super.title,
    required super.subtitle,
    super.icon,
    super.visibleWhen,
    super.gate,
    required this.builder,
  });

  final Widget Function(AppController controller) builder;
}
