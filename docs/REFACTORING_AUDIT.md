# dna-client 重构审计（2026-11-23）

审计范围：`lib/` 全部 475 个 dart 文件、111,741 行；顺带核对了 `test/` 的覆盖情况。
审计方式：只读。四个域并行实读 + 全量 grep 计数。**lib/ 零改动，无提交**。
所有行号均为审计时的实际行号，证据路径可直接跳转核对。

---

## 0. 一句话结论

**这个仓库不缺抽象，缺的是「把调用点接到已有的唯一实现上」。**

上一轮重构（代码注释里标为「2026-11 审计」）已经建好了七套共享件：三态视图、分页状态机、五态骨架、SnackBar 唯一入口、应用内动作表、设置 spec 体系、单源守卫测试。本轮找到的重复，**六成以上是「抽象建好之后，调用点没接上去」**，而不是「应该再抽一层」。

所以本文的判据是硬的：**每条必须给出 N 处 → 1 处的 N**。给不出 N 的，一律进第 6 节「不建议做的事」。

**总量**：可消掉的手抄副本约 **500 处**，各域自报合计见下；净删估计 **1800~2200 行**。

| 域 | 发现 | P0 | 可消副本 |
|---|---|---|---|
| island_app 社区端 | 9 | 2 | 304 处 |
| chat 聊天链路 | 11 | 2 | ≈230 处 + 388 行闭包 |
| settings 与表单 | 8 | 3 | ≈70 处 |
| state 与服务层 | 11 | 4 | 字段表 9→1、导入 3→1、死 setter 41→0、prefs 20→1 |

---

## 1. 先看这张表：已有唯一入口，被绕过多少处

这是全仓库性价比最高的一批改动——**全部是纯替换，不新建任何抽象**。每一行都是「工具已经存在，把调用点接上去」。

| 已有唯一入口 | 位置 | 应有多少处 | 实际绕过 | 典型绕过点 |
|---|---|---|---|---|
| `showSnack` | `lib/utils/ui_feedback.dart:23` | 174 处在用 | **64 处 / 43 文件**裸 `ScaffoldMessenger.of`，其中 island_app 占 37 处（含同一文件内两份副本 `tickets_page.dart:407`、`:660`） | 15 个私有 `_snack` helper 各自重写 |
| `AppEmptyState` / `AppErrorState` / `AppLoadingState` | `lib/widgets/state_views.dart:20/78/111` | 40/27/18 处引用（含定义与 re-export） | **19 处**空态 `Center(child: Text)`、**6 处**手拼错误态、**40 处** `Center(child: CircularProgressIndicator())`（21 文件） | `card_detail_page.dart:2085-2145` 整个 `_ErrorBody` 类；`me_page.dart` 一个文件 11 处裸 spinner，其中 `:992/1099/1167/1224/1410` 是五态首屏守卫 |
| `PagedListBody` / `PagedGridBody` | `lib/widgets/paged_list_body.dart:18/63` | 4 处在用 | **11 处**手抄「五态+触底+尾条」，**7 处**手写 `NotificationListener` 触底 | `tickets_page.dart:122-179`、`me_page.dart:1222-1257` |
| `AttachmentIntake` | `lib/services/attachment_intake.dart:42` | 主程序已在用 | **21 处**（7 份 `_mimeOf` + 6 份 `_pickImage` + 8 处 base64 dataURL 拼接），island_app 引用次数 **0** | `tickets_page.dart:335-376` 与 `:567-608` 同文件两份逐字节相同 |
| `PostLikeFavMixin` | `lib/island_app/utils/post_like_fav.dart:12` | 1 处在用 | **10 处**内联「登录守卫+API+回写+Snack」 | `teahouse_body.dart:397-430`（隔壁类）、`search_page.dart:386-424` |
| `RowAction` 动作表 | `lib/utils/action_table.dart:53-89` | `chat_app_bar.dart:166-235` 已证可行 | `chat_ui_helpers.dart:55-77 / 97-112 / 145-217` **三种写法**并存 | 14 行手写 `PopupMenuItem` |
| `SubmitFormState` / `FormSubmitButton` | `lib/widgets/submit_form.dart:14-84` | island 4 页在用 | `ta_editor_page` 与 `world_editor_page` 两个编辑器都绕开，各写一套保存按钮 | world 那份还缺忙态与 try/catch |
| `SettingSection` 分组头 | `lib/widgets/setting_section.dart:38-138` | 23 处在用 | **11+ 处**手写同形分组头 | `conversation_prompt_strategy_page.dart` 六张卡全手写；`world_editor_form.dart:248` 注释自认「做法同 setting_section」 |
| `FormHandle` 脏标记（尚不存在） | — | — | **3 份**同构实现 | `world_editor_form.dart:23-48`、`ta_editor_form.dart:33-81`、`dialogue_style_form.dart:11-46` |
| `SharedPrefs` 缓存单例 | `lib/island_app/shared_prefs.dart:9-33` | 4 个 island 文件在用 | **20 个**裸 `SharedPreferences.getInstance()` / 9 文件 | 三套访问方式并存 |
| `relativeTime` | `lib/island_app/utils/time_format.dart:2-13` | 8 处在用 | **1 份逐字节副本** `comment_section.dart:939-950` | |
| `copyToClipboard`（导出服务内） | `identity_export_import_service.dart:71` | — | **3 份逐字相同** | `ta_export_import_service.dart:312`、`world_export_import_service.dart:142` |
| `describeError` | `lib/utils/error_display.dart:12` | 57 处在用 | 全库仍有 **96 处** `'XX失败：$e'` 直接把原始异常拼给用户 | |
| 数字缩写 | 归口文件不存在 | — | **4 份**（`card_detail_page.dart:1183` 与 `:1391` 同文件两份） | |

**这批做完，代码行数几乎不减，但「同一个东西有 N 份真相」会一次性消失。**

---

## 2. 上帝文件排行（按危害，不按行数）

行数只说明它大，「危害」看它里面**装了几个不相干的领域**。排序依据：职责数 × 复用广度 × 无测试。

| 排名 | 文件 | 行数 | 里面装了什么 | 判 |
|---|---|---|---|---|
| 1 | `lib/state/app_controller.dart` | 2258 | **7 个领域**（设置/LLM 配置/角色/身份/世界/会话/备份）× 129 方法 × 99 个 notifyListeners，78 个 UI 文件当万能句柄 | 必须拆成 5 个 |
| 2 | `lib/island_app/api/client.dart` | 2300 | 1 个类 94 个接口方法 × 16 个资源域；服务器地址守卫手抄 75 处、解包校验 50 处、键转换 37 处 | 必须按资源拆 |
| 3 | `lib/pages/chat/chat_surface.dart` | 1419 | 单 `build` 480 行（背景立绘+内容列+Scaffold 装配+沉浸退出球+输入中条），`_showMemberPicker` 205 行内联一个搜索多选 sheet | 抽 3 组件 + 1 sheet |
| 4 | `lib/island_app/card_detail_page.dart` | 2197 | 20 个类写在一个文件；私有 `_ErrorBody`/`_SkeletonBody` 与共享三态平行 | 拆文件不消重复，只搭车 |
| 5 | `lib/pages/chat/ui/widgets/chat_message_list.dart` | 1139 | 单 itemBuilder 388 行，3 个 kind 分支各手抄一遍手势接线与卡片外壳 | 按 kind 拆 3 个气泡 |
| 6 | `lib/island_app/me_page.dart` | 1591 | 一个文件两个 State 类，5 份五态接线 | 接 PagedListBody |
| 7 | `lib/pages/settings/prompt_strategy_advanced_page.dart` | 893 | 私有 `_enumRow`/`_TriSwitchRow`/`_LevelRow` 与 `strategy_field_rows.dart` 逐字重复，另 10 个手写 TextField | 13 处 → 3 |
| 8 | `lib/pages/chat/ui/chat_ui_helpers.dart` | 896 | 杂物抽屉：菜单 + 177 行候选弹框 + 消息编辑回溯 + 收焦滚动善后，四类职责一个 mixin | 搬走两块 |
| 9 | `lib/pages/world_editor/world_editor_form.dart` | 1141 | 表单三件套之一；分组头手写、脏句柄自制 | 接 FormHandle |
| 10 | `lib/services/storage_usage_service.dart` | 989 | 服务在做 UI 文案（约 20 条中文串），页面在做统计（三层遍历写两遍） | 职责互换 |
| 11 | `lib/pages/oobe/oobe_steps.dart` | 983 | 5 个类簇集合，切文件边界干净，但四步骨架抄了 4 份 | 抽 OobeStepScaffold |
| 12 | `lib/island_app/widgets/comment_section.dart` | 1005 | 自带时间格式化副本、手写空态错误态 | 接共享件 |
| 13 | `lib/pages/ta_editor/ta_editor_form.dart` | 854 | 回填逻辑写两遍；必填星号是装饰（`_save` 零校验） | 去重 + 补校验 |
| 14 | `lib/widgets/setting_collapsible.dart` | 738 | 折叠行抄 4 遍、折叠体抄 4 遍（第 5、6 份在别处） | 6 → 2 个构件 |

### 2.1 可单独提取成组件的清单（按页面，全部有行号）

「能拆」不算理由，这张表里每条都满足至少一条：**① 同一段 UI 已存在 2 份以上；② 它在一个 300 行以上的方法/闭包里，改它要在大文件里定位。**

| # | 从哪里提 | 提什么 | 证据 | 提到哪里 | 消掉 |
|---|---|---|---|---|---|
| 1 | `chat_surface.dart` | 聊天背景立绘 + 蒙层渐变 | `:1089-1156`（在 480 行 build 里） | `chat/ui/widgets/chat_background.dart` | 1 份 |
| 2 | `chat_surface.dart` | 沉浸态退出球 | `:1057-1084` | `chat/ui/widgets/immersive_exit_button.dart` | 1 份 |
| 3 | `chat_surface.dart` | 「对方正在输入」条 | `:978-998` | `chat/ui/widgets/typing_indicator.dart` | 1 份 |
| 4 | `chat_surface.dart` | 添加群成员 sheet（205 行内联） | `_showMemberPicker` `:381-585` | `chat/ui/widgets/group_member_picker_sheet.dart` | 1 份 |
| 5 | `chat_surface.dart` | 群聊播报条（113 行） | `_buildSpeakerBar` `:630-742` | `chat/ui/widgets/speaker_bar.dart` | 1 份 |
| 6 | `chat_message_list.dart` | 三个气泡 + 手势接线 | itemBuilder `:142-529`（388 行）；手势逐字 3 份 `:160-173`/`:224-237`/`:307-320`；卡片外壳 2 份 `:174-182`/`:238-246` | `chat/ui/widgets/message_bubbles.dart`（`_SummaryPromptBubble`/`_SummaryBubble`/`_ChatBubble`/`_MessageGesture`） | 手势 3→1、外壳 2→1 |
| 7 | `chat_message_list.dart` | 高亮文本排布（207 行 5 层闭包） | `_buildHighlightedText` `:845-1051` | `utils/novel_text_spans.dart`（**仅搬迁，无第二调用点**，排最后做） | 1 份 |
| 8 | `chat_ui_helpers.dart` + `chat_actions_inspiration.dart` | 候选弹框（两处各 177/218 行，约 150 行同构） | `helpers:334-510` vs `inspiration:118-335`；`RetryOptionCard`(`:798-895`)、`_RetryOriginalCard`(`:749-794`) 也该一起搬 | `chat/ui/widgets/candidate_picker_sheet.dart` | 2 套 → 1 套 |
| 9 | `chat_ui_helpers.dart` | 菜单后收焦 + 滚动善后 | `:731-745` | `ChatController` | 2→1（与 `chat_state_mixin.dart:180-187`） |
| 10 | `prompt_strategy_advanced_page.dart` | 私有分组卡两种 | `_Section` `:637-690`、`_FoldSection` `:745-788` | 已有的 `SettingSection`（支持 collapsible） | 11+→1 |
| 11 | `prompt_strategy_advanced_page.dart` | 三个策略行 + 10 个手写 TextField | `_enumRow``:606-633`、`_TriSwitchRow``:794-843`、`_LevelRow``:846-892` | `lib/widgets/strategy_rows.dart`（= 现 `settings/widgets/strategy_field_rows.dart` 上移） | 13→3 |
| 12 | `setting_collapsible.dart` | 折叠行头 + 折叠体 | 行头 4 份 `:120-144/338-362/497-521/621-645`；展开体 4 份 `:152-212/368-428/522-563/648-697`；第 5 份 `tts_settings_spec.dart:248-320`、第 6 份 `setting_section.dart:144-221` | 同文件内 `CollapsibleRow` + `CollapsibleBody`（`_CollapsedHeader`:708-737 已有，缺的是它的 child） | 6→2 |
| 13 | `card_detail_page.dart` | 私有错误态类（60 行） | `_ErrorBody` `:2085-2145` | `AppErrorState`（外层包 `SliverAppBar` 保留返回键） | 1 份 |
| 14 | `root_shell.dart` + `home_body.dart` | 站点公告弹层（注释说「共用」，实际两份） | `root_shell.dart:819-820` vs `home_body.dart:438-439`（后者多 `onOpen`） | `island_app/widgets/announcement_sheet.dart` | 2→1 |
| 15 | `explore_body.dart` + `home_body.dart` | 骨架卡（逐行相同，含同样的注释） | `:270-307` vs `:336-373` | `island_app/widgets/skeleton_card.dart` | 2→1 |
| 16 | `oobe_steps.dart` | 四步共用骨架 | `:381-390`/`:658-667`/`:792-806`/`:867-871` | 同文件内 `OobeStepScaffold` | 4→1 |
| 17 | `ta_editor_page.dart` + `world_editor_page.dart` | 编辑器外壳（AppBar + 菜单 + 顶栏保存 + FAB + 返回确认） | `:104-166` vs `:182-267` | `lib/widgets/editor_shell.dart`（内接 `SubmitFormState`） | 2→1 |
| 18 | `card_detail_page.dart` | 15 个纯展示私有 widget | `:1091-1981` | `island_app/card_detail/` 子目录 | 搭车，不单独立项 |

注：#1–#9 属批 3，#10–#13 属批 6（动观感），#14–#18 属批 2 收尾。

其余 >700 行文件（`search_page` 1082、`image_gen_body` 1035、`tickets_page` 912、`world_detail_page` 881、`app_settings` 875、`teahouse_post_page` 873、`root_shell` 867、`prompt_strategy` 823、`image_gen_detail_page` 802、`chat_input_bar` 794）**不建议单独立项拆文件**——它们的病灶都被第 1 节的表或第 3 节的条目覆盖了，单拆只会「文件数变多、重复照旧」。

---

## 3. 状态管理：两处最脏

### 3.1 `AppController`：一个 notifier 管 7 个领域

- 6 个可变状态字段（`app_controller.dart:77-82`）承载 7 个领域，129 个方法，**99 个 notifyListeners**；
- **69 个 notify 挤在 293-973 这 680 行设置写入区**，占七成；
- 15 个纯转发 getter，其中 176/179/181/183 是同一句 `.where((x) => !x.archived).toList()` 抄 4 遍，且**每次 build 都新建一份 List**；
- **粒度失控**：存一条聊天消息（`:1407 upsertConversation`）和拨一个开关（`:431`）是同一个事件。24 处 `ListenableBuilder(listenable: controller)` 全是「任一变全都变」；设置页每次通知要重建 55 条字段 + 重新 `toJson()` 一次 78 字段；
- **41 个死 setter**（435-439、705-710、760-774、893-903 一族，约 244 行）**零调用点**——设置已经有第二套写入口 `patchSettings`(`:428`)，旧的没删，还带着「clamp 在这里做」的错误暗示；
- 拆分方案已给到行区间：`SettingsController`(≈600) / `LlmProfileController`(≈260) / `LibraryController`(≈420) / `ConversationStore`(≈400) / `BackupController`(≈720)，`AppController` 留 120 行当组合根。跨域耦合只有 3 条，facade 转调即可。

### 3.2 `ChatState`：双份持有 + 31 个转发器 + 三功能污染

- **38 个活字段分家两处**：19 个在 `state/chat_state.dart`、19 个在 `chat_state_mixin.dart`；
- `chat_state.dart:9-10` 的 `conversation` / `accent` **全库无读写**（死字段），真值在 mixin 的 15-16 行另存一份；
- `chat_state_mixin.dart:24-61` **31 个 getter/setter 只做 `=> _state.x` 转发**，38 行；
- **接缝切反**：mixin 在 87-89 行声明三个方法，实现在 `chat_surface.dart:220/249/304`——State 类反过来给 mixin 供料；
- **三功能污染**：摘要 5 个字段、灵感 3 个、重说 2 个全塞在「聊天状态」里；BGM 的 2 字段 4 方法也在（`chat_state_mixin.dart:209-261`），页面 State 兼职音乐生命周期观察者。

---

## 4. 结构性问题：分层有三处倒置

island_app **不是**平行体系（86 个文件里大量 `import 'package:dna/models/...'`、`services/`、`utils/`），但依赖方向有三处反了：

| 反了的地方 | 证据 | 后果 |
|---|---|---|
| 共享 `lib/widgets/paged_list_body.dart` 依赖社区 5 个件 | `:3` app_dimensions、`:4` load_more_list、`:5` refreshable、`:6` state_views、`:7` wide_body | 通用分页组件住在 `island_app/` 里，主程序要用就得反向依赖 |
| 设置规格树依赖社区页 | `pages/settings/spec/settings_tree.dart:25` → `island_app/server_settings_body.dart`、`:26` → `sponsor_body.dart` | 设置树的 spec 层引用了社区 UI，隔层 |
| `AppController` 依赖社区裁剪页 | `state/app_controller.dart:43` → `island_app/widgets/card_crop_page.dart` | 状态层直接依赖某个 UI 页 |

