# 设置区配置驱动迁移

> 目标：设置项由**声明**产生界面、产生搜索索引、产生写入口；页面不再手写
> 分组、字段与落盘逻辑。

## 一、四层结构

| 层 | 文件 | 职责 |
|---|---|---|
| 声明类型 | `lib/pages/settings/spec/settings_spec.dart` | sealed 的 7 种字段 + 分组 + 入口（字段页 / 自定义页）；分组用 [SettingsGroupId] 而不是分组名当身份 |
| 数据 | `spec/settings_tree.dart` + 各页 `*_spec.dart` | 唯一数据源。分组顺序、入口、字段文案、范围、可见性都在这里 |
| 渲染 | `spec/settings_fields_page.dart` | 声明 → 界面。不新造 UI，复用 `SettingSection` / `SettingSwitch` / `Collapsible*` |
| 写通道 | `lib/models/app_settings_patch.dart` + `AppController.patchSettings` | key → 字段的**穷尽 switch**；未声明的 key 当场抛错 |
| 适配 | `settings_catalog.dart` / `settings_search_page.dart` | 主页分组与字段级搜索，都从同一棵树派生 |

## 二、不变量（由测试守）

1. 任何可写设置都必须在声明里有一条，且 `key` 存在于 `AppSettings.toJson()`、
   类型与 `settingsKeyKinds` 一致、运行期类型匹配。
2. 同一个 key 不能被两条声明使用。
3. **反向覆盖**：`toJson` 的每个键都必须归入四类之一 —— 已声明 / 内部状态 /
   动作项托管 / 由手写页面管理。新增字段而不给界面 = 测试红。
   四个桶**互不重叠**（一个 key 只能有一个归属），且「由手写页面管理」的每条
   理由不得少于 10 字 —— 防止把桶当垃圾桶。
4. 数值项 min < max、默认值在范围内、step > 0；枚举项默认值在选项里。
5. 文案长度：字段 title ≤ 12 字、subtitle ≤ 24 字；入口 subtitle ≤ 24 字。
6. 入口 id、字段 id 全局唯一；入口的 `groupId` 必须存在于 `settingsGroups`。
7. `toJson → fromJson` 往返不丢字段（此前 `loreStickyRounds` 存了不读）。

对应测试：`test/settings_spec_test.dart`（规格）、`test/settings_patch_test.dart`（写通道）、
`test/settings_structure_test.dart`（导航结构）、`test/settings_design_test.dart`（信息设计）。

## 三、进度

* 声明驱动的字段页：**10 个**（安全与隐私、外观与聊天界面、回复与发送、
  剧情摘要与上下文、消息与高级、语音合成、语音输入、采样参数、自由剪图、检查更新）。
* key 归属：**待迁移桶已删除**。82 个键现在的分布是：已声明 60 / 内部状态 11 /
  动作项托管 3 / 由手写页面管理 11（每条附理由）。
* 渲染器已支持 `SettingDouble` 的折叠编辑（`CollapsibleDoubleSetting`），
  双精度不再只能渲染成常驻滑杆。
* 字段标题硬线 26 字（推荐 12）：采样参数名带英文术语，砍短会对不上号。
* **搜索覆盖**：索引同时遍历 `settingsTree` 与 `settingsDetachedEntries`，
  采样参数/自由剪图/检查更新虽然不在设置主页，搜「温度」「剪图」也能直达。
* 仍手写：AI 服务与模型（服务商/模型 CRUD）、提示词策略（按角色继承/覆盖编辑器）、
  备份与还原（动作页）、社区服务器、赞助、关于、开发者选项。

## 四、动作项托管的 key（`settingsActionManagedKeys`）

这三条没有标量声明，由 `SettingAction` 里的自绘控件写入。每一条都要能说清
「为什么标量声明表达不了」：

| key | 原因 |
|---|---|
| `ttsGlobalSeed` | 可空整数：null = 恢复默认种子，与 0 是两种音色；`SettingInt` 只能写 int |
| `customAccentColor` | 可空 ARGB：切回「自动取色」要真清空，`copyWith` 的 `??` 语义表达不了 |
| `sherpaCustomBaseUrl` | 文本：输入即写且要 trim，声明层还没有文本项 |

等声明层补上「可空数值项」「文本项」之后，这个桶应该缩到空。

## 五、行为对齐情况

### 已补齐（迁移后曾经丢过，已修）