**动作**：把 `state_views` / `load_more_list` / `refreshable` / `wide_body` / `app_dimensions` 上移到 `lib/widgets/`（`state_views` 已经这么做了，用 `typedef` 保留短名零改造），`paged_list_body` 的 5 个 import 就变成同层；`settings_tree` 的两处改走 `SettingAction` 之外的自定义入口；`app_controller` 那处把 `FreeImageCrop` 换成注入的函数句柄。
另有两个同名类（`AppSettings`：`island_app/app_settings.dart:8` vs `models/app_settings.dart:16`；`SearchPage`：`island_app/search_page.dart:33` vs `pages/search_page.dart:17`），建议后者改名，否则每次搜符号都会撞。

---

## 5. 安全网缺口：重构前必须先补的东西

**32 个 >500 行的文件没有任何定向测试**，几乎全部集中在两个地方：island_app（14 个）与 chat/编辑器（8 个）。`test/` 有 122 个文件 20,879 行，但**覆盖集中在设置 spec、动画、附件、存储**这些新代码上。

这意味着第 1 节那批「纯替换」是**安全的**（有 `AppEmptyState` 等单测兜着样式），但第 3、4 节的拆分**没有安全网**。

所以批 0 不是建议，是前置条件。按优先级补四条能失败的测试：

1. **payload 装配 golden**：4 个入口（发送/继续说/重说/群聊点名）改造前抓一份完整 payload 列表，逐字节对比。这是 F-01 唯一的验收方式。
2. **五态渲染**：对 `PagedListBody` 做一次「loading / error / empty / loaded / loadingMore」的快照测试，替换 18 处时才有对照物。
3. **设置字段表对账**：断言 `settingsKeyKinds` 条数 == `copyWith` 参数表条数 == `settings_service` 读写键条数。现在注释里写 82、实测 78，这种漂移只能靠测试拦住。
4. **导入骨架**：三条导入路径（`importConversations` / `applyConversationImport` / `_applyImport`）各一条「导入后集合内容」的断言，再合并。

仓库已有 `test/state_views_single_source_test.dart` 这个先例——**这类守卫测试是本仓库自己的既定做法，扩展它比引入新工具便宜**。

---

## 6. 不建议做的事（防止第三次重构撞车）

这四条是三个域各自主动纠正的假设，写下来免得下次又提一遍：

1. **不要合并 `app_section.dart` 与 `setting_section.dart`**。前者是主导航壳（`enum AppSection` 是底栏/抽屉栏目，含 sectionFlight 转场），与设置分组零重叠。
2. **不要动设置 spec 体系**。9 个 `*_spec.dart` 全部由 `settings_tree.dart:97-180` 挂进树，页面走 `settings_catalog.dart:96-111` → `settings_fields_page.dart:89-112`，搜索索引共用同一棵树。它是本仓库唯一做到「一处声明、三处消费」的地方，旧 page 已全删。
3. **不要把 `FormDraft` 推广到设置页**。设置是「改了就落盘」，编辑器是「草稿+显式保存」，写通道不同。
4. **不要为 `SettingItemSpec` 加别名/关键词字段**、**不要把 5 个 `SettingAction` 自绘控件强行统一**（seed 输入、模型下载面板、强调色磁贴、预设行、检查更新磁贴彼此不同构，只有生命周期外壳像）。

另：`mixin` 拆出来的 `chat_page.dart` **不是转发壳**——20 个方法没有一个是参数原样转发的空壳，它的残渣是死代码不是冗余层（见附录 A F-09）。

---

## 7. 落地批次（按「风险从低到高、依赖从先到后」）

每批的验收统一为：`flutter analyze` 零新警告 + 该批定向测试通过；**全量测试只在提交前跑一次，且必须 `-j 2`**（本机 16GB，默认并发下 `attachment_gc_test` 会假超时）。

| 批 | 内容 | 预计净变化 | 风险 |
|---|---|---|---|
| **0** | 第 5 节四条特征测试 | +测试 | 无 |
| **1** | 纯删除：41 个死 setter、死字段 `chat_state.dart:9-10`、死文件 `conversation_service`/`world_service`、死方法 `_buildSystemPrompt`、4 个 18 行兼容壳、悬空注释、7 个零写入 patch 键 | **-700 行** | 零 |
| **2** | 接上已有入口（第 1 节全表）：showSnack 64→1、三态 65→3、分页五态 18→2、AttachmentIntake 21→2、PostLikeFav 10→2、RowAction 菜单、SettingSection 分组头 11→1、copyToClipboard 3→1、relativeTime 2→1 | 行数几乎不变，**但 N 份真相变 1 份** | 低（纯替换） |
| **3** | 合并唯一入口：chat payload 4→1、轮次脚手架 3→1、候选生成 4→1、候选弹框 2→1、编辑器外壳 2→1、折叠行 6→2、策略行 13→3、FormHandle 3→1、AsyncController 16→1、设置字段表 9→1 + 单键落盘 65→1 | **-1200 行** | 中 |
| **4** | 拆上帝：`AppController` → 5 域（先做分组通知再做搬家）；`ApiClient` → transport + 6-8 个子客户端 + 3 个 helper | **-800 行** | 中高 |
| **5** | 状态收尾：ChatState 双份合一、31 个转发器删除、摘要/灵感/重说/BGM 迁出、6 处滚动排帧收成 1 处 | **-300 行** | 中 |
| **6** | 视觉回归类：`prompt_strategy` 两页换 `SettingSection`、`card_detail` 纯展示 widget 挪子目录、`oobe_steps` 抽 `OobeStepScaffold` | 无净删 | 需逐页看观感 |

**不要并行做批 2 与批 3**：批 3 会重写批 2 刚接好的调用点（例如 `tickets_page` 的五态与它的 `_pickImage` 在同一段代码里）。

**批 4 必须放在批 3 之后**：`AppController` 拆分前要先有「字段表唯一」与「单键落盘」，否则拆完 5 个 controller 只是把 65 次写扩散到 5 个地方。

---

## 8. 附：全仓库量化底数

```
dart 文件 475 / 111,741 行        >800 行 23 个 / >500 行且无定向测试 32 个
私有 widget 类 289 个             同名重复类 3 组（_SkeletonCard/_HeroBanner/_SectionHeader）
setState( 576 处 / 110 文件        notifyListeners( 129 处 / 13 文件（98 在 app_controller）
CircularProgressIndicator 88 / 45  SharedPreferences.getInstance 21 / 11（三套访问方式）
jsonDecode 40 / 25                 jsonEncode 40 / 19
path.join 40 / 12                  getApplicationDocumentsDirectory 13 / 9
catch (e)/(_) 290 处（空 catch 14） '$e' 直接拼给用户 96 处
平台条件导入三件套 7 组 / 21 文件 / 1,314 行
测试 122 文件 / 20,879 行          守卫型测试 5 个（state_views_single_source 等）
```

---

# 附录：分域原始清单

> 附录 A–D 是四个域的完整发现，保留原始证据与行号，未做删改。

---

## 附录 A：chat 聊天链路（11 条，P0×2 / P1×6 / P2×3）

### 审计范围与总判

范围：`lib/pages/chat/**` 全部 28 个 dart 文件（约 6 400 行）+ `lib/pages/chat_page.dart`（586 行）。

总判：**拆分方向是对的，重复不在文件之间，而在 mixin 内部——同一件事被抄了 3~4 遍。**
chat_page 已经瘦成"页面壳 + 滑块动画"，真正的聊天逻辑落进了 `chat_surface.dart` 的 13 个 part（5 个 helpers mixin + 5 个 actions mixin）。问题在于 mixin 之间没有共享「请求装配 / 轮次脚手架 / 候选生成」这三层，于是每个 action 各自抄一份。

共 11 条：P0 两条（F-01、F-02），P1 六条，P2 三条。

### 先回答 a–g 七个问题

**a. chat_page.dart 留下的转发壳？——没有壳，但有残渣。**
20 个方法里没有一个是「参数原样转发」：`_openConversation`(158-160) 虽只有一行，但它是 fade 语义的唯一入口；`_viewFor`/`_peekFor` 是性能缓存不是转发。**真正可以整段删的是残渣**，不是方法：9 行悬空文档注释（578-586）、2 个死 import（2、5）、1 个死方法（chat_payload_builders.dart:5-14）、17 条过期的 `// ignore: unused_element`、2 套同构的 widget 缓存（403-418 / 421-437）。见 **F-09**。

**b. 消息渲染分支？——有，而且比预期更碎。**
`chat_message_list.dart` 是「1 个 388 行 itemBuilder 闭包」+「3 段手抄的菜单接线」+「2 段手抄的卡片外壳」，`kind` 是裸字符串（models/conversation.dart:159、170），本集群 25 处字面量比较。可以变成 kind→widget 的映射表，而且**同目录已经有这种模式的先例**（chat_app_bar.dart:166-235 用 `List<RowAction>` 渲染整个 ⋮ 菜单，机制在 utils/action_table.dart:53-89）。见 **F-02**。

**c. 流式 delta/done/error 重复？——不重复，这条不报。**
只有一个消费点：chat_stream_handlers.dart:52-122 的 `await for` + `switch (chunk)`（4 个 case 全覆盖），chat_actions_send 三处只是调用它（278、390、611）。重复在它的**上游**（payload 组装，F-01）和**下游**（候选生成 F-04 / 候选弹框 F-05），不在回调本身。

**d. 滚动与定位？——三层包装同一件事，5 处手工排帧。**
`ChatController.scrollToBottom` 内部已经 `addPostFrameCallback`（chat_controller.dart:10-21），调用侧又套一层（chat_ui_helpers.dart:507-509、669-671、734-739），mixin 还再延迟 300ms 补滚一次（chat_state_mixin.dart:144-148），键盘弹出时第四次（172-188）。见 **F-11**。

**e. state 里塞了多少不是聊天的东西？——38 个活状态字段，两处分家，31 个纯转发访问器。**
- `chat_state_mixin.dart`（361 行）自带 16 个可变字段：4、7、8、9、11、12、13、14、15、16、17、18、22、39、40、209；
- `chat_state.dart`（35 行）21 个字段，其中 `conversation`(9)、`accent`(10) **全库无任何读写**（死字段），真正的值在 mixin 的 15、16 行另存一份；
- 另有 3 个字段散在别的 mixin：chat_stream_handlers.dart:12、chat_actions_send.dart:67、70；
- 合计 **38 个活字段**：19 个在 ChatState，19 个在 mixin。其中摘要 5 个（chat_state.dart:23-28）、灵感 3 个（29-31）、重说 2 个（33-34）、搜索 2 个（14、16）、token 1 个（15）——三个独立功能的状态全塞在「聊天状态」里；
- 31 个 getter/setter（chat_state_mixin.dart:24-61，38 行）只做 `_state.x` 转发；
- 接缝切反了：mixin 在 87-89 行**声明** `_ensureOpeningMessage`/`_loadAccent`/`_scrollToBottom`，实现却在 chat_surface.dart:220、249、304（State 类反过来给 mixin 供料）。

见 **F-07**。

**f. chat_ui_helpers.dart 是杂物抽屉吗？——有一半是。**
顶层符号只有 3 个：`mixin ChatUiHelpers`(3-746)、`_RetryOriginalCard`(749-794)、`RetryOptionCard`(798-895)。但 mixin 内部混了四类职责：

| 片段 | 行 | 归位判断 |
|---|---|---|
| 消息菜单 + 动作分发 | 31-331 | 留下（这才是「聊天动作」） |
| 重说结果弹框（整块 UI） | 334-510 | 搬走 → 与灵感弹框合并成 `candidate_picker_sheet.dart`（F-05） |
| 消息编辑 / 回溯 / 分叉 | 512-729 | 留下（其中「替换第 i 条并落库」重复，见 F-03） |
| 菜单后的收焦 + 滚动善后 | 731-745 | 搬走 → `ChatController`（F-11） |

外加 `_RetryOriginalCard` 只被 426 行用一次、`RetryOptionCard` 被 429 行与 chat_actions_inspiration.dart:276 共用 —— 两颗卡片都该搬进候选弹框文件，现在它们藏在一个叫 ui_helpers 的文件里。

**g. 超长 build / 方法清单**

| 方法 | 位置 | 行数 | 建议拆出 |
|---|---|---|---|
| `build` | chat_surface.dart:753-1232 | **480** | `_ChatBackground`(1089-1156)、`_ImmersiveExitButton`(1057-1084)、`_TypingIndicator`(978-998) |
| `_showMemberPicker` | chat_surface.dart:381-585 | **205** | `ui/widgets/group_member_picker_sheet.dart` |
| `_buildSpeakerBar` | chat_surface.dart:630-742 | **113** | `ui/widgets/speaker_bar.dart` |
| `build` | chat_message_list.dart:142-529 | **388** | 见 F-02：`_SummaryPromptBubble`/`_SummaryBubble`/`_ChatBubble` + `_MessageGesture` |
| `_buildHighlightedText` | chat_message_list.dart:845-1051 | **207** | `utils/novel_text_spans.dart`（**仅搬迁，无第二调用点**，不建议抽象；排最后做） |

### 发现

#### F-01 请求装配四处
- 病灶类型：重复逻辑
- 证据：
  - `lib/pages/chat/actions/chat_actions_send.dart:242-277`（_send：latestSummary → sliceForPayload → collectFor → buildMessagesFrom）
  - `lib/pages/chat/actions/chat_actions_send.dart:447-483`（_generateRetryCandidates：同 20 行，仅 slice 参数不同）
  - `lib/pages/chat/actions/chat_actions_send.dart:574-610`（_triggerTaReply：再抄一遍）
  - `lib/pages/chat/actions/chat_actions_send.dart:327-389`（_continueFromContext 干脆手抄了整个 buildMessagesFrom 的布局：system→摘要→历史循环→mergeAdjacentSameRole→lore→authorNote），而 `ChatMessageBuilder.buildMessagesFrom` 早就支持同样的布局，见 `lib/pages/chat/chat_message_builder.dart:229-290`
- 现状：同一次「把当前会话装成 LLM 请求」在 4 个入口各写一遍，其中 3 份逐字相同、第 4 份是手抄的平行实现；第 5 份（`_buildSystemPrompt`）拆分后已死，见 chat_payload_builders.dart:5-14。同一病灶还有衍生副本：「禁止输出词语」这段 system 文案在 chat_payload_builders.dart:111-115、chat_summary.dart:153-158、chat_summary.dart:231-236 三处逐字重复，第四次在 chat_system_prompt.dart:130。
- 重构动作：新建 `lib/pages/chat/builders/chat_request_builder.dart`，放一个 `ChatRequestBuilder.payload({required TA ta, ConversationMessage? placeholder, int? endExclusive, Set<String>? excludeIds, String? extraSystemTail})`，把「摘要切片 + 视觉图片收集 + system prompt + 历史 + 尾部」收成唯一入口；四处调用点改成一次调用（_send 与 _generateRetryCandidates 只差 endExclusive/excludeIds）；_continueFromContext 的手抄布局删掉，改用 `buildMessagesFrom(..., extraUserText:)`（该参数已存在于 chat_message_builder.dart:234）；「禁止输出词语」抽成 `ChatSystemPrompt.forbiddenWordsLine(World?)`，4 处调用。
- 消掉多少重复：payload 装配 4 处 → 1 处（约 130 行），禁词文案 4 处 → 1 处（约 15 行）
- 风险：最坏是把「继续说」的 system 指令从尾部位置挪到 history 之前，KV cache 前缀全失效（首字延迟变长）；再坏一点是群聊 `mergeAdjacentSameRole` 漏调，Anthropic 严格交替报 400。落地时必须逐字节对比改造前后 payload（建议先写 golden 对比 4 个入口的 payload 列表）。
- 优先级：P0

#### F-02 消息分支三份手抄
- 病灶类型：重复逻辑 / 可提取组件
- 证据：
  - `lib/pages/chat/ui/widgets/chat_message_list.dart:155-213`（summary_prompt 分支）、`:215-273`（summary 分支）、`:275-529`（普通气泡）——三段都在同一个 itemBuilder 闭包里
  - 菜单接线逐字 3 份：`:160-173`、`:224-237`、`:307-320`（都是 GestureDetector 的 onLongPressStart + onSecondaryTapDown 调同一个 onShowMessageMenu）
  - 卡片外壳逐字 2 份：`:174-182` 与 `:238-246`（margin/padding/maxWidth/decoration 完全一致）
  - kind 字面量比较 25 处：`chat_message_list.dart:155,215,278,280,433`、`chat_payload_builders.dart:20,31,53,65,78,125,145`、`chat_ui_helpers.dart:18,51,93,129`、`chat_actions_send.dart:81,296,359`、`chat_surface.dart:317,332`、`chat_summary.dart:50,209`、`state/chat_controller.dart:31`、`chat_message_slice.dart:43`、`chat_message_builder.dart:261`；类型定义处 `lib/models/conversation.dart:159,170` 只是 String
- 现状：气泡外观由一串 if + 裸字符串判断决定，每加一种 kind（现在 3 种）就要再抄一份手势接线与卡片外壳。
- 重构动作：①`chat_models.dart` 增 `enum MessageKind { message, summary, summaryPrompt }` + `MessageKind.of(String)`，25 处比较改枚举（拼错就从编译期消失）；②新建 `lib/pages/chat/ui/widgets/message_bubbles.dart`，放 `_SummaryPromptBubble`、`_SummaryBubble`、`_ChatBubble` 三个 widget 与一个 `_MessageGesture`（封装 onLongPressStart/onSecondaryTapDown，3 份 → 1 份）；③`ChatMessageList.build` 的 itemBuilder 只剩一个可穷尽的 `switch (kind)` 派发 + 「是不是最后一条 AI」的判定。
- 消掉多少重复：菜单接线 3 → 1，卡片外壳 2 → 1，388 行闭包 → 3 个约 40 行的 widget + 20 行派发
- 风险：最坏是 `GlobalKey` 的挂载点从 itemBuilder 根部挪进子 widget，搜索跳转会 `Scrollable.ensureVisible` 失效（key 必须留在 `Align` 这一层，chat_message_list.dart:156、220、424、487）；其次是群聊「最后一条 assistant」判定要跟着 switch 走，漏了会让「重说/继续说」按钮出现在所有气泡上。
- 优先级：P0

#### F-03 轮次脚手架三份
- 病灶类型：重复逻辑
- 证据：
  - `lib/pages/chat/actions/chat_actions_send.dart:224-241`（newId → 空 assistant 消息 → copyWith(messages+activeTaId) → upsert → mounted → setState → _scrollToBottom）
  - `lib/pages/chat/actions/chat_actions_send.dart:309-326`（同 18 行）
  - `lib/pages/chat/actions/chat_actions_send.dart:556-573`（同 18 行）
  - 收尾也三份：`:278-287`、`:390-399`、`:611-620`（streamed 判定 → `setState(() => _sending = false)` → `_maybePromptSummary()`）
  - 同类还有「替换第 index 条并落库」两份：`lib/pages/chat/ui/chat_ui_helpers.dart:494-501` 与 `:585-592`
- 现状：每加一个「发起一次生成」的入口（发送/继续/群聊点名/重说），就要把这套占位-落库-滚动-收尾抄一遍；`_sending` 的置位与复位散在 8 处（223、286、308、398、417、422、555、619）。
- 重构动作：在 `chat_actions_send.dart` 加两个私有方法：`_beginAssistantTurn(TA ta, {bool group = false})` 返回 `(String assistantId, ConversationMessage message)`；`_endAssistantTurn({required bool streamed})` 负责 streamed 判定、`_sending = false`、`_maybePromptSummary()`。另加 `_replaceMessageAt(int index, ConversationMessage)` 收掉 _showRetryPicker/_editAssistantAt 的换条逻辑。
- 消掉多少重复：轮次脚手架 3 → 1（约 40 行），收尾 3 → 1，换条 2 → 1
- 风险：最坏是群聊与单聊的落库函数选错（单聊走 `upsertConversation`，群聊必须 `upsertGroupConversation`）→ 群聊被写成单聊，聊天记录在列表里"消失"（这个坑 chat_state_mixin.dart:101-104 的注释已经踩过一次）。参数化时必须显式传 group 标志，不要靠 `_isGroup` 猜。
- 优先级：P1

#### F-04 候选生成两套实现
- 病灶类型：重复逻辑
- 证据：
  - `lib/pages/chat/actions/chat_actions_send.dart:497-523`（_generateRetries：并发 3 条 + 300ms 错峰）
  - `lib/pages/chat/actions/chat_actions_send.dart:525-545`（_generateRetriesSequential：串行 3 条）
  - `lib/pages/chat/actions/chat_actions_inspiration.dart:72-91`（灵感的串行版，逻辑同上）
  - `lib/pages/chat/actions/chat_actions_inspiration.dart:93-108`（灵感的并发版，逻辑同上）
- 现状：同一件事（用同一份 payload 要 N 条候选、失败吞掉、空串过滤）写了 4 遍，差异只有：条数、是否错峰、是否 `stripThoughtTags`（灵感做、重说不做）。
- 重构动作：新建 `lib/pages/chat/builders/chat_candidate_generator.dart`：`Future<List<String>> generateCandidates(ChatCandidateRequest{payload, count, sequential, stagger, transform})`；4 个方法删掉，调用点改成一次调用（重说传 `transform: (c) => stripOwnSpeakerPrefix(c, ta.name)`，灵感传 `stripThoughtTags`）。
- 消掉多少重复：4 → 1（约 90 行）
- 风险：最坏是把灵感的 `stripThoughtTags` 与重说的 `stripOwnSpeakerPrefix` 搞混 → 灵感里出现 thought 标签文本，或群聊候选带「名字：」前缀入库后滚成「名字：名字：」。transform 必须由调用方显式传，不要给默认值。
- 优先级：P1

#### F-05 候选弹框两份拷贝
- 病灶类型：可提取组件 / 重复逻辑
- 证据：
  - `lib/pages/chat/ui/chat_ui_helpers.dart:334-510`（_showRetryPicker，177 行）
  - `lib/pages/chat/actions/chat_actions_inspiration.dart:118-335`（_InspirationSheet，218 行）
  - 结构逐项对应：标题行 `helpers:386-420` vs `inspiration:211-220`；`LinearProgressIndicator` helpers:421 vs inspiration:251-255；候选列表 `helpers:422-438` vs `inspiration:270-286`（都用 RetryOptionCard）；三按钮底栏 `helpers:439-482` vs `inspiration:288-328`（取消/关闭、再生成/再试、使用 —— 连同 `viewPadding.bottom` 的键盘避让写法都一致）；选中态 + 新标记逻辑 `helpers:347-377` vs `inspiration:142-189`
- 现状：两块弹框唯一的实质差异是「灵感顶部多一个主题输入框」，其余约 150 行是同一份代码。
- 重构动作：新建 `lib/pages/chat/ui/widgets/candidate_picker_sheet.dart`，含 `CandidatePickerSheet`（参数：`title、header?、options、onRegenerate、regenerateLabel、confirmLabel、resetOnRegenerate`）+ 把 `RetryOptionCard`(helpers:798-895) 与 `_RetryOriginalCard`(749-794) 一起搬进这个文件；重说与灵感各留一个 20 行左右的调用点（灵感只多传一个 header widget）。
- 消掉多少重复：2 套 150 行 → 1 套 + 2 个薄调用
- 风险：最坏是灵感的「换主题就清空旧候选」语义（inspiration:181-186）与重说的「再试只追加」语义（helpers:366-369）被合成一个默认行为 —— 灵感会把上一题的答案混进这一题。合并时把「换批策略」作为显式参数（`resetOnRegenerate`）。
- 优先级：P1

#### F-06 五处超长方法
- 病灶类型：可提取组件
- 证据：见上文 g 表。最狠的 `chat_surface.dart:753-1232`（480 行）里塞了：背景立绘 + 蒙层渐变（1089-1156）、内容列（797-1087）、Scaffold/AppBar 装配（1157-1229）、沉浸退出球（1057-1084）、"对方正在输入"条（978-998）——全是并列关系，没有一个是"必须在这里"的。`_showMemberPicker`(381-585) 更是把一整个「添加群成员」的搜索式多选 sheet 内联在 State 里。
- 现状：单个 build 里 5 个并列图层平铺，改任何一处（比如"对方正在输入"的样式）都要在 480 行里定位。
- 重构动作：
  - `chat_surface.dart` → 抽 `ui/widgets/chat_background.dart`（1089-1156，含 GIF/群头像/蒙层渐变）、`ui/widgets/immersive_exit_button.dart`（1057-1084）、`ui/widgets/typing_indicator.dart`（978-998）、`ui/widgets/group_member_picker_sheet.dart`（381-585）、`ui/widgets/speaker_bar.dart`（630-742）；
  - `chat_message_list.dart:142-529` 按 F-02 拆；
  - `chat_message_list.dart:845-1051`（_buildHighlightedText，207 行、5 层嵌套闭包）搬到 `lib/utils/novel_text_spans.dart`——它只有一个调用点（362 行），是搬迁不是抽象。
- 消掉多少重复：不消重复，消的是「一个方法里 5 个并列职责」；build 480 → 约 120 行
- 风险：最坏是抽 `_buildSpeakerBar`/`_ChatBackground` 时把 `Theme.of(context)` 取到的 `primaryContainer`/`surfaceContainerHighest` 改成父级传色 → 沉浸态与强调色切换后颜色不跟着变（这两个色现在是 build 里现取的，chat_surface.dart:819-823）。抽 widget 时让子 widget 自己 `Theme.of`。
- 优先级：P1

#### F-07 状态双份转发器
- 病灶类型：状态脏乱
- 证据：
  - 死字段：`lib/pages/chat/state/chat_state.dart:9-10`（`Conversation? conversation`、`Color? accent`）——全库只有 chat_state_mixin.dart:24-61 读写 `_state.其它字段`，这两个从无读写；真值在 `chat_state_mixin.dart:15-16`（`late Conversation _conversation`、`Color? _accent`）另存
  - 转发层：`chat_state_mixin.dart:24-61`，38 行 31 个 getter/setter，全部是 `=> _state.x`
  - 污染：`chat_state.dart:23-28`（摘要 5 个）、`:29-31`（灵感 3 个）、`:33-34`（重说 2 个）与聊天状态同处一 class；BGM 两个字段与 4 个方法在 `chat_state_mixin.dart:209-261`，`didChangeAppLifecycleState`(191-206) 让聊天页 State 兼职音乐生命周期观察者
  - 接缝切反：`chat_state_mixin.dart:87-89` 声明三个方法，实现在 `chat_surface.dart:220、249、304`；另有 3 个字段飘在别的 mixin（chat_stream_handlers.dart:12、chat_actions_send.dart:67、70）
- 现状：一个页面的状态分两处持有，19 个字段在 ChatState、19 个在 mixin；访问字段要么走转发器要么直接摸 mixin 私有字段，两种写法并存。
- 重构动作：①删 `chat_state.dart:9-10` 两个死字段；②把 `chat_state_mixin.dart:24-61` 的 31 个访问器**整段删除**，改为在 mixin 内部直接读写 `_state.sending`（或把 ChatState 拆成 `ChatRunState`/`SummaryState`/`InspirationState` 三个小对象，各由对应 mixin 持有）；③摘要 5 字段搬进 `ChatSummaryHelpers` 自己的私有状态，灵感 3 字段搬进 `ChatActionsInspiration`；④BGM（209-261 + 191-206）搬进独立 `ChatBgmController`；⑤`_ensureOpeningMessage`/`_loadAccent`/`_scrollToBottom` 的实现从 chat_surface.dart 挪进 mixin（消除反向依赖）。
- 消掉多少重复：字段持有 2 处 → 1 处；31 个访问器 → 0；跨功能字段 13 个（摘要 5 + 灵感 3 + 重说 2 + BGM 2 + lore 1）迁出聊天状态
- 风险：最坏是删访问器时顺手给 setter 加了 `setState` → 流式回调里每 100ms 一次的更新变成重入。`_sending` 的写入必须保持"裸赋值 + 调用点自己 setState"。
- 优先级：P1

#### F-08 菜单项手写十四行
- 病灶类型：重复逻辑（复用已有机制，不新建抽象）
- 证据：
  - `lib/pages/chat/ui/chat_ui_helpers.dart:55-77`（摘要菜单 3 项，逐字手写 `Row(Icon, AppSpacing.wMd, FitText)`）
  - `lib/pages/chat/ui/chat_ui_helpers.dart:97-112`（摘要提示菜单 2 项，同样手写）
  - `lib/pages/chat/ui/chat_ui_helpers.dart:145-163`（这里才定义 `item(value, icon, label)` 辅助函数）→ `:173-217`（9 项用它，但危险项 198-217 又退回手写）
  - 已有机制：`lib/utils/action_table.dart:53-89`（`RowAction`：id/label/icon/visible/enabled/checked/danger/itemStyle），同目录 `lib/pages/chat/ui/widgets/chat_app_bar.dart:166-235` 已经用它把整个 ⋮ 菜单写成数据表
- 现状：同一个函数里三种写法（手写 / 用 item() / 用 item() 再手写危险项），visible/enabled/danger 三个语义各实现一遍；而 app_bar 那边已经证明 RowAction 够用。
- 重构动作：`_showMessageMenu` 改成先构造 `List<RowAction>`（visible/enabled/checked/danger 直接落到字段），再交给一个新增的锚定位入口 `rowActionMenuAt(context, position, actions)`（加在 action_table.dart 里，内部就是现在 `:113-124` 的 onSelected 查表 + `showMenu`）。**不要**再造第二套菜单抽象——RowAction 就是它。
- 消掉多少重复：菜单项构造 3 种写法 → 1 张表；14 行手写行 → 14 个 RowAction
- 风险：最坏是 PopupMenuItem 的 `enabled` 与 RowAction 的 `enabled` 语义错位（后者是"置灰但仍显示"，action_table.dart:78-80 有注释），改完「重说」在不可用时可能整项消失而不是置灰。落地时对着 174-177 行逐项核对。
- 优先级：P2

#### F-09 拆分残留五类
- 病灶类型：状态脏乱
- 证据：
  - `lib/pages/chat_page.dart:578-586`：9 行 `_HorizontalDominantDragRecognizer` 的文档注释悬在文件末尾，**后面没有任何声明**（该类已搬去 `lib/pages/chat/chat_surface.dart:1385-1418`）
  - `lib/pages/chat_page.dart:2`（`import 'dart:ui' as ui;` 全文无 `ui.` 使用）、`:5`（`conversation_labels.dart` 的三个函数在 chat_page 里一次都没用）
  - `lib/pages/chat/builders/chat_payload_builders.dart:5-14`：`_buildSystemPrompt` 全库唯一一处出现（连抽象声明都没有），死方法 10 行
  - 18 条 `// ignore: unused_element`，其中 **17 条已过期**：`_summaryById`(payload_builders:38) 用在 chat_surface.dart:909、`_continueFromContext`(send:290) 用在 helpers:229、`_maybePromptSummary`(summary:28) 用在 send:287/399/620、`_streamAssistantResponse`(stream_handlers:33) 用在 send:278/390/611、`_showSummaryDetail/_editSummary/_deleteSummary`(summary_ui:6/24/37) 用在 helpers:84/86/88、`_insertMessageAfter/_removeMessageById`(actions:4/16) 用在 summary:72/99/305/327、`_totalTurnCount/_lastChatMessageId/_hasSummaryPrompt/_recentTurnSlice/_buildInspirationPayload`(payload_builders:16/27/51/56/133) 分别在 chat_summary 与 chat_actions_inspiration 被调用
  - 两套同构缓存：`chat_page.dart:403-418`（_viewFor：字段 120-123）与 `:421-437`（_peekFor：字段 115-117），都是"key 不变就复用同一 Widget 实例"
- 现状：`part` 拆分让私有方法跨 part 可见，analyzer 报 `unused_element`，于是有人批量加 ignore 消警告 —— 结果**唯一一处真死代码（_buildSystemPrompt）混在 17 条假警告里，正好被掩盖**。
- 重构动作：①删 chat_page.dart:578-586 的悬空注释、删 :2 与 :5 两个 import；②删 `_buildSystemPrompt`(payload_builders:5-14) 与它那行 ignore；③删掉其余 17 条过期 ignore（删完 `flutter analyze` 应零新警告，若有新警告说明又发现一处真死代码）；④把两个缓存合成一个 `_CachedInstance<T>`（`match(key)/get(build)`），chat_page.dart 少 5 个字段、2 个方法体。
- 消掉多少重复：同构缓存 2 → 1；无效护栏 18 → 0
- 风险：最坏是删完 ignore 后发现其中有 1 条其实是真死的，那就不是警告而是需要决策的删改 —— 所以一次只删 ignore、不改结构，先看 analyze 输出再决定。
- 优先级：P1

#### F-10 侧栏重复算数据
- 病灶类型：重复逻辑
- 证据：
  - 角色列表（有非归档 1:1 会话的角色）：`lib/pages/chat_page.dart:308-317`（_swipeCharacters）与 `lib/pages/chat/ui/chat_quick_sidebar.dart:124-133`（_characters），逐字同构
  - 会话查询一行别名：`lib/pages/chat_page.dart:303-304` 与 `lib/pages/chat/ui/chat_quick_sidebar.dart:109-110`（都是 `controller.getConversationById`）
  - 「最近活跃的 1:1 会话」：`lib/pages/chat_page.dart:323-341`（_mostRecentConversationOf，手算 timestamp 最大值）与 `lib/utils/conversation_labels.dart:42-57`（conversationsOfTa，已含 pinned 优先 + lastMessageAt 排序）——后者更完整，前者是它的退化版
  - 群聊判定：`lib/pages/chat_page.dart:286-288`（_isGroupOf）与 `lib/pages/chat/state/chat_state_mixin.dart:63`（_isGroup），两套口径
- 现状：`conversation_labels.dart` 已经是"会话排序/取最近"的唯一来源（侧栏 :137-139 就是这么用的），但聊天页为了"左右滑动切角色"又手写了一遍，且少了 pinned 维度。
- 重构动作：在 `lib/utils/conversation_labels.dart` 补 `List<TA> charactersWithChats(AppController)` 与 `Conversation? mostRecentConversationOf(AppController, String taId)`（内部复用 conversationsOfTa）；chat_page 的 308-317、323-341 改成调用，侧栏 124-133 改成调用，两处 `_conversationById` 一行别名删掉直接调 controller。
- 消掉多少重复：角色列表 2 → 1，最近会话 2 → 1，别名 2 → 0
- 风险：最坏是 `mostRecentConversationOf` 从"纯时间最大"变成"pinned 优先 + 时间最大"后，左右滑动的目标会话变了（滑回某个角色时可能落到它置顶的旧会话，而不是刚聊完的）——这其实是更对的行为，但要跟作者确认，别默默改交互。
- 优先级：P2

#### F-11 滚动到底三层包装
- 病灶类型：重复逻辑
- 证据：
  - `lib/pages/chat/state/chat_controller.dart:10-21`：`scrollToBottom()` 内部已有 `addPostFrameCallback` + `animateTo`
  - 调用侧再包一层 `addPostFrameCallback`：`lib/pages/chat/ui/chat_ui_helpers.dart:507-509`、`:669-671`、`:734-739`
  - 第四次"延迟补滚"：`lib/pages/chat/state/chat_state_mixin.dart:140-148`（postFrame + 300ms 各一次）；第五次在键盘回调 `:172-188`
  - 收焦与滚动的组合两份：`chat_ui_helpers.dart:731-745`（_scrollAfterMenu：unfocus + postFrame + 120ms 后再 unfocus）与 `chat_state_mixin.dart:180-187`（键盘收起时 unfocus）
- 现状：同一件"等布局完成再滚到底"，控制器做一次、包装方法做一次、mixin 再补两次；`_scrollToBottom` 有 10 个调用点（send:212/241/326/573、snapshots:165、stream_handlers:79/120、surface:304、mixin:141/146/179）。
- 重构动作：`ChatController` 里加 `scrollToBottomSoon()`（唯一入口，内部 postFrame + animateTo + 必要时重试一次）与 `dismissFocusAndScroll()`（把 _scrollAfterMenu 的收焦序列搬进去）；删掉 3 处外层 `addPostFrameCallback` 包装与 mixin 的 300ms 补滚。
- 消掉多少重复：排帧层级 3 → 1；收焦+滚动组合 2 → 1
- 风险：最坏是去掉 300ms 那次补滚后，长列表首次进入停在中间（item 还在懒建，maxScrollExtent 会变）——`scrollToBottomSoon` 必须保留"重试一次"（可改成在 maxScrollExtent 变化时再滚，而不是固定延迟）。
- 优先级：P2