1. **TTS 开关的就绪门槛 + 自愈**。旧页面在 init 与每次 controller 变化时探测
   `TtsService.instance.isModelsReady()`，模型没就绪就置灰开关、并把
   `ttsEnabled` 写回 false。现在由 `FieldsEntry.resolveRuntime` 钩子在进入页面
   时探测一次并做同样的校正（见 `tts_settings_spec.dart` 的 `_resolveTtsRuntime`），
   置灰用 `enabledWhen: (r) => r.ttsModelsReady != false` 表达。
   `ttsModelsReady == null`（未探测）**不置灰** —— 「不知道」不能等于「不可用」。
2. **下载中禁止切换**。旧页面在下载期间禁掉「识别模型」「下载源」。现在
   `lib/services/model_download_state.dart` 是唯一写入入口（计数，begin/end 成对），
   宿主页监听它并把 `modelDownloading` 放进 `SettingsRuntime`，两个选项用
   `enabledWhen: (r) => !r.modelDownloading` 置灰。
3. **行内短说明**。`showParenButton` / `inspirationIncludeSummary` /
   `retrySequential` 旧版是 `SettingSwitch.description`（开关右侧同一行）。
   声明层补了 `SettingToggle.inlineNote`，三条已改回行内，不再多占一行。
4. **Beta 徽标**。`SettingSectionSpec` 补了 `trailing`，TTS「语音朗读」与
   语音输入「离线语音识别」两张卡重新挂上 `BetaTag`。
5. **两态副标题**。TTS 开关（就绪 / 未就绪）与语音输入开关的副标题旧版随状态
   切换。声明层补了 `SettingItemSpec.subtitleOf(SettingsRuntime)`，两者已恢复
   两态；TTS 的来源是运行态 `ttsModelsReady`，语音输入的来源是
   `sherpaModelReady` + `sherpaModelPath`（都在 AppSettings 里）。

### 仍是差异（文案级，不是行为）

| 差异 | 说明 |
|---|---|
| 两处动态副标题 → 静态 | 自由剪图、检查更新的副标题旧版随取值切换。这两处是「说明型」不是「状态型」，静态化 + 常驻 hint 可接受，暂不改 |
| TTS 页标题 | 现在用入口标题「语音合成与背景音乐」，旧页是「端侧语音合成」；「端侧 = 离线不上传」的卖点可在分组说明里补 |
| 步进器写盘次数 | 数值项由「每动一格写一次」变成「松手写一次」（最终值相同，写得更少），属于改进 |

## 六、再迁一页的操作步骤

1. 新建 `lib/pages/settings/<页面>_settings_spec.dart`，导出
   `final FieldsEntry xxxEntry`（照 `security_settings_spec.dart` 的形状）。
   **只新增，不改树、不改测试、不删旧页。**
2. 把 `settings_tree.dart` 里对应的 `CustomEntry` 换成该符号。
3. 旧页面若只被 `settings_tree` 引用 → 直接删除；
   若被别处引用（命令入口、测试 pump）→ 改写成 10 行兼容壳
   （见 `appearance_display_page.dart`）。
4. 从 `test/settings_spec_test.dart` 的 `settingsKeysPendingMigration` 删掉对应 key。
5. 入口不在设置主页的页面（开发者选项里的），登记到 `settingsDetachedEntries`。
6. `flutter analyze lib test` + `flutter test --no-pub --exclude-tags live`。

## 七、待办（都不是本次目标的一部分）

1. 补「可空数值项」「文本项」两种声明类型，把动作项托管的 3 个 key 收进声明
   （`ttsGlobalSeed` / `customAccentColor` / `sherpaCustomBaseUrl`）。
2. 若将来要动 AI 服务页：它现在是「表单 + 异步探测 + 3 tab 分栏」的复合页面，
   要声明化得先把它拆成「连接表单（自定义）」+「其余字段（声明）」两块。
3. 第五节的四条文案级差异，属于「要不要给 `SettingSectionSpec` 加 trailing /
   给 `FieldsEntry` 加 pageTitle」的取舍，不是行为问题。

## 八、剩余手写页面为什么手写（`settingsCustomPageKeys` 的依据）

| 入口 | 为什么不是字段页 |
|---|---|
| AI 服务与模型 | 服务商选择 + Base URL/API Key 表单 + 模型列表拉取 + 连接测试；`saveProvider`/`saveSelectedModel` 还会同步 `providers`/`models` |
| 提示词策略 | 按角色继承/覆盖的编辑器（数量、档位、覆盖态） |
| 备份与还原 | 文件 IO + 平台分支（Web/Android/桌面）的动作页 |
| 社区服务器 / 赞助 | 服务器地址表单 / 展示页 |
| 关于 / 开发者选项 | 信息页 / 命令控制台 |
| AI 服务 ⋮ 分栏页 | 3 个 tab（界面模式 / 生成参数 / 网络），其中两 tab 是服务商与模型的 CRUD 列表 |
| 应用图标 | 网格选择器 + 平台能力判断 |