### 建议落地顺序

1. **F-09**（半天，纯删）——先清残渣，后面所有改动都在干净地基上；顺手让 `flutter analyze` 恢复「有警告=真有问题」。
2. **F-01 + F-03**（P0/P1，动唯一真链路）——先写 payload golden 对比再合并。这两条做完，chat_actions_send.dart 的 604 行能掉到约 330 行。
3. **F-02**（P0，动 UI）——先落 MessageKind 枚举（纯机械、可分批），再拆三个气泡 widget。搜索跳转与「重说/继续说」按钮每步手动回归。
4. **F-05 + F-04**（候选链路，一起做省一次回归）。
5. **F-07**（状态）——只做①②（删死字段 + 删 31 个访问器）风险最低、收益立竿见影；③④⑤留后。
6. **F-06 / F-08 / F-10 / F-11** 按需。

---

### 勘误：F-09 里有三条结论在实施时被推翻（2026-11-23）

本条是「拆分残留」，我照着删的时候核对了一遍，**三条站不住**：

1. **`:2` 与 `:5` 不是死 import。** `chat_page.dart` 只含一个 part：`chat/ui/chat_quick_sidebar.dart`。`ui.` 与 `conversationLabel`/`conversationsOfTa` 的调用点在那个 part 里（`chat_quick_sidebar.dart:139/190/354`），删掉 import 直接编译失败。
2. **18 条 `// ignore: unused_element` 不是过期护栏，全部仍在抑制真实警告。** 去掉后再 analyze，17 条会原样变成 `unused_element` 警告。它们抑制的是一批「在 abstract 声明 + 实现 + 调用点之间跨 mixin」的私有成员，属于 analyze 的已知误报口径，**不要删**。
3. **末尾那 9 行孤儿注释成立**（类确实已搬到 `chat_surface.dart:1385`），`_buildSystemPrompt`（含它那行 ignore）成立，`ChatState.conversation`/`.accent` 两个死字段成立（全库零读写）。

净结果：本批只删了 23 行（孤儿注释 9 + 死方法 12 + 死字段 2 + 一个因此变空的 import 1，含空行抵消），不是原估的「消掉一批护栏」。

**教训**：判断「import 是否死」必须看整个 library（含全部 part），只看声明文件会误判。

## 附录 B：settings 与表单编辑器（8 条，P0×3 / P1×3 / P2×2）

### 结论速览

- 发现 8 条：P0 3 条、P1 3 条、P2 2 条。
- 关于「spec 驱动是不是制造了第二套重复」——**结论是否定的，spec 体系是真被消费的**（逐条核对见第一节）。它是这套代码里目前唯一做到「一处声明、三处消费」的地方，不要回退它。
- 真正在重复的不是 spec，而是 spec **两侧**：① spec 里 `SettingAction` 逃生口长出的手写控件；② 没走 spec 的四个编辑器/策略页各自重写了一遍「折叠行、分组头、校验、脏标记、提交按钮态、编辑器外壳」。
- 任务里列的 `lib/widgets/app_section.dart`(641) **不是设置容器**，是主导航壳（`enum AppSection` 是底栏/抽屉栏目）。它与 `setting_section` 无重叠，也不能合并，详见第三节。

### 一、逐项核查（a：spec 是否真被渲染器消费）

统计方法：对每个 `*_spec.dart` 做全 lib 的 import 反查，并确认入口符号最终落到哪条渲染链路。

| spec 文件 | 行数 | 被 import 处 | 入口类型 | 谁渲染 |
|---|---|---|---|---|
| appearance_display_spec.dart | 404 | settings_tree.dart:33、appearance_display_page.dart:4 | FieldsEntry | SettingsFieldsPage |
| conversation_send_spec.dart | 281 | settings_tree.dart:36 | FieldsEntry | SettingsFieldsPage |
| conversation_summary_settings_spec.dart | 183 | settings_tree.dart:37 | FieldsEntry | SettingsFieldsPage |
| conversation_advanced_settings_spec.dart | 132 | settings_tree.dart:34 | FieldsEntry | SettingsFieldsPage |
| tts_settings_spec.dart | 538 | settings_tree.dart:43 | FieldsEntry ×2（ttsEntry/bgmEntry） | SettingsFieldsPage |
| security_settings_spec.dart | 86 | settings_tree.dart:41 | FieldsEntry | SettingsFieldsPage |
| sampler_settings_spec.dart | 336 | settings_tree.dart:40 | FieldsEntry | SettingsFieldsPage |
| update_settings_spec.dart | 123 | settings_tree.dart:44 | FieldsEntry | SettingsFieldsPage |
| free_image_settings_spec.dart | 86 | settings_tree.dart:39 | FieldsEntry | SettingsFieldsPage |

消费链是闭合且唯一的：

1. 声明 → `settingsTree`/`settingsDetachedEntries`：`lib/pages/settings/spec/settings_tree.dart:97-180`、`:187-191`。
2. 声明 → 页面：`lib/pages/settings/settings_catalog.dart:96-111` `buildSettingsEntryPage` 的 switch 只认 `FieldsEntry`/`CustomEntry`；`FieldsEntry` 交给 `_FieldsEntryHost` 做一次异步能力探测（:150-169），再交给 `SettingsFieldsPage`。
3. 声明 → 字段控件：`lib/pages/settings/spec/settings_fields_page.dart:89-111`（逐 section/逐 item 渲染），sealed 穷尽 switch 在 `:205-212`，写通道在 `:189-199`（`patchSettings` 或 `writeOverride`）。
4. 声明 → 搜索索引：`lib/pages/settings/settings_search_page.dart:76-110` 直接遍历 `settingsTree` + `settingsDetachedEntries`，索引粒度到字段（`item.searchTerms`，settings_spec.dart:212）。

**旧页面确已删除**：`lib/pages/settings/` 下已无 `tts_settings_page.dart`、`security_settings_page.dart`、`conversation_send_page.dart`、`conversation_summary_settings_page.dart`、`conversation_advanced_settings_page.dart`。剩下的只有 4 个 18-19 行的兼容壳（见 F-07），它们内部也只有一行 `SettingsFieldsPage(entry: …)`，不是第二份 UI。

所以「每个 *_spec 与旧 page 共存」这个假设在本仓库不成立。**但 spec 体系有一个真实的漏口**：`SettingAction`（settings_spec.dart:410-426）的 `builder` 是逃生口，非标量设置只能整行自绘，于是「声明文件」里长出手写 StatefulWidget：

- `tts_settings_spec.dart:193-321`（_GlobalSeedSetting，含第 5 份折叠行）、`:324-538`（_ModelDownloadPanel，下载进度/取消/删除/确认弹窗）。
- `conversation_send_spec.dart:76-137`（_MaxParagraphsField）。
- `update_settings_spec.dart:36-84`（_CheckNowTile）。
- `sampler_settings_spec.dart:70-182`（_PresetRow）。
- `appearance_display_spec.dart:27-143`（_AccentColorTile/_AppIconTile）。

tts 的 538 行里约 350 行是手写控件，声明只占 `:67-184`。另有 3 处最典型的「同一件事写三遍」在 `conversation_send_spec.dart:225-240 / 241-256 / 257-270`：三个 `SettingAction` 各包一个 `SettingSwitch`，闭包里手写 `controller.savePromptStrategy(promptStrategy.copyWith(formatX: v))`，三者只差字段名。（这一条与 models/spec 侧审计可能重叠，去重时以本节为准。）

关于 **(b) 表单三件套**：`lib/widgets/form_draft.dart`/`form_fields.dart`/`submit_form.dart` 确实存在，但三个编辑器的采用度是三种：world_editor_form 用了 FormDraft+FormFields（world_editor_form.dart:675-741），ta_editor_form 一个都没用（自己的 7 个 raw controller：ta_editor_form.dart:118-128），oobe 两步表单用的是 `ProviderConfigForm`（oobe_steps.dart:807-829）。`SubmitFormState` 的消费者只有 4 个 island_app 页面，两个编辑器都绕过了它（见 F-03）。

关于 **(c) 四个容器**：只有三个真的存在同职责——`SettingSection`、`DetailSection`、以及散落的私有 `_Section`；`app_section.dart` 是导航壳，不参与。见第二节 F-04 与第三节。

关于 **(d) 长列表/index**：没有「每页自己写一遍 section 列表 + 搜索索引」。设置主页只读 `settingsCatalog`（settings_page.dart:82-90），搜索页只读树（settings_search_page.dart:76-110），折叠由 `SettingSection(collapsible:)` 统一提供（setting_section.dart:46,70,114-120，23 处调用 `SettingSection(` 已验证）。残余重复是「分组头排版」被抄了 11+ 处（F-04）。

关于 **(e) oobe_steps 拆分**：983 行里已经是 5 个独立类簇，切文件边界干净：`StepTracker`+`_StepTrackerItem`+`_StepConnector`（:99-310，215 行）、`OobeStepHeader`（:313-363）、`WelcomeStep`+`_WelcomeLogo`+`_WelcomeFeature`（:369-589，221 行）、`CommunityStep`（:596-745）、`ApiStep`（:748-836）、`ModelStep`（:839-890）、`OobeFooter`（:893-974）、两个 Intent（:976-982）。唯一要顺手收的是四步共用的骨架 `Padding(xl)+Column(stretch)+[header, hLg, Expanded(SingleChildScrollView)]` 抄了 4 份（:381-390、:658-667、:792-806、:867-871），可折成 `OobeStepScaffold`。

### 二、发现清单

#### F-01 策略行组件写两遍
- 病灶类型：重复逻辑
- 证据：`lib/pages/settings/widgets/strategy_field_rows.dart:11`（StrategyEnumRow）、`:67`（StrategyLevelRow）、`:119`（StrategyTriSwitchRow）、`:175`（StrategyTextFieldRow）——全套四个行组件，**唯一消费者**是 `lib/pages/settings/widgets/strategy_override_editor.dart:4`（import）与 `:133`–`:322` 共 25 处调用。
  `lib/pages/settings/prompt_strategy_advanced_page.dart:606-633` 私有 `_enumRow`（与 StrategyEnumRow 逐字相同，仅少 title/底部 8dp）、`:794-843` 私有 `_TriSwitchRow`（与 StrategyTriSwitchRow 逐字相同）、`:846-892` 私有 `_LevelRow`（与 StrategyLevelRow 相同，max 写死 5，调用点 `:463/:469/:475/:481/:505`）；另有 10 个手写 TextField 逐字段接线（`:285-295`、`:335-346`、`:406-429`、`:438-448`、`:519-532`、`:534-560`、`:569-591`），每个都是「`StrategyTextFieldRow` 已实现的那五行 + `onSubmitted: _updateDetails(_d.copyWith(x: _parseX(v)))`」。
- 现状：同一套「策略行」有两份实现，一份公开一份私有，跨文件改一处必然漏另一处。
- 重构动作：把 `strategy_field_rows.dart` 提升到 `lib/widgets/strategy_rows.dart`（四个组件一字不改地搬），`prompt_strategy_advanced_page.dart` 删掉 `_enumRow/_TriSwitchRow/_LevelRow` 三个私有件与 10 个手写 TextField，改为调用共享组件；字段读写接线收成该页内一张 `List<StrategyRow>` 声明表（行 = label + 读 `_d.x` + 写 `_updateDetails(_d.copyWith(x:))`）。
- 消掉多少重复：13 处 → 3 个共享组件 + 1 张声明表。
- 风险：高级页的私有件没有底部 8dp，换共享件后会多出间距，整页高度会变；`_LevelRow` 的 5 档写死与 `StrategyLevelRow.max` 的默认值需确认一致。
- 优先级：P0

#### F-02 折叠行 4 写、折叠体 3 写
- 病灶类型：重复逻辑
- 证据：`lib/widgets/setting_collapsible.dart` 里四个控件各自重抄了同一段「收起态整行」——`:120-144`、`:338-362`、`:497-521`、`:621-645`（Row: Expanded(title) + wMd + FitText(value) + wXs + Icon(expand_less/more)），以及同一段展开体 `:152-212`、`:368-428`、`:522-563`、`:648-697`（AnimatedSize + Padding(l/r md,bottom sm) + Column）。行容器 `_CollapsedHeader` 已经抽出来了（`:708-737`），但它的 child 又被抄了四遍。
  第五份在 `lib/pages/settings/tts_settings_spec.dart:248-320`（_GlobalSeedSetting 自己写 InkWell + Row + chevron + AnimatedCrossFade），第六份是 `lib/widgets/setting_section.dart:144-221`（_CollapsibleSectionBody 的 header/chevron/AnimatedCrossFade）。
  并且这里有一条自相矛盾的注释：`setting_collapsible.dart:148-151` 明确写「刻意不用 AnimatedCrossFade，它会同时构建两个子树」，而 `setting_section.dart:203` 与 `tts_settings_spec.dart:279` 仍在使用 AnimatedCrossFade。
- 现状：一个折叠形态有 6 份实现、2 套动画方案，改观感要改 6 处。
- 重构动作：在 `lib/widgets/setting_collapsible.dart` 内新增 `CollapsibleRow`（= _CollapsedHeader + title/value/chevron，接收 `Widget Function(BuildContext)` 的展开体）与 `CollapsibleBody`（统一的 AnimatedSize 展开/收起）；四个 Collapsible*Setting 只剩「展开体是什么控件」（Slider/TextField/Stepper）；`setting_section.dart` 的 _CollapsibleSectionBody 与 tts 的 _GlobalSeedSetting 改为使用同一对构件。
- 消掉多少重复：6 处 → 2 个构件。
- 风险：`setting_section` 的折叠头是「整行 header + description 在下方」，与数值项的「title/value」布局不完全同构，合并时若强行统一会动设置分组头的观感；AnimatedCrossFade→AnimatedSize 会把「收起时也构建子树」的行为改掉（正是注释想要的方向，但会影响 2 处既有页面的首帧表现）。
- 优先级：P0

#### F-03 编辑器外壳两份，其中一份缺忙态与异常
- 病灶类型：重复逻辑
- 证据：`lib/pages/ta_editor_page.dart:104-166` 与 `lib/pages/world_editor_page.dart:182-267` 是同一个骨架：PopScope(canPop:false)+_handlePop（ta:88-100 / world:168-180）、AppBar actions 里一个 `PopupMenuButton<String>` + `switch (value)`（ta:113-146 / world:192-241）且菜单项都是手写 `Row(Icon, SizedBox(width:8), FitText)`（ta:124-145 / world:206-241）、一个顶栏保存按钮 + 一个 `AppEditorFab` 保存按钮（ta:147-151 + 161-165 / world:242-246 + 259-263）。
  差异是实质性的：ta 的 `_save` 有忙态与 try/catch + 错误 snackbar（`ta_editor_page.dart:46-47,61-86`），world 的 `_save` 没有任何忙态、也没有 try/catch（`world_editor_page.dart:74-90`）——`upsertWorld` 抛异常时直接冒泡，连点还会重复写。
  同时两者都没用现成的 `SubmitFormState`/`FormSubmitButton`（`lib/widgets/submit_form.dart:14-84`，其消费者只有 island_app 的 4 个页面：proxy_config_page.dart:27、points_page.dart:343、server_settings_body.dart:29、tickets_page.dart:296）。
- 现状：编辑器外壳靠复制粘贴演进，两份已经跑偏（一份有失败保护、一份没有）。
- 重构动作：新建 `lib/widgets/editor_shell.dart`：`EditorShell({appBarTitle, menuItems, saveLabel, saving, onSave, onRequestPop, body})`，内部持有 `SubmitFormState` + `FormSubmitButton` + `confirmDiscardEdits`（`lib/utils/action_table.dart:24-32` 已提供确认弹窗）。ta/world/card_publish/world_publish 四个外壳只传参数；菜单项改用已有的 `RowAction`/`rowActionMenu`（action_table.dart:53-194）。
- 消掉多少重复：2 份 106+94 行、4 处菜单项写法、2 处保存按钮对（顶栏+FAB）→ 1 个外壳 + 参数；顺带补齐 world 侧缺失的忙态/异常处理。
- 风险：`_handlePop` 的 canPop 语义与页面内二次确认（world 的 nameError 清空、ta 的 afterSave 清图片）都在外壳里，抽取时容易把「保存成功后才执行的清理」丢掉（ta_editor_page.dart:83）。
- 优先级：P0

#### F-04 分组/卡片头抄 11+ 处
- 病灶类型：可提取组件
- 证据：已有组件 `SettingSection`（`lib/widgets/setting_section.dart:38-138`，图标+标题 titleSmall/onSurfaceVariant+说明）被 23 处调用；但同一形态在别处手写：
  `lib/pages/settings/prompt_strategy_advanced_page.dart:637-690`（私有 `_Section`：Card + Icon(primary,20) + titleMedium + bodySmall 说明）、`:745-788`（私有 `_FoldSection`：同样的卡 + ExpansionTile）。
  `lib/pages/settings/conversation_prompt_strategy_page.dart:135-160`、`:202-227`、`:269-294`、`:393-420`、`:472-499`、`:527-551`（6 张卡，每张 Row(Icon 20, SizedBox 8, FitText titleMedium) + SizedBox 4 + FitText 说明，逐字同形）。
  `lib/pages/world_editor/world_editor_form.dart:248-275`（注释里自己写「做法同 lib/widgets/setting_section.dart」——说明了这是在抄）。
  `lib/pages/ta_editor/ta_editor_form.dart:487-501`、`:551-557`、`:735-741`、`:782-788`（又一种：无图标 + titleLarge）。
- 现状：同一层级语义有三种画法（SettingSection / 私有 _Section 卡 / titleLarge 卡），提示词策略两页完全绕开了已有组件。
- 重构动作：把 `conversation_prompt_strategy_page` 的 6 张卡与 `prompt_strategy_advanced_page` 的 `_Section/_FoldSection` 换成 `SettingSection(icon:, title:, description:, collapsible:)`（后者已支持折叠）；`ta_editor_form` 的 4 张 titleLarge 卡换成 `SettingSection` 并把标题降为同一字号阶；不新建组件。
- 消掉多少重复：11+ 处手写头 → 1 个已存在的组件。
- 风险：`SettingSection` 带 `AppSurface` 底色与固定内边距（setting_section.dart:106-113），直接替换会改掉提示词策略页「白卡 + 16 内边距」的观感，属于视觉回归而非功能回归；建议一页一页换。
- 优先级：P1

#### F-05 脏标记句柄三份
- 病灶类型：重复逻辑
- 证据：三份同构的「表单句柄 + jsonEncode 基线」：
  `lib/pages/world_editor/world_editor_form.dart:23-48`（WorldFormController：current/isDirty/reset + _attach/_detach）、`:108`（_baseline）、`:134`（基线写入）、`:141-143`（_isDirty 比较）；
  `lib/pages/ta_editor/ta_editor_form.dart:33-81`（TaFormController，同样四个方法，基线存在 controller 侧：`:35,39,62,70`）；
  `lib/pages/dialogue_style/dialogue_style_form.dart:11-46`（DialogueStyleFormController，基线用自定义 `_sig`：`:18,27,31-33`）。
  三者的差异纯属漂移：基线存放位置不同、序列化方式不同（toJson vs 手写指纹）。
- 现状：同一个「未保存改动」概念有三套实现，新增编辑器会再抄第四套。
- 重构动作：新建 `lib/widgets/form_handle.dart`：`FormHandle<T>`（_attach/_detach/current()/isDirty/reset(T)/markClean()），基线统一为「序列化函数由使用方注入」；三个 Controller 变成 `class TaFormController extends FormHandle<TA>`，只保留各自特有的方法（如 `afterSave`、`exportViaDialog`）。
- 消掉多少重复：3 份（约 110 行）→ 1 个基类。
- 风险：`isDirty` 是三处外壳「返回时确认」的唯一依据（ta_editor_page.dart:92、world_editor_page.dart:172、dialogue_style_page.dart:81），基线语义若从「jsonEncode」换成「注入序列化」，任何少写字段的 toJson 都会让脏检查静默失效（本仓库已有先例：app_settings_patch.dart:8 记录 loreStickyRounds 在 toJson 写了但 fromJson 不读）。
- 优先级：P1

#### F-06 校验三种做法，其中一种什么都没做
- 病灶类型：状态脏乱
- 证据：（甲）字段级校验走 `FormDraft.validateRequired`：`lib/pages/world_editor/world_editor_form.dart:788-790`、`lib/pages/settings/quick_replies_page.dart:270`、`lib/pages/settings/regex_rules_page.dart:254`、`lib/pages/conversation_create_page.dart:52`。（乙）外壳持有一个 `_nameError` 注入表单：`lib/pages/world_editor_page.dart:72-81,253-257`、`lib/island_app/world_publish_page.dart:329,348,352,406-409`、`lib/pages/identity_editor_page.dart:33,78,197-201`。（丙）什么都没做：`lib/pages/ta_editor/ta_editor_form.dart:562` 与 `:602` 把字段标成必填（`'名字 *'`、`'设定（角色人设，发送给 AI）*'`），但 `lib/pages/ta_editor_page.dart:61-86` 的 `_save` 不做任何校验；角色名必填只存在于社区发布路径（`lib/island_app/card_publish_page.dart:74`）。
- 现状：必填星号是装饰；本地保存能存出空名字的角色，与「世界名称必填」自相矛盾。
- 重构动作：把（乙）的四处「外壳持有 _nameError + 传给表单 + onChanged 清空」统一成 `lib/widgets/field_error.dart` 的 `FieldError` 值对象 + `FieldErrorController`（一处注入、一处清除）；ta 编辑器在 `_save` 里补与 world 相同的必填检查（复用 `FormDraft.validateRequired` 或该值对象）。
- 消掉多少重复：4 处同形 12 行 → 1 处；并补上一个真实缺失的校验。
- 风险：补校验会改变既有用户行为（现在能存空名字的存档/测试可能依赖该行为）；错误文案有 4 种不同措辞（`请填写世界名称` / `请填写世界名称再发布` / `请填写身份名称（必填）。` / `请填写角色卡名称`），统一时会改文案。
- 优先级：P1

#### F-07 四个兼容壳已无人新用 + 迁移状态注释失真
- 病灶类型：状态脏乱
- 证据：`lib/pages/settings/appearance_display_page.dart:11-18`、`update_settings_page.dart:11-18`、`sampler_settings_page.dart:10-17`、`free_image_settings_page.dart:11-18`，四个文件各 18-19 行，正文只有一句 `SettingsFieldsPage(entry: …)`，注释自己写着「新代码请直接用 SettingsFieldsPage」（如 appearance_display_page.dart:9-10）。
  实际调用点：`advanced_settings_page.dart:49`（Update）、`:60`（FreeImage）、`ai_service_settings_page.dart:233` 与 `ai_service_more_page.dart:169`（Sampler）；AppearanceDisplayPage 在 lib 内**零调用**，只被 4 个测试 pump（test/auto_resume_startup_test.dart:174、test/font_scale_effect_test.dart:153、test/font_scale_smoke_test.dart:115、test/font_scale_test.dart:150），FreeImageSettingsPage 同理（test/free_image_crop_test.dart:103,109,131）。
  同类的注释失真：`lib/pages/settings/spec/settings_tree.dart:13-20` 的「迁移状态」写「仍是手写页面：…语音合成、语音输入…」，而语音合成早已是 `FieldsEntry`（tts_settings_spec.dart:67，树里 `:116` 引用），语音输入（STT）整个功能已从应用移除（`lib/services/removed_stt_cleanup.dart:1`）。
- 现状：一个自称「唯一数据源」的文件里，迁移状态清单有两项是错的；四个壳的存在理由只剩测试。
- 重构动作：4 个调用点改为 `SettingsFieldsPage(entry: …)`（或直接 `buildSettingsEntryPage`），3 个测试改为 pump `SettingsFieldsPage`；删除 4 个壳文件（约 76 行）；修正 settings_tree.dart:13-20 的清单（按实际 9 个 FieldsEntry + 3 个 detached 重写）。
- 消掉多少重复：4 个类 → 0；1 处失真注释 → 与代码一致。
- 风险：改测试入口会牵动 7 处测试（4 个字号/启动 + 3 个剪图），若这些测试是「页面级」护栏，替换成 SettingsFieldsPage 后语义仍等价；删壳前必须确认没有外部 import（本次 grep 已确认 lib 内只有上述 4 个调用点）。
- 优先级：P2

#### F-08 ta_editor_form 回填逻辑写两遍
- 病灶类型：重复逻辑
- 证据：`lib/pages/ta_editor/ta_editor_form.dart:155-175`（`_applyTa`：逐字段写 12 个字段 + setState）与 `:461-475`（`_importWithImages` 尾部：同样逐字段写 12 个字段 + setState），两段的字段清单、赋值顺序、trim/toString 处理完全相同（`_taId/_nameController/_gender/_personaController/_introController/_openingController/_tags/_seedController/_authorNoteController/_authorIntervalController/_images/_dialogueStyle/_strategyOverride`），第二段还漏了 `_authorIntervalController` 之外无需处理的 `selectedProvider` 无关项——但**漏了 `_applyTa` 里对 `ta?.authorNoteInterval` 的默认值处理一致性保证**（`:164-165` vs `:471`）。
- 现状：导入回填靠手工复制，字段一增就两边不同步。
- 重构动作：`:461-475` 整段替换为 `_applyTa(finalTA)`（`_applyTa` 已经能接`TA?` 且内部 setState），删掉重复的 12 行赋值。
- 消掉多少重复：2 段各 ~13 行 → 1 段。
- 风险：`_applyTa` 会重置 `_strategyOverride`/`_images`（`:167,171`），导入场景本就期望整体回填，语义一致；但 `_applyTa` 不处理 `_id` 冲突逻辑（在调用方 `:384-408` 已处理），替换顺序不能颠倒。
- 优先级：P2

### 三、不建议做的事（避免为抽象而抽象）

1. **不要合并 `app_section.dart` 与 `setting_section.dart`**。`lib/widgets/app_section.dart:16-24` 的 `AppSection` 是底栏/抽屉栏目枚举，该文件是「胶片式栏目切换」的壳（`:188-233` sectionFlight、`:243-637` AppSectionShell），与设置分组无关。任务描述里「四个容器组件职责重叠」这个假设对这一项不成立。
2. **不要把 `FormDraft` 推广到设置页**。设置是「改了就落盘 + 值在 AppSettings」，编辑器是「草稿 + 显式保存 + 就地校验」，两套写通道不同（这一判断已写在 `lib/widgets/form_draft.dart:5-8`，本次核对认同）。
3. **不要为 `SettingItemSpec` 增加 aliases/关键词字段**。`lib/pages/settings/spec/settings_spec.dart:206-212` 的理由成立：第二份手写别名会与文案漂移。本次未发现「搜不到」的具体案例。
4. **不要把 `SettingAction` 的 5 个自绘控件强行统一**（seed 输入、模型下载面板、强调色磁贴、预设行、检查更新磁贴）。它们彼此不同构，只有生命周期外壳相似；真正需要的是给 `SettingAction` 之外的「非标量设置」补一个受控写法（例如 `SettingSwitch` + `read/write` 钩子，解决 F-01 里 3 处 `copyWith` 样板），而不是把它们塞进同一个 Widget。
5. **`DetailSection` 不建议并入 `SettingSection`**：`lib/widgets/detail_section.dart:11-17` 的两种画法是「内容展示」与「设置项」两种语义，文件头已说明强行统一会改观感；本次核对未发现它与 SettingSection 有调用点重叠。

### 四、边界与未覆盖

- 本轮**只读**：未修改 lib/ 任何文件，未执行 git 写操作，未跑 flutter test/analyze/build。
- 未展开细读（仅结构扫描）：`lib/pages/settings/storage_settings_page.dart`(666)、`about_page.dart`(411)、`open_source_page.dart`(460)、`data_settings_page.dart`(357)、`models/*`(共 4 文件)、`app_icon_page.dart`(210)、`ai_service_settings_page.dart`(305) 与 `ai_service/{simple,advanced}_view`；这些文件里可能有同类的分组头/表单样板，若需要请追加一轮。
- `app_settings_patch.dart`(320) 的 `settingsKeyKinds`(82 条) 与 `applySettingsPatch` 的 82 分支 switch 是「键列表的第二份真相」，与 spec 的 `key:` 声明构成三处对账（另两处是 `AppSettings` 字段与 `copyWith` 参数表）。它位于 lib/models，属 models 审计范围，本次只在此登记、不单独出条，避免与 models 侧重复计数。

---

## 附录 C：island_app 社区端（9 条，P0×2）

### 审计范围与方法

审计对象：`lib/island_app/**`（86 个 dart 文件）。逐个实读了 11 个指定巨型文件与全部 `widgets/`、`utils/` 共享件，横向统计用 grep 做全量计数。

**一个必须先说清的前提**：这个模块在上一轮审计（代码注释里标为"2026-11 审计"）已经建好了七套共享抽象 —— 分页状态机 `lib/widgets/paged_controller.dart`、五态骨架 `lib/widgets/paged_list_body.dart`、三态视图 `lib/widgets/state_views.dart`、触底监听 `lib/island_app/widgets/load_more_list.dart`、卡片网格 `lib/island_app/widgets/responsive_card_grid.dart`、SnackBar 入口 `lib/utils/ui_feedback.dart`、点赞 mixin `lib/island_app/utils/post_like_fav.dart`。

所以本轮结论**不是"缺抽象"**，而是：**抽象建好了，但只被一部分调用点采纳，剩下的仍是手抄副本**。9 条发现里有 6 条的动作是"把已存在的唯一实现接上去"，不需要新建抽象层。

### 发现

#### F-1 ApiClient 是上帝客户端，173 处请求样板可收敛
- 病灶类型：重复逻辑 + 上帝文件
- 证据：
  - `lib/island_app/api/client.dart:214` 单类 `ApiClient` 独占 2146 行；`^  Future<` 开头的公开/私有方法共 101 个（其中 7 个私有前缀 `_`，即 94 个 HTTP 接口方法），横跨 AUTH/SITE/CARDS/COMMENTS/USERS/MY/SEARCH/TICKETS/NOTIFICATIONS/POINTS/ARTICLES/RECOMMEND/TEAHOUSE/REPORTS/PROXY/IMAGEGEN 16 个资源域（分区注释见 `client.dart:106-111`）。
  - 每方法开头的服务器地址守卫整段复制 **75 处**：`client.dart:465-467`、`:512-514`、`:1285-1287`、`:1299-1301`、`:1313-1315`、`:1345-1347`、`:1371-1373`、`:1942-1944`、`:1972-1974`、`:2002-2004`、`:2019-2021` …（全部是 `if (ServerConfig.cachedBaseUrl.isEmpty) {` + `throw Exception('未配置服务器地址');` + `}`）。
  - 响应解包 + 类型校验整段复制 **77 + 50 处**：`final d = data['data'];` 77 处，随后 `if (d is! Map) throw Exception('X响应格式不正确');` 50 处，只有文案里的中文名词不同（`:470` 赞助信息 / `:812` 角色卡详情 / `:1380` 工单列表 / `:1950` 茶馆搜索 / `:2010` 用户搜索 / `:2236` 生图历史 …）。
  - Map 键转 String 的哑操作复制 **37 处**：`d.map((k, v) => MapEntry(k.toString(), v))`（`:471`、`:1294`、`:1308`、`:1322`、`:1335` …）。
  - 分页 record 类型被写了两遍以上：具名 typedef `ExploreCardsPage`（`:43-49`）与 `ArticlesData`（`:77-83`）**形状完全相同**，另有 8 处方法返回签名里内联手打同一个 record（`:1363`、`:1676`、`:1741`、`:1776`、`:1934`、`:1959`、`:1994`、`:2217`）。
  - 单一本地 helper `listOf` 只服务一个方法却写在方法体内：`:2028-2036`（而 `_pageOf` 的等价逻辑在 `:1140-1145` 又写了一遍）。
- 现状：底层传输（`_requestBody` 重试/超时/中止、`_requestJson`）已经抽得很干净，但**每个业务方法的"守卫 → 发请求 → 解 data → 校验类型 → 转 Map"五步流水线全是手抄**，94 个方法 = 94 份。
- 重构动作：
  1. 在 `api/client.dart` 内新增两个私有方法（不新建文件）：`Map<String, dynamic> _dataOf(Map<String, dynamic> raw, String what)` —— 内建 `raw['data']` 解包 + `is! Map` 校验（文案用 `what` 参数拼）+ 键转 String；`void _requireBaseUrl()` —— 统一守卫，由 `_apiUri`（`:1155`）内部调用即可，75 处调用点直接删除。
  2. `({List<Map<String,dynamic>> items, int page, int pages, int total, bool hasNext})` 提成顶层 typedef `PageOfCards`，具名 typedef 与 8 处内联签名全部换成它。
  3. 按资源把 94 个方法拆成 `api/cards_api.dart`、`api/teahouse_api.dart`、`api/tickets_api.dart`、`api/users_api.dart`、`api/imagegen_api.dart` 等 6-8 个子客户端（分区注释已划好边界），共用同一个 `ApiTransport`（就是现在的 `_requestBody`/`_requestJson` 三个方法，搬进 `api/transport.dart` 并公开）。`ApiClient.instance` 保留为聚合门面，转发到子客户端，页面一行不用改。
- 消掉多少重复：75 处守卫 + 50 处解包校验（77 处 `data['data']` 里有 50 处紧跟类型校验，二者是同一段两行，只计一次）+ 37 处键转换 + 11 处分页类型 = **173 处 → 3 处**（`_requireBaseUrl` / `_dataOf` / `PageOfCards`）。
- 风险：`_dataOf` 把"哪种格式错误"的文案统一后，排查日志会失去"哪个接口坏了"的区分度 —— 必须把 `what` 参数带进异常消息，否则排障退步。拆子客户端时 `ApiClient.instance` 的聚合门面若有遗漏方法，页面会编译不过（可控，不会静默坏）。
- 优先级：P0

#### F-2 分页五态接线手写 11 处，绕开已存在的 PagedListBody
- 病灶类型：重复逻辑
- 证据：
  - 共享件早已就位：`lib/widgets/paged_list_body.dart:18` `PagedListBody`（注释自述"2026-11 审计把这套状态机收进了 PagedController，但那之后每个页面仍在手抄同样一段 loading ? LoadingState : error ? ErrorState : empty ? Empty : LoadMoreListView"）与 `:63` `PagedGridBody`。
  - 已采纳（4 处）：`lib/island_app/my_cards_page.dart:162`、`my_collections_page.dart:81`、`notifications_page.dart:198`、`worlds_list_page.dart:236`。
  - 仍手抄同一段（11 处，首屏守卫 `if (X.isLoading && X.items.isEmpty)` 一字不差）：`me_page.dart:991`、`me_page.dart:1098`、`me_page.dart:1166`、`me_page.dart:1223`、`me_page.dart:1409`、`tickets_page.dart:124`、`widgets/comment_section.dart:563`、`image_gen_body.dart:892`、`image_gen_body.dart:1008`、`image_gen_failed_page.dart:87`、`points_page.dart:196`。完整对照可见 `tickets_page.dart:122-179` 与 `me_page.dart:1222-1257`：守卫 3 段 + `ListView.separated` + `itemCount: items.length + (isLoadingMore ? 1 : 0)` + `itemBuilder` 里 `if (index >= items.length) return 尾部 spinner` —— 四段结构完全相同，只有 `itemBuilder` 与分隔线缩进不同。
  - 触底监听同样两套：共享 `loadMoreListener`（`widgets/load_more_list.dart:46`）只被 3 处用（`explore_body.dart:147`、`worlds_body.dart:177`、`comment_section.dart:590`），另 7 处仍手写 `NotificationListener<ScrollNotification>` + `maxScrollExtent - kLoadMoreThreshold`：`home_body.dart:198`、`me_page.dart:1000`、`:1107`、`:1175`、`:1232`、`:1421`、`tickets_page.dart:152`。
- 现状：同一段"五态 + 触底 + 尾条"骨架，4 个页面用组件、11 个页面手抄，且抄的版本已经漂移（`points_page.dart:197` 用 `LoadingState()`，其余 10 处用 `Center(child: CircularProgressIndicator())` —— 前者有规范的居中样式，后者没有）。
- 重构动作：不新建文件。11 处 `_buildXxx(BuildContext)` 全部改成返回 `PagedListBody<T>(controller: _xxxPaged, itemBuilder: …, empty: EmptyState(…))`；`me_page.dart:1013` 的角色卡网格那一处改用 `PagedGridBody`（`sliverBuilder` 里塞已有的 `ResponsiveCardGrid`）；7 处手写监听换成 `loadMoreListener(onReachEnd: …)`。给 `LoadMoreListView`（`load_more_list.dart:79`）补 `physics: AlwaysScrollableScrollPhysics()`，否则短列表在 `AppRefreshIndicator` 下不能下拉。
- 消掉多少重复：11 处五态 + 7 处触底监听 = **18 处 → 2 处**。
- 风险：`me_page` 的 tab 内容是嵌在 `NestedScrollView`/`TabBarView` 里的，`PagedListBody` 返回的是独立 `ListView`，替换时若父级依赖 sliver 结构会导致滚动联动失效（表现为吸顶 TabBar 不再吸顶）。这一处要单独验证，其余 10 处是纯替换。
- 优先级：P0

#### F-3 点赞/收藏 mixin 建了只被 1 个类用，其余 10 处仍内联
- 病灶类型：重复逻辑
- 证据：
  - 抽象存在且注释写明目标：`lib/island_app/utils/post_like_fav.dart:7-8` "抽掉 5~6 处重复的『登录守卫 + API 调用 + SnackBar』"，mixin 在 `:12`。
  - 唯一采纳者：`teahouse_body.dart:57` `with PostLikeFavMixin<TeahouseBody>`。
  - 同一个文件里的另一个状态类就不用了：`teahouse_body.dart:397-412` `_toggleLike` 与 `:414-430` `_toggleFavorite`（`_TeahouseFavoritesPageState`，类定义在 `:330`）—— 与 mixin 的 `_run` 逻辑等价，但自己重写了 `if (!_loggedIn) { _snack('请先登录后再点赞'); return; }` + try/catch + `describeError`。
  - 另外 3 个文件 8 个方法逐字复制同一段：`teahouse_topics_page.dart:195-210`、`:212-228`；`search_page.dart:386-405`、`:407-424`（只多了 `post['id']` 的类型兜底）；`teahouse_post_page.dart:146-162`、`:164-182`、`:197-209`、`:211-226`（同一文件里两对）。
- 现状：一个"登录守卫 + API + 结果回写 + 失败 Snack"的固定八行块，被写了 10 份；其中 2 份就在已经 mixin 了它的那个文件的隔壁类里。
- 重构动作：不新建文件。4 个 State 类都 `with PostLikeFavMixin`，实现 `onPostLikeResult` / `onPostFavoriteResult` 两个回调（`teahouse_body.dart:147`、`:155` 已有现成写法可照搬），删掉各自的 `_toggleLike`/`_toggleFavorite`；调用点从 `_toggleLike(id)` 改成 mixin 的 `togglePostLike(id)`。`search_page` 的 id 解析兜底（`:391-394`、`:412-415`）上移到 mixin 的 `_run` 之前或提成 `_postIdOf(Map)`。
- 消掉多少重复：**10 处 → 2 处**（mixin 的 like/fav 两个方法）。
- 风险：mixin 走 `AuthGuard.run`（`utils/auth_guard.dart`），现有内联版只在 `teahouse_body` 用 `_loggedIn` 直判 —— 两者未登录时的交互（弹登录引导 vs 弹一句 snack）不完全一样，替换会改变用户可见行为，要逐个确认文案。
- 优先级：P1

#### F-4 SnackBar 有唯一入口，island_app 全模块 0 次使用
- 病灶类型：重复逻辑
- 证据：
  - 唯一入口：`lib/utils/ui_feedback.dart:23` `showSnack(context, message)` —— 内部 `clearSnackBars()` + `FitText` + 可配置时长 `_globalSnackDuration`（`:16-21`，由设置项驱动）。主程序调用它 **约 120 处**（`lib/pages/**`、`lib/utils/action_table.dart:268`、`lib/services/startup_update_check.dart:55` 等）。
  - `lib/island_app/**` 对它的调用：**0 处**。取而代之的是 15 个私有 helper + 22 处直接 `ScaffoldMessenger.of(context)`：
    - 15 个 helper：`card_detail_page.dart:709`、`my_cards_page.dart:150`、`worlds_list_page.dart:118`、`image_gen_detail_page.dart:306`、`image_gen_body.dart:151`、`search_page.dart:361`、`proxy_config_page.dart:86`、`profile_edit_page.dart:152`、`widgets/comment_section.dart:475`、`tickets_page.dart:407`、`tickets_page.dart:660`、`teahouse_topics_page.dart:180`、`teahouse_body.dart:130`、`teahouse_body.dart:382`、`teahouse_post_page.dart:520`（`tickets_page` 与 `teahouse_body` 各在自己文件里写了两份）。
    - 无 helper 直接调用的：`home_body.dart:190`、`card_publish_page.dart:53`、`:425`、`:433`、`teahouse_compose_page.dart:87`、`:173`、`:189`、`:195`、`me_page.dart:489`、`:508`、`:521`、`:531`、`notifications_page.dart:117`、`:122`、`root_shell.dart:173`、`swipe_body.dart:120`、`points_page.dart:418`、`server_settings_body.dart:84`、`world_publish_page.dart:128`、`:362`、`world_detail_page.dart:331`、`image_viewer.dart:123`、`save_image.dart:45`、`:52`、`auth_guard.dart:40`、`post_like_fav.dart:51`。
- 现状：同一句"底部提示"，主程序走统一入口（有字号自适应、有时长设置、会先清掉上一条），社区端 37 处各写各的（用 `Text` 而非 `FitText`、时长固定默认值、连续提示会排队堆叠）。`tickets_page.dart:407` 与 `:660` 是**同一文件内的两份副本**。
- 重构动作：不新建文件。15 个私有 helper 的方法体改成 `showSnack(context, msg);`（保留 helper 让 100+ 调用点零改动），22 处直接调用改成 `showSnack(context, …)`，删掉各自的 `ScaffoldMessenger.of` 链。`post_like_fav.dart:49` 与 `auth_guard.dart:40` 直接改成调 `showSnack`。
- 消掉多少重复：**37 处 → 1 处**。
- 风险：`showSnack` 内部会 `clearSnackBars()`，"两条连续提示"的现有行为会变成"后一条顶掉前一条"。少数场景（如评论发布失败后紧接重试提示）可能感知变化。另外 `FitText` 在极窄屏下的折行与原 `Text` 不同。
- 优先级：P1

#### F-5 选图 + MIME 判定 + base64 data URL：7 份 _mimeOf、6 份 _pickImage，而仓库里已有 AttachmentIntake
- 病灶类型：重复逻辑
- 证据：
  - 已有统一实现：`lib/services/attachment_intake.dart:42` `AttachmentIntake`（`pickGallery` `:76` / `pickCamera` `:97` / `pickFiles` `:50` / `_compressImage` `:177` / `_mimeOfName` `:216`），已被主程序 `lib/pages/chat/ui/widgets/chat_input_bar.dart:529`、`:533`、`:556` 使用。**island_app 对它的引用：0 处。**
  - 同一文件内两份逐字节相同的三件套：`tickets_page.dart:335-349` vs `:567-581`（`_pickImage`）、`:351-364` vs `:583-596`（`_mimeOf`）、`:366-376` vs `:598-608`（`_readImage`）。
  - 跨文件同类实现：`teahouse_compose_page.dart:71`（选图）、`:125`（`_mimeOf`）；`widgets/comment_section.dart:270`（选图）、`:259`（mime 判定）；`teahouse_post_page.dart:457-475`（`_readEditImageData` + 内联 mime switch）；`image_gen_body.dart:165`（`pickMultiImage`）、`:203`（`_mimeOf`）；`card_payload.dart:121`（`_mimeOf`）；`profile_edit_page.dart:116`。
  - data-URL 拼接串 8 处：`card_payload.dart:56`、`profile_edit_page.dart:116`、`teahouse_compose_page.dart:119`、`teahouse_post_page.dart:465`、`tickets_page.dart:372`、`tickets_page.dart:604`、`comment_section.dart:264`、`widgets/card_crop_platform_stub.dart:18`。
- 现状：`_mimeOf` 7 份、`_pickImage` 6 份、`'data:$mime;base64,${base64Encode(bytes)}'` 8 份，全都绕过 `AttachmentIntake`；而 `AttachmentIntake` 里连图片压缩（`:177`）都做好了，这些内联实现里只有 `ImagePicker` 的 `maxWidth/maxHeight/imageQuality` 三个神仙参数。
- 重构动作：新建 `lib/island_app/utils/image_data_url.dart`，导出两个函数：`Future<XFile?> pickSingleImage({required int maxSide, required int quality})`（内部调 `AttachmentIntake.instance.pickGallery` 或统一的 `ImagePicker` 参数）、`Future<String?> imageFileToDataUrl(XFile? file)`（内部调 `AttachmentIntake` 已有 mime 判定 + base64）。6 处选图 / 7 处 mime / 8 处拼接的调用点各自缩成一行。
- 消掉多少重复：**21 处 → 2 处**。
- 风险：`AttachmentIntake` 返回的是 `Attachment` 对象（含压缩后的 bytes），与现有代码期望的 `XFile` 形态不同，接口要么适配要么绕过；现有 `maxWidth: 1280 / imageQuality: 82` 的取值如与 `AttachmentIntake` 的压缩策略不一致，上传体积会变，需要确认后端图片上限。
- 优先级：P1

#### F-6 空态 13 处、错误态 6 处手写，绕开 state_views 唯一实现
- 病灶类型：重复逻辑
- 证据：
  - 唯一实现：`lib/widgets/state_views.dart:20` `AppEmptyState`（图标 48 + bodyLarge + bodySmall + 可选按钮 + `compact`）、`:78` `AppErrorState`（`cloud_off_outlined` + 文案 + OutlinedButton 重试）、`:111` `AppLoadingState`。`lib/island_app/widgets/state_views.dart:18-20` 用 `typedef` 保留了 `EmptyState`/`ErrorState`/`LoadingState` 短名，调用点零改造成本。
  - 空态手写成 `Center(child: Text('…'))` 的 13 处：`home_body.dart:267`、`image_gen_body.dart:674`、`:904`、`image_gen_detail_page.dart:446`、`:551`、`search_page.dart:503`、`:689`、`teahouse_body.dart:245`、`:441`、`teahouse_post_page.dart:625`、`teahouse_topics_page.dart:239`、`tickets_page.dart:726`、`widgets/sticker_text.dart:316`。
  - 错误态手写（自己拼 图标+文案+重试按钮，绕开 `AppErrorState`）的 6 处：`card_detail_page.dart:2085-2145`（`_ErrorBody`，60 行，图标 `cloud_off_outlined`、`size: 40`、`Text('加载失败')`、`OutlinedButton('重试')` —— 与 `AppErrorState` 结构完全相同但硬编码尺寸且用 `Text` 而非 `FitText`）、`world_detail_page.dart:388-398`（`Text(_error) + TextButton('重试')`）、`search_page.dart:677-688`（`Text(error) + FilledButton('重试')`）、`image_gen_body.dart:562-573`（`Text(_error) + FilledButton('重试')`）、`image_gen_failed_page.dart:90-104`（`Text + OutlinedButton('重试')`）、`comment_section.dart:566-577`（`Text + FilledButton.tonal('重试')`）。
  - 尺寸/字号因此已经漂移：同一屏里 `tickets_page.dart:138-145` 用 `AppSize.iconEmptyCompact` + `scheme.outline`，`card_detail_page.dart:2115-2121` 用硬编码 `size: 40`，`search_page.dart:663-666` 用 `size: 48`。
- 现状：三态组件的注释明确写着"这里是**唯一实现**…不要再在本文件里新增组件"，但 19 个调用点仍在手写等价结构，且尺寸/字号/按钮层级已经三套取值。
- 重构动作：不新建文件。13 处 `Center(child: Text(x))` → `EmptyState(icon: …, title: x, compact: true)`（图标按语境给，如茶馆 `Icons.forum_outlined`、工单 `Icons.support_agent`）；6 处手写错误态 → `ErrorState(message: x, onRetry: …)`；`card_detail_page.dart:2085-2145` 整个 `_ErrorBody` 类删掉，`:806` 附近的调用点改成把 `SliverAppBar`（带返回键）和 `ErrorState` 一起塞进已有的滚动结构。
- 消掉多少重复：**19 处 → 2 处**（`EmptyState` / `ErrorState`）。
- 风险：`AppErrorState`/`AppEmptyState` 内部是 `Center + Padding(AppInsets.page)`，塞进 `CustomScrollView` 的 `SliverFillRemaining` 才正常；`card_detail_page` 与 `world_detail_page` 的错误态需要顶栏返回键，直接用 `ErrorState` 会丢掉返回路径 —— 这两处必须包一层 `SliverAppBar` 再用，不能裸替换。
- 优先级：P1

#### F-7 单对象加载三件套（_loading/_error/_load）手写 16 份，缺 PagedController 的对称实现
- 病灶类型：状态脏乱 + 重复逻辑
- 证据：
  - 16 个 State 类各自维护 `bool _loading`（其中 11 个还配一个 `String? _error`）+ 自己的 `Future<void> _load()`：`articles_page.dart:321-322`/`:333`、`card_detail_page.dart:373-374`/`:411`、`image_gen_body.dart:46-47`/`:117`、`profile_edit_page.dart:34`/`:61`、`proxy_config_page.dart:31`/`:63`、`punishments_page.dart:82-83`/`:98`、`recommend_page.dart:42-43`/`:54`、`sponsor_body.dart:22-23`/`:37`、`swipe_body.dart:48-51`/`:75`、`teahouse_topics_page.dart:24-25`/`:33`、`tickets_page.dart:525`/`:544`、`world_detail_page.dart:83-88`/`:106`、`server_settings_body.dart:34`/`:51`、`app_drawer.dart`/`:381`、`root_shell.dart`/`:790`、`widgets/sticker_text.dart`/`:267`。
  - 方法体逐行同构：`recommend_page.dart:54-73`、`sponsor_body.dart:37-66`、`world_detail_page.dart:106-127` 三份都是 `setState { _loading = true; _error = null; } → try { await fetch(); if (!mounted) return; setState { data; _loading = false; } } catch (e) { if (!mounted) return; setState { _error = …; _loading = false; } }`。
- 现状：列表型数据已经统一到 `PagedController`（`lib/widgets/paged_controller.dart:54`，含 `isLoading/isLoadingMore/error/loadedOnce/isEmpty` 与"禁止并发、失败不清空"的语义），但**单对象/一次性加载**没有任何对称抽象，16 个页面手工维护同一套三件套，且已经漂移（`recommend_page.dart:70` 存 `'$e'`、`world_detail_page.dart:123` 存 `'详情加载失败：${describeError(e)}'`、`sponsor_body.dart:64` 存 `'$e'`）。
- 重构动作：新建 `lib/widgets/async_controller.dart`，导出 `AsyncController<T>`（与 `PagedController` 同款 API 风格）：`Future<T> Function() fetch`、`bool isLoading`、`String? error`、`Object? errorObject`、`T? value`、`Future<void> load({bool quiet = false})`（`quiet` 保留世界卡导入后的静默刷新语义，对齐 `world_detail_page.dart:139-151` 的 `_refreshQuiet`）。16 个页面把 `_loading/_error/_load` 换成 `late final _ac = AsyncController(fetch: …, onChanged: () { if (mounted) setState(() {}); })`。
- 消掉多少重复：**16 份三件套 + 16 份 try/catch 骨架 → 1 份**。
- 风险：`AsyncController` 与 `PagedController` 会成为两个近亲类，未来容易再长出第三个；必须把"列表用 Paged、单对象用 Async"写进注释并在 `paged_controller.dart` 顶部互相引用，否则下一个人会选错。另外 `_load()` 里有副作用的页面（如 `tickets_page.dart:544-564` 要把 `d['messages']` 拆成列表并重置错误提示、`profile_edit_page.dart:61-82` 要把 7 个字段灌进 TextEditingController 预填表单）不能机械替换，要保留各自的数据落位逻辑。
- 优先级：P1

#### F-8 数字缩写 _fmtCount 4 份、相对时间 2 份，已有 utils 里的唯一实现
- 病灶类型：重复逻辑
- 证据：
  - 数字缩写（≥1 万显示 `x.x万`、≥1 千显示 `x.xk`）4 份：`widgets/card_tile.dart:58-63`、`card_detail_page.dart:1183-1187`（`_fmtCount`）、`card_detail_page.dart:1391-1395`（同一文件里的第二个，叫 `_fmt`，函数体逐字相同）、`swipe_body.dart:429-433`。
  - 相对时间：唯一实现在 `lib/island_app/utils/time_format.dart:2-13` `formatRelativeTime`（已被 `articles_page.dart:217`、`me_page.dart:1144`、`:1511`、`notifications_page.dart:244`、`world_detail_page.dart:533`、`worlds_list_page.dart:253`、`widgets/teahouse_post_tile.dart:93`、`widgets/world_card_tile.dart:45` 共 8 处正确使用），但 `widgets/comment_section.dart:939-950` 的 `_formatTime` 是**逐字节副本**（同样 8 行、同样的 `刚刚/分钟前/小时前/天前/YYYY-MM-DD` 分支），调用点在 `:856`。
- 现状：`time_format.dart` 与 `points_format.dart` 已是既定归口，评论组件却自带一份时间格式化；数字缩写则压根没有归口文件，4 份散在 3 个文件里，其中 2 份在同一文件内。
- 重构动作：新建 `lib/island_app/utils/count_format.dart`，导出 `String formatCount(num? value)`（合并 `card_tile` 的 `dynamic` 入参与另三处的 `int` 入参）；`comment_section.dart:939-950` 整个删掉，`:856` 改调 `formatRelativeTime(c.createdAt)`。
- 消掉多少重复：**6 处 → 2 处**。
- 风险：`card_tile.dart:62` 返回 `n.toStringAsFixed(0)`（对 999.6 会输出 `1000`），另三处返回 `'$n'`（对 double 会输出 `999.6`）—— 统一时必须定死取整策略，否则大数边界显示会变。
- 优先级：P2

#### F-9 公告弹层两套、骨架卡两份
- 病灶类型：重复逻辑
- 证据：
  - 公告弹层：`lib/island_app/root_shell.dart:819-820` `AnnouncementSheet`，注释明写"侧边栏「公告」与首页首启公告共用"；但 `lib/island_app/home_body.dart:438-439` 又定义了一个 `_AnnouncementSheet`，且 `:151` 用的是私有那份。两者结构同构（`SafeArea` → `Row` 内 `Icons.campaign_outlined` + `'站点公告'` 标题 → 可滚动 `Html` → `FilledButton('知道了')`），差异只在 padding（`root_shell` `20,4,20,16` vs `home_body` `24,0,24,16`）、`ConstrainedBox(maxHeight: 0.7 屏)` 有无、以及 `home_body` 多了 `onOpen` 链接回调。
  - 骨架卡：`lib/island_app/explore_body.dart:270-307` 与 `lib/island_app/home_body.dart:336-373` 的 `_SkeletonCard` 逐行相同（同样的 doc 注释"骨架卡片：3:4 封面块 + 两行文字条，用于加载中的占位。"、同样的 `AspectRatio(3/4)` + 96×14 条 + 全宽 12 条）。
- 现状：两处"共用"声明都没有兑现 —— 公告是两份独立实现，骨架卡是两份逐字复制（`_SkeletonCard` 是本轮全模块**唯一**重名的私有类，另一对是语义不同的 `_HeroBanner`）。
- 重构动作：把 `root_shell.dart:820` 的 `AnnouncementSheet` 搬进 `lib/island_app/widgets/announcement_sheet.dart`，补一个可选 `onOpen` 参数与 `maxHeightFraction` 参数，`home_body.dart:438` 整个私有类删掉、`:151` 改引用共享件；把 `explore_body.dart:270` 的 `_SkeletonCard` 搬进 `lib/island_app/widgets/skeleton_card.dart`，两份调用点（`explore_body.dart:258`、`home_body.dart:323`）改引用。
- 消掉多少重复：**4 处 → 2 处**。
- 风险：`home_body` 的公告弹层有"点链接外部打开"的分支，`root_shell` 那份没有；合并时若漏掉 `onOpen`，首页公告里的链接会变成死链。骨架卡的 `AppRadius.sm` 与真实 `CardTile` 的 `kRadiusMd` 本就不一致，迁移时不要顺手改值，否则骨架→真实网格会跳一下。
- 优先级：P2

### 对几个指定"巨型文件"的判断

任务点名要判断 `client.dart` / `card_detail_page.dart` / `me_page.dart` / `search_page.dart` 等是不是上帝文件。逐个给结论：

- `api/client.dart`（2146 行，94 个接口方法）——**是**，且是唯一一个"必须拆"的。见 F-1，拆的是资源子客户端，不是随便切文件。
- `card_detail_page.dart`（2036 行，18 个顶层类：模型 `CardDetail` `:32`、`DialogueTurn` `:243`，页面 `CardDetailPage` `:299` + `_CardDetailPageState` `:371`，12 个纯展示私有 widget `:1091`-`:1981`（`_HeroBanner`/`_ProfileCard`/`_AuthorSection`/`_AuthorAvatar`/`_AuthorStat`/`_ActionsBar`/`_TagsSection`/`_ReviewStatusBadges`/`_AuthorNoteSection`/`_DialogueSection`/`_ChatBubble`/`_SkeletonBody`），再往后 `_ErrorBody` `:2085`、`_CommentsPage` `:2155`）——**是上帝文件，但"拆成 15 个文件"本身不消重复**，不符合本次判据。里面真正的重复只有 `_fmtCount`/`_fmt`（F-8）和 `_ErrorBody`/`_SkeletonBody` 与共享三态/骨架平行（F-6）。**建议不为此开一条重构任务**，只在做 F-6、F-8 时顺手把纯展示 widget 挪到 `card_detail/` 子目录，作为搭车收益。
- `me_page.dart`（1488 行，一个文件里含 `_MePage`、`_UserListPage` 两个 State）——重复集中在 5 份五态接线（F-2），拆文件不是重点。
- `search_page.dart`（1025 行）——真正的问题是 `_resultsShell`（`:650-696`）自己手写了 loading/error/empty 三态（`:674-689`），5 个 tab 都走它，等于一处手写给 5 个 tab 兜底；修 F-6 时把 `_resultsShell` 里三段换成 `LoadingState`/`ErrorState`/`EmptyState` 即可，不需要拆文件。
- `image_gen_body.dart`（979 行）、`widgets/comment_section.dart`（944 行）、`tickets_page.dart`（854 行，一个文件 6 个类）、`world_detail_page.dart`（836 行）、`teahouse_post_page.dart`（830 行）、`root_shell.dart`（797 行）、`image_gen_detail_page.dart`（765 行）——**不是独立病灶**。它们的重复都被 F-2 / F-4 / F-5 / F-6 / F-7 覆盖了；单看行数拆文件只会得到"文件数变多、重复照旧"。

### 建议执行顺序

1. **F-2 + F-6**（纯替换，已有组件，风险最低，一次消掉 37 处手抄骨架）→ 2. **F-4**（37 → 1，同样是纯替换）→ 3. **F-1**（工作量最大，但 173 处样品，值得单独立项）→ 4. **F-3 + F-5 + F-7**（需要新增 mixin 采纳和 AsyncController）→ 5. **F-8 + F-9**（顺手清）。

按各条自上界相加：173 + 18 + 10 + 37 + 21 + 19 + 16 + 6 + 4 = 304 处。**注意这不是精确去重后的净数** —— F-3 消掉的 10 个点赞/收藏块内部本身就含 F-4 要消的 `_snack` 调用，两条有重叠；F-2 的 11 处里也含 F-6 的错误态分支。实际净减少约在 260-300 处之间，量级不受影响。

---

## 附录 D：状态管理与服务层（11 条，P0×4）

### 0. 审计口径

只读审计，未改 lib/ 下任何文件。所有行号来自本次实际读取的文件；计数用 `grep -c` 口径（pattern + 目录 lib/），行区间用逐行读取确认。

审计范围文件规模：

| 文件 | 行数 |
|---|---|
| lib/state/app_controller.dart | 2257 |
| lib/services/storage_usage_service.dart | 988 |
| lib/models/app_settings.dart | 874 |
| lib/models/prompt_strategy.dart | 822 |
| lib/services/data_backup_service.dart | 630 |
| lib/services/llm_service_base.dart | 507 |
| lib/services/conversation_export_import_service.dart | 432 |
| lib/services/ta_export_import_service.dart | 426 |
| lib/services/settings_service.dart | 386 |
| lib/models/app_settings_patch.dart | 320 |
| lib/models/strategy_conflicts.dart | 68 |

服务层样板基线（全部实测计数）：

| 样板 | 出现次数 / 文件数 | 结论 |
|---|---|---|
| `SharedPreferences.getInstance()` | 21 处 / 11 文件 | 已有 SharedPrefs 缓存单例却只被 4 个文件用 |
| `jsonDecode(` | 40 处 / 25 文件 | 无统一 decode 守卫 |
| `jsonEncode(` | 40 处 / 19 文件 | 同上 |
| `path.join(` | 40 处 / 12 文件 | 无统一目录常量 |
| `getApplicationDocumentsDirectory()` | 13 处 / 9 文件 | 同上 |
| `catch (e) {` / `catch (_) {` | 157 / 133 处 | 290 个 catch，其中 14 个是空 `catch (_) {}` |
| 把 `$e` 拼进用户可见文案 | 96 处 | 「XX失败：$e」是事实上的错误协议 |
| `ExportImportResult(success:false, …)` | 28 处 / 9 文件 | 可收敛成一个 guard |
| 平台条件导入三份（*_io/_stub/_web） | 7 组 / 21 文件 / 1314 行 | 见 F-8 |

### 1. app_controller 解剖（问题 a 的正面回答）

### 1.1 它持有什么

10 个实例字段（`lib/state/app_controller.dart:70-82`）：

| 字段 | 行 | 所属领域 |
|---|---|---|
| `_settingsService` / `_openAiService` / `_hiveService` / `_providerRegistry` | 70-75 | 依赖注入的 4 个服务引用（不是状态） |
| `_settings` | 77 | **设置域**：主题 / 字体 / 字号 / 强调色 / 输入栏 / TTS / BGM / 采样参数 / 模型配置 / 社区开关 / 备份开关… |
| `_tas` | 78 | **角色库** |
| `_identities` | 79 | **身份库** |
| `_worlds` | 80 | **世界库** |
| `_conversations` | 81 | **会话库（单聊）** |
| `_groupConversations` | 82 | **会话库（群聊）** |

也就是说：**6 个可变状态、7 个互不相关的领域**（设置 / LLM 配置 / 角色 / 身份 / 世界 / 会话 / 导入导出与备份）被塞进 1 个 `ChangeNotifier`。表面积：**129 个方法/getter 声明**，**99 个 `notifyListeners()` 调用点**。

### 1.2 方法与通知点的领域分布

| 领域 | 行区间 | 特征 |
|---|---|---|
| LLM 配置（providers/models/activeModel/请求组装） | 59-64, 75, 107-170, 251-416, 486-497 | 14 个方法；10 个 notify |
| 设置写入（`saveXxx` 大块） | 293-973 | **69 个方法、69 个 notify**，占全部通知点的 70% |
| 角色/身份/世界 CRUD | 975-1342, 1642-1671 | 15 个方法；10 个 notify |
| 会话 CRUD（含群聊收尾、复制、排序） | 1344-1717, 1674-1687 | 16 个方法；11 个 notify |
| 导出/导入/删除前备份 | 1032-1239, 1719-2231 | 18 个方法；6 个 notify |
| 启动装配 / 清空数据 | 198-248, 2233-2257 | 3 个方法；2 个 notify |

### 1.3 纯转发 getter（字段只在 getter 里转发）

15 个 getter 不改变语义，只把字段吐出来或加一层过滤：`settings`(84)、`openAiService`(85)、`settingsService`(104)、`llmProviders`(173)、`tas`(175)、`identities`(177)、`worlds`(178)、`conversations`(180)、`groupConversations`(182)、`activeTas`(176)、`activeWorlds`(179)、`activeConversations`(181)、`activeGroupConversations`(183)、`tasById`(186)、`allConversations`(195)。

其中 176/179/181/183 是**同一个模板抄 4 遍**（`.where((x) => !x.archived).toList()`），并且每次 build 都新建一份 List。

### 1.4 该拆成哪几个 controller（具体分法）

| 新 controller | 字段范围 | 行区间来源 | 约行数 |
|---|---|---|---|
| `SettingsController`（设置读写 + patch + 平台校正） | `_settings`(77) | 84, 88-101, 104, 223-233, 428-973 中除模型 CRUD 外全部 | ≈600 |
| `LlmProfileController`（providers/models/activeModel/请求组装/legacy 镜像） | 派生自 `_settings` | 59-64, 75, 107-170, 251-290, 293-416, 486-497, 844-856 | ≈260 |
| `LibraryController`（角色/身份/世界） | `_tas`(78), `_identities`(79), `_worlds`(80) | 175-196, 975-1342, 1642-1671, 1698-1717 | ≈420 |
| `ConversationStore`（会话/群聊） | `_conversations`(81), `_groupConversations`(82) | 180-183, 1344-1635, 1674-1687, 1689-1696 | ≈400 |
| `BackupController`（导出/导入/自动备份） | 无自有字段，读上面四个 | 1032-1239, 1719-2231 | ≈720 |
| 保留 `AppController` 作组合根/facade | 只留 4 个引用 + `initialize`/`clearAllData` | 47-82, 198-248, 2239-2255 | ≈120 |

跨域耦合只有 3 条，拆的时候用 facade 转调即可：`deleteTa`→`_pruneTaFromGroups`(991→1000-1030，角色域要改会话域)、`deleteXxxWithBackup`(1136-1239，库域要先走导出域)、`_applyImport`(2092-2231，备份域要整体覆盖库域)。

### 2. 发现

#### F-1 上帝状态对象
- 病灶类型：上帝文件
- 证据：`lib/state/app_controller.dart:70-82`（6 个可变状态同属 7 个领域）；`lib/state/app_controller.dart:88-2237`（129 个方法/getter 声明的跨度，99 个 notify 中有 69 个挤在 293-973 这一段设置写入区）；`lib/state/app_controller.dart:1720-2231`（513 行导出导入也塞在这里）
- 现状：一个 `ChangeNotifier` 同时是设置存储、LLM 配置中心、角色/身份/世界/会话四个仓储、以及备份编排器，78 个 UI 文件都拿它当万能句柄。
- 重构动作：新建 `lib/state/settings_controller.dart`、`lib/state/llm_profile_controller.dart`、`lib/state/library_controller.dart`、`lib/state/conversation_store.dart`、`lib/state/backup_controller.dart`；按 §1.4 的行区间整块搬走；`app_controller.dart` 只留组合根与 3 条跨域转调；78 个调用点改成「只注入自己用得到的那一个」。
- 消掉多少重复：1 个 2257 行上帝对象 → 5 个 ≤720 行的领域对象 + 1 个 120 行 facade；跨域耦合点从「任意方法都能碰任意字段」收敛到 3 条显式转调。
- 风险：拆错领域边界会让跨域联动失效（最典型：`toggleSimpleModelMode` 改设置必须让聊天页换模型）。必须先做 F-6 的分组通知，再搬代码，否则中途界面不刷新。
- 优先级：P0

#### F-2 字段表九份
- 病灶类型：重复逻辑
- 证据：同一份 78 字段的清单在 9 处各写一遍 —— `lib/models/app_settings.dart:17-97`（构造 78 参数）、`lib/models/app_settings.dart:99-175`（`empty()` 73 项）、`lib/models/app_settings.dart:475-558`（toJson 78 键）、`lib/models/app_settings.dart:560-688`（fromJson，84 次 `json['x']` 读取）、`lib/models/app_settings.dart:690-856`（copyWith）、`lib/models/app_settings_patch.dart:37-117`（settingsKeyKinds 78 条）、`lib/models/app_settings_patch.dart:123-296`（switch 79 个 case）、`lib/services/settings_service.dart:165-235`（load：55 个读点）、`lib/services/settings_service.dart:283-373`（save：65 个写点），外加 `lib/services/settings_service.dart:12-80` 的 67 个 pref 键常量。漂移已经发生：`lib/models/app_settings_patch.dart:35` 的注释写「与 copyWith 的参数表逐条对应（82 条）」，实测是 78 条；`lib/models/app_settings_patch.dart:6-7` 断言「`AppSettings.fromJson` 目前没有任何调用点，是一段未被激活的代码」，但 `lib/models/app_settings.dart:866` 与 `871` 就在用它（`clearCustomAccentColor`/`clearTtsGlobalSeed`）。
- 现状：加一个设置项要改 9 处 + 1 个键常量表，注释已经开始记错数字。
- 重构动作：新建 `lib/models/settings_field_spec.dart`，每条 = `(jsonKey, prefKey, kind, defaultValue, clear)` 的 `const List<SettingsField>`；由这一张表驱动三件事：①`applySettingsPatch` 改成查表，②`SettingsService.load/save` 改成遍历表，③`settingsKeyKinds` 直接从表派生（toJson/fromJson/copyWith 保留手写或由表生成，二者取一）。copyWith 保留（类型安全 + 可空清单靠它报错），但增加一个「字段数对账」测试替代手写注释里的数字。
- 消掉多少重复：9 处平行清单 + 67 个键常量 → 1 张表；新增一个设置项的改动点从 9 处降到 1 处。
- 风险：`clearCustomAccentColor`/`clearTtsGlobalSeed`/`dynamicHalfScreen`/`simpleModelMode` 这四个「copyWith 表达不了」的特例必须在表里显式标注，否则置空语义会被表驱动吞掉（`lib/models/app_settings.dart:858-873` 就是为这件事存在的）。
- 优先级：P0

#### F-3 死setter双写
- 病灶类型：重复逻辑
- 证据：`lib/state/app_controller.dart:435-439`（`saveThemeMode`）、`lib/state/app_controller.dart:705-710`（`saveSnackDuration`）、`lib/state/app_controller.dart:760-774`（`saveMessageQuickButtons`）、`lib/state/app_controller.dart:893-903`（`resetAdvancedSampling`）—— 这一族共 **41 个方法、约 244 行（含文档注释）、0 个真实调用点**（检索 `\.saveXxx(` 与不带括号的 tear-off 在 lib/ 下均为空；4 个「命中」只是注释里提到旧名：`lib/pages/settings/conversation_summary_settings_spec.dart:26`、`lib/pages/settings/security_settings_spec.dart:9-10`）。活着的写入口是另一个：`lib/state/app_controller.dart:428-432` `patchSettings` + `lib/pages/settings/spec/settings_fields_page.dart:198`。
- 现状：设置有两套写入口，新的一整套（声明式 patch）已经在用，旧的一整套 41 个 setter 已死但没删，还带着「clamp 在这里做」的错误暗示（如 `lib/state/app_controller.dart:785-790` 的 0..100000 clamp 实际由 spec 的 min/max 承担）。
- 重构动作：删除这 41 个 setter；只保留确实有副作用的 3 个（`saveSnackDuration` 需 `setSnackDuration`、`saveAppIcon` 需换图标、`completeOobe` 需放预置卡），并改造成 spec 的 `writeOverride`（`lib/pages/settings/spec/settings_fields_page.dart:192-196` 已有该通道）。
- 消掉多少重复：41 处「copyWith + save + notify」三段式 → 1 处 `patchSettings`；app_controller 直接瘦 244 行。
- 风险：`saveSnackDuration` 的副作用（`lib/state/app_controller.dart:708`）不能跟着删 —— 删了「提示时长」就变成只存不生效。这也是 F-11 里唯一一个真正不可达的设置项。
- 优先级：P0

#### F-4 采样参数回写
- 病灶类型：状态脏乱
- 证据：`lib/state/app_controller.dart:251-290`（`_syncActiveModelToLegacyFields` 把合并后的采样值**写回** `_settings`）与 `lib/state/app_controller.dart:151-163`（`buildLlmRequest` 又从 `model`/`_settings` **再算一遍**同一个合并规则）是同一规则的两份实现；`lib/state/app_controller.dart:859-871`（`saveSampling` 落盘但**不**回写）与 `lib/state/app_controller.dart:293-298`、`lib/state/app_controller.dart:301-307`、`lib/state/app_controller.dart:348-360`（`toggleSimpleModelMode`/`setActiveModel`/`saveModelConfig` 全部回写）构成不对称；`lib/state/app_controller.dart:287-288` 的 deepseek 两项**无条件**覆盖，而同函数内 7 个采样参数都带 `m.customSamplingEnabled &&` 守卫。
- 现状：`_settings.temperature` 等 9 个字段存的是「激活模型的派生值」而不是用户输入，两条写入路径一条回写一条不回写。
- 重构动作：`LlmProfileController` 里只保留一份 `SamplingParams resolve(LlmModelConfig, AppSettings)`；`_syncActiveModelToLegacyFields` 整体删除，改为请求侧单点解析（`buildLlmRequest` 已是对的），legacy 扁平字段只作为**只读兼容投影**（或不持久化）。
- 消掉多少重复：合并规则 2 处 → 1 处；被镜像的 9 个字段从「持久化的派生值」降级为「运行期投影」，用户值不再被覆盖。
- 风险：最坏是「用户先设全局温度 0.5 → 编辑一次模型卡（`lib/state/app_controller.dart:348-360` → `lib/state/app_controller.dart:251-290`）→ 若该模型开了自定义采样，0.5 被模型值覆盖 → 之后所有非自定义模型都用被覆盖后的值，且没有任何提示或回滚路径」。现状已具备这个链条；本轮只做了静态读取，未跑测试验证用户可感知，若确认可感知应升 P0。
- 优先级：P1

#### F-5 导入骨架三遍
- 病灶类型：重复逻辑
- 证据：`lib/state/app_controller.dart:1789-1854`（`importConversations`）与 `lib/state/app_controller.dart:1973-2033`（`applyConversationImport`）的「先备份 → 拆单聊/群聊 → saveConversations → 造 report」骨架 **61 行里 56 行逐字相同**（PowerShell `Compare-Object` 实测）；第三份同构骨架在 `lib/state/app_controller.dart:2111-2231`（`_applyImport`）；`DataImportReport(` 共 6 处（`lib/state/app_controller.dart` 的 1807、1845、1988、2024、2147、2215），`..._conversations, ..._groupConversations` 的拼接共 13 处（1725-2208 区间）。
- 现状：同一套替换/追加语义写了三遍，改一条规则要同步改三处。
- 重构动作：在 `BackupController` 内抽两个方法：`Future<(String?, String?)> _autoBackupOnce({required bool full})`（现有 `lib/state/app_controller.dart:1077-1100` 直接复用）与 `Future<DataImportReport> _mergeConversations(List<Conversation> incoming, {required bool replaceAll})`；三处调用点改成一行调用 + 各自只保留「入参从哪来」的差异。
- 消掉多少重复：3 处 × ~60 行 → 1 处 ~50 行 + 3 行调用；`DataImportReport` 构造 6 处 → 2 处（全量/仅会话）。
- 风险：三份骨架的「仅追加」去重键不完全一样（`lib/state/app_controller.dart:1821-1827` 与 `lib/state/app_controller.dart:2002-2007` 相同，但 `lib/state/app_controller.dart:2160-2190` 多了 tas/worlds/conversations/identities 四个集合）—— 合并时要把「去重集合」参数化，否则会丢掉身份数据的去重。
- 优先级：P0

#### F-6 通知粒度失控
- 病灶类型：状态脏乱
- 证据：`lib/state/app_controller.dart:1407`（`upsertConversation` → `notifyListeners`，每条消息落盘都会触发）与 `lib/state/app_controller.dart:431`（任何设置项）共用同一个 notifier；订阅方是全量订阅：`lib/pages/world_page.dart:98-103`（世界列表订阅整个 controller）、`lib/pages/my_home_page.dart:128-137`（TA 网格每次通知都重算 `collectTags(all)`）、`lib/pages/settings/spec/settings_fields_page.dart:77-87`（设置页每次通知重建 55 条字段并重新 `settings.toJson()` 一次）。
- 现状：改一个开关和存一条聊天消息是同一个事件；`ListenableBuilder(listenable: controller)` 在 lib 里 24 处，全部是「任一变全都变」。
- 重构动作：先做**低成本版**——在 `AppController` 内用 3 个 `ChangeNotifier` 分域（settings / library / conversations）并把 99 个 notify 拆到对应域；页面把 `listenable: controller` 换成对应域（`lib/pages/world_page.dart:99` → `controller.library`，`lib/pages/settings/spec/settings_fields_page.dart:78` → `controller.settingsNotifier`）。这一步不搬代码就能做，也是 F-1 的前置。
- 消掉多少重复：24 个订阅点从「订阅 1 个全域 notifier」变成「各订阅 1 个域」；设置页重建次数从「任何通知都重建」降到「只有设置变化才重建」，同时省掉每次通知一次的 78 字段序列化。
- 风险：漏改某个订阅方会出现「数据变了界面不刷新」，且这类 bug 只在特定操作序列下出现。必须逐个页面核对，不能靠编译期保证。
- 优先级：P1

#### F-7 单键全量落盘
- 病灶类型：状态脏乱
- 证据：`lib/state/app_controller.dart:428-432`（`patchSettings` 改一个键后调 `_settingsService.save(_settings)`）；`lib/services/settings_service.dart:283-373`（`save()` 内有 **65 个** `prefs.set*/remove` 调用）；对照 `lib/services/settings_service.dart:165-235`（`load()` 55 个读点）。
- 现状：拨一个开关 = 65 次 SharedPreferences 写 + 一次 78 字段序列化；滑杆如果按 `immediate` 存就是每帧 65 次写（`lib/pages/settings/spec/settings_spec.dart:102-111` 的 `SettingsSaveMode` 就是为了绕开这件事而存在）。
- 重构动作：`SettingsService` 增加 `Future<void> saveOne(String prefKey, Object? value)`，由 F-2 的字段表提供 `jsonKey → prefKey` 映射与类型；`patchSettings` 改调 `saveOne`；`save()` 只留给「导入/重置/迁移」这类真正需要全量写的场景。
- 消掉多少重复：单次设置写入 65 次 prefs 调用 → 1 次；`save()` 与 `load()` 的 120 行逐字段代码由表驱动替代（与 F-2 同一处收敛）。
- 风险：`customAccentColor` / `ttsGlobalSeed` 的「置空 = remove」语义（`lib/services/settings_service.dart:316-321`、`lib/services/settings_service.dart:323-327`）要在 `saveOne` 里单独处理，否则清空会写成 null 而不是删键。
- 优先级：P1

#### F-8 平台纯函数双份
- 病灶类型：重复逻辑
- 证据：`lib/services/attachment_storage_io.dart:188-191` 与 `lib/services/attachment_storage_stub.dart:130-133`（`normalizeExt` 逐字相同）；`lib/services/attachment_storage_io.dart:36` 与 `lib/services/attachment_storage_stub.dart:30`（`_refPattern` 同一个正则写两遍）；`lib/services/attachment_storage_io.dart:179-182` 与 `lib/services/attachment_storage_stub.dart:121-124`（`shardOf`）；`lib/services/attachment_storage_io.dart:194` 与 `lib/services/attachment_storage_stub.dart:136`（`isValidRef`）；`lib/services/image_storage_io.dart:80` 与 `lib/services/image_storage_stub.dart:77`（`_normalizeExt`）。且入口文件只是一个条件导出、没有共享接口：`lib/services/image_storage.dart:9-10`、`lib/services/attachment_storage.dart:17-18`。
- 现状：7 组 io/stub/web 三份（21 文件 1314 行）里，与平台无关的纯函数被抄了两遍，两端靠注释「两端必须用同一套规则」（`lib/services/attachment_storage_stub.dart:128-129`）维持一致 —— 这正是会漂移的地方。
- 重构动作：新建 `lib/services/attachment_ref.dart`（`kRefPattern`、`normalizeAttachmentExt`、`shardOf`、`isValidRef`）与 `lib/services/blob_ref.dart`（图片侧同构）；两端 import 同一份；同时各加一个 `abstract interface class`（`AttachmentStoreApi` / `ImageStorageApi`）让两个实现被编译期强制对齐签名。
- 消掉多少重复：4 个纯函数 × 2 份 → 1 份（attachment），1 个 × 2 份 → 1 份（image）；接口签名 2 份 → 1 份。
- 风险：低。唯一风险是 `shardOf` 在 Web 端本无意义（`lib/services/attachment_storage_stub.dart:118-120` 的注释），抽走后要把「Web 没有目录」这条约束保留在注释里，别让人误以为 stub 真的在分片。
- 优先级：P1

#### F-9 偏好存储三套
- 病灶类型：重复逻辑
- 证据：裸 `SharedPreferences.getInstance()` 20 个调用点：`lib/services/settings_service.dart:118,284,377,383`、`lib/services/resume_service.dart:51`、`lib/services/ta_service.dart:22,40`、`lib/pages/chat/chat_snapshot_store.dart:11,31`、`lib/widgets/glass_quality.dart:60,74`、`lib/pages/settings/settings_usage_store.dart:29,56`、`lib/state/app_controller.dart:2240`；已存在的缓存单例 `lib/island_app/shared_prefs.dart:9-33` 只被 4 个 island 文件用（`lib/island_app/app_settings.dart:26,39,50`、`lib/island_app/auth_session.dart:61,97,113`、`lib/island_app/server_config.dart:33,40`）。另有两个**零引用死文件**：`lib/services/conversation_service.dart:7-34` 与 `lib/services/world_service.dart:7-33`（除自身声明外 0 处引用），两者结构逐行相同、只差类型。
- 现状：三套访问方式（裸 getInstance / SharedPrefs 缓存 / 各 store 自建 key + 自建 try-catch），9 个文件各管一段键空间；两个 Hive 之前的遗留服务已完全死掉。
- 重构动作：把 `lib/island_app/shared_prefs.dart` 提升为 `lib/services/key_value_store.dart`（唯一入口 + reject 空 key + 统一异常吞掉 + 可选 TTL），9 个消费方改成注入它；删除 `conversation_service.dart`、`world_service.dart`。
- 消掉多少重复：20 个 getInstance 调用点 → 1 个；`conversation_service`/`world_service` 两份同构 68 行 → 0；pref 键声明散在 9 个文件 → 1 个 key 表（与 F-2 的 prefKey 列合并）。
- 风险：`settings_usage_store` 是使用痕迹、明确不进备份（`lib/pages/settings/settings_usage_store.dart:12-13`），收进统一 store 时不要顺手让它进 `AppSettings`，否则备份会把「最近点过哪页」带到新设备。
- 优先级：P1

#### F-10 存储层越界
- 病灶类型：可提取组件
- 证据：服务在做 UI 文案与格式化：`lib/services/storage_usage_service.dart:64-72`（`storageCategoryLabel` 七个中文分类名）、`lib/services/storage_usage_service.dart:375-379`（「群聊」「N 条消息」「N 段摘要」）、`lib/services/storage_usage_service.dart:664-670`（「合成语音缓存（N 个音频）」「听过的台词，再听不用重新合成」）、`lib/services/storage_usage_service.dart:683`、`lib/services/storage_usage_service.dart:695`、`lib/services/storage_usage_service.dart:710-712`、`lib/services/storage_usage_service.dart:754-759`（「身份数据」「设置数据」「附件索引（网页版）」）；页面在做统计：`lib/pages/settings/storage_settings_page.dart:68-93` 自己在页面里遍历「所有会话 × 所有消息 × 所有附件」构引用集合，`lib/pages/settings/storage_settings_page.dart:123-130` 在清理时**把同一段三层循环再抄一遍**，`lib/pages/settings/storage_settings_page.dart:83` 自己算 `orphanBytes`。
- 现状：文档头写着「只负责算，不负责画」（`lib/services/storage_usage_service.dart:1-4`），实际是「算的要写文案，画的要算统计」，两边都越界；孤儿附件这条统计口径完全不在 report 里。
- 重构动作：①把「引用集合 → 孤儿列表 + 字节」搬进 `AttachmentGc`（`lib/services/attachment_gc.dart` 已有 `findOrphans`/`orphanBytes`，只需加一个收口 `Future<OrphanReport> scan(AppController)` 或接收 `Iterable<Conversation>`）；②把服务里约 20 条中文串与 `formatStorageBytes` 的展示口径搬到页面侧的一个 `storage_usage_l10n.dart`，服务只返回 `StorageUsageItem(name, bytes, noteKind)` 这类可渲染数据。
- 消掉多少重复：三层遍历 2 处 → 1 处（且在服务层）；跨层中文文案 ~20 条从服务里抽出，与页面文案同层。
- 风险：把文案抽到 UI 后，服务的单测断言会从「字符串」变成「枚举/noteKind」，需要同步改测试；若只搬循环不动文案，收益只剩一半。
- 优先级：P1

#### F-11 死状态清单
- 病灶类型：状态脏乱
- 证据：① `lib/services/resume_service.dart:32,58`（`resume_last_opened_at` 只写不读，注释自认「只记录不参与决策」）；② `lib/models/app_settings_patch.dart:39,45,46,47,114,115,116` 声明的 7 个键（`provider`/`baseUrl`/`apiKey`/`selectedModel`/`activeModelId`/`providers`/`models`）在 `applySettingsPatch` 里都有 case（`lib/models/app_settings_patch.dart` 的 125、137、139、141、287-292 共 5 处），但 lib 内**没有任何写入点**；③ `snackDurationMs` 既无 spec 声明、唯一 setter 已死（F-3），实际不可达却仍被读（`lib/state/app_controller.dart:223`）并持久化（`lib/services/settings_service.dart:196-197`、`lib/services/settings_service.dart:314`）；④ `lib/models/app_settings.dart:331-341` 留着 5 段孤立文档注释，描述的 STT 字段早已删除；⑤ 两个死文件见 F-9；⑥ 41 个死 setter 见 F-3。
- 现状：至少 6 类「看起来能用、实际没有入口或没有读者」的状态，其中 `snackDurationMs` 是用户永远改不动的设置，7 个 patch 键是随时会被误用的陷阱。
- 重构动作：① 删 `_atKey` 及其写入；② 7 个无写入点的键从 `settingsKeyKinds`/`applySettingsPatch` 移除（模型配置走 `LlmProfileController` 的专用方法，不走通用 patch）；③ 给 `snackDurationMs` 补一条 spec 声明（带 `writeOverride: (c, v) => c.applySnackDuration(v)`）或删字段；④ 删 `lib/models/app_settings.dart:331-341` 的孤儿注释。
- 消掉多少重复：死状态 6 类 → 0；同时把「patch 能写哪些键」从 78 收敛到 71，剩余键全部有真实调用点。
- 风险：②若将来真要用 patch 写模型配置，需要走 `LlmProfileController` 的专用入口而不是 patch —— 删键前要在注释里写清「为什么这些键不在 patch 里」，否则半年后有人加回来。
- 优先级：P2

### 3. 建议的重构顺序

1. **F-6（分组通知）**：不搬代码，先让 99 个 notify 分成 3 组，24 个订阅点各订一组。是后面所有拆分的前置。
2. **F-3 + F-11**：删 41 个死 setter 与死状态，纯删除，风险最低，app_controller 立刻少 244 行。
3. **F-5**：把导入三份骨架合成一份，仍在 app_controller 内，不牵动 domain 边界。
4. **F-7 + F-2**：先把字段表收成一张，再让 `patchSettings` 走单键写盘。这两条必须一起做，否则表驱动了但写盘还是全量。
5. **F-1**：按 §1.4 拆 5 个 controller，跨域 3 条用 facade 转调。
6. **F-8 + F-9 + F-10**：服务层收敛，与状态层解耦，可并行。

### 4. 未覆盖 / 存疑（留给 Lead 判）

- `lib/models/prompt_strategy.dart`(822) 与 `lib/models/strategy_conflicts.dart`(68) 本轮只做了结构与调用点核查：`strategy_conflicts` 是纯函数、单点定义，无重复；`prompt_strategy` 的 toJson/fromJson 已确认有真实调用点（`lib/services/settings_service.dart:125`、`lib/models/ta.dart:153`、`lib/models/world.dart:87`），未做逐字段往返完备性核查。
- `lib/services/llm_service_base.dart`(507) 与三个 provider（openai/anthropic/zhipu）的流式解析骨架疑似重复（`lib/services/openai_service.dart:104,128`、`lib/services/zhipu_service.dart:127,151`、`lib/services/anthropic_service.dart:242,280` 三处都是「空 key/model 校验 + buildHeaders + chatEndpoint」），本轮未展开，建议归给「网络/LLM 层」那条线。
- F-4 的「用户设置被派生值覆盖」只做了静态推导，没有运行验证；若 Lead 要定 P0 需要补一条能失败的测试。
- 本轮没有统计 475 个 dart 文件的整体重复率，只覆盖 task-4 指定范围。
