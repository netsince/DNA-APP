# 回归审计（v2）：哪些改动是我改坏了用户的设计

> 范围：`HEAD 50c3c4f` 对比当前工作区 —— **117 个文件被改 + 7 新增 + 1 删除**，全部未提交。
> 方法：只读。逐项对照「原实现（`git show HEAD:…`）」与「现实现」；「存在了多久」现场取自 git。
>
> **本版是重写。** 上一版把所有问题并列成「功能退化 / 便利下降 / 纯视觉」，这个框架本身是错的：
> 它默认「我的改动 = 修问题」，把「原设计」当被告。重判之后，多数条目其实是**我的判断越界**，
> 少数才是原设计确实违反规范。

---

## 0. 判据修正：上一版错在哪

| # | 错误 | 具体表现 |
|---|---|---|
| 1 | **把「规范没覆盖」当成「违反规范」** | M3 没有「消息动作排」这种组件，也没有「布局是否随滚动变化」的条文。留白处应由产品判断填，不是被判成缺陷。上一版把 A1/A2 写进「用『手搓控件』替代 M3 既有组件」——那个「既有组件」并不存在 |
| 2 | **把「我改动的代价」记成「原设计的问题」** | 导航按宽度类（B3）原设计确实违反 M3，但「用户肌肉记忆失效」是**我改动的代价**，不该并列在「原行为 vs 现行为」里读成原设计的错 |
| 3 | **把「默认值」当实现细节** | 改 `FitText` 默认值 = 改 750+ 处调用行为，那是产品决策；而这条决策**作者 18 天前已经做过**（见 §4） |
| 4 | **用「顺手统一」当理由** | B 级 9 条里真正需要改的只有 4 条，多出来的都来自「既然在整改就统一一下」——这种改动不需要证据 |

**新判据（本版采用）**

| 处置 | 含义 |
|---|---|
| **R 回滚** | 原设计站得住（规范未覆盖 / 有用户开关 / 有历史与零投诉），是我改坏了 |
| **H 折中** | 原设计有真缺陷，但正确修法是「加一个入口」，不是「删掉原入口」 |
| **K 保留** | 原设计确实违反 M3 或无障碍硬线，改动成立（代价要接受） |
| **U 用户要求** | 你明确要求的改动，不作为回归处理 |

处置分布（117 个改动文件）：**R 15**、**H 1**、**K 6**、**U 1**、**C 60**、**M 27**、**T 8**（另 7 新增 / 1 删除）。

---

## 1. 必须回滚：我改坏的设计（R1–R7）

### R1｜消息气泡快捷动作排：5 → 1

| 项 | 内容 |
|---|---|
| 原行为 | 气泡外一排：**朗读 / 复制 / 重说 / 继续说**（后两者仅最近一条 AI 消息），各有独立显示开关 |
| 现行为 | 只剩朗读；其余进长按菜单，气泡尾多一颗「更多操作」打开**同一个**菜单 |
| 原设计违反 M3 吗 | **不违反，因为 M3 没有这个模式。** 聊天消息的「气泡 + 快捷动作」来自 IM 行业惯例，不是 Material 条文 |
| 存在多久 | `987c207` **2026-08-10** → **98 天 / 13 个 tag**（`v0.2.1-pre1`…`v0.3.7`），期间零改动 |
| 我为什么改错 | 我把「同一批动作两个入口」一律当问题；实际这是**分层**（一眼能点 vs 列表齐全）。那颗按钮打开的就是长按菜单 ⇒ 同一入口复制一份 + 多一次点击 |
| 二次伤害 | 三个设置项语义被偷换成「显不显示那颗按钮」 |
| 证据 | 原：`git show HEAD:lib/pages/chat/ui/widgets/chat_message_list.dart` 416-455、534；现：同文件 442-450 |
| 回滚方式 | 恢复动作排与三个开关原义；长按/右键菜单保留；仅保留命中区 26→48dp 与读屏标签 |

### R2｜半屏 / 全屏的滚动自动切换

| 项 | 内容 |
|---|---|
| 原行为 | 开「半屏聊天」+「滚动时自动全半屏」：滚动向上（含滚轮/触控板）→ 展开全屏；向下或近底 24px → 收敛半屏；「回到底部」也收敛 |
| 现行为 | 自动行为删除，改顶栏手动按钮；设置项标签被改成「顶栏显示展开按钮」 |
| 原设计违反 M3 吗 | **不违反，M3 对此没有规定**；而且它解决的是 M3 不知道的产品问题（看着立绘聊天 / 回看历史用满屏） |
| 存在多久 | `2981891`+`235188d` **2026-08-21** → **87 天 / 9 个 tag**，零返工 |
| 我为什么改错 | 我把「布局变化应由显式操作发起」当成规范，其实那是**我的偏好**；而且两个入口语义不同（自动跟随 vs 手动覆盖），不是打架 |
| 证据 | 原：`git show HEAD:lib/pages/chat_page.dart` 1174-1180 / 1368-1380 / 1418-1430 / 862 |
| 回滚方式 | 恢复三条判定与阈值；`dynamicHalfScreen` 标签回原义；顶栏「半屏/全屏」按钮去掉（它会与滚动打架） |

### R3｜`FitText` 缩字默认值

见 **§4 专章**（这条最严重：推翻了作者 18 天前的明确决定）。

### R4｜编辑器保存入口：FAB → 顶栏文字按钮

| 项 | 内容 |
|---|---|
| 原行为 | 右下 FAB 保存（会话/群聊/身份/世界/对话范例 6 页）；顶栏另有一个 ✓ |
| 现行为 | 只留顶栏文字「保存/创建」 |
| 原设计违反 M3 吗 | **一半**：同一动作两个入口确实是重复主操作（M3 反对）。但正确方向是**留 FAB 删顶栏勾**，我反了 |
| 存在多久 | `AppEditorFab` 自 `c37327c` **2026-09-30** → **47 天 / 9 个 tag** |
| 我为什么改错 | 我只想着「去重」，没考虑可达性：顶栏右上角单手够不到，FAB 一直在拇指区 |
| 回滚方式 | 恢复 FAB 作为唯一保存入口，删顶栏 ✓/文字按钮；或改底部固定操作条 |

### R5｜聊天顶栏动作 3 → 5

| 项 | 内容 |
|---|---|
| 原行为 | 回到底部 / 背景图 / ⋮（3 个） |
| 现行为 | 再加「半屏/全屏」「沉浸」两颗 |
| 原设计违反 M3 吗 | 原设计没问题；**M3 反而建议顶栏动作控制在 2–3 个 + 溢出菜单**，是我的改动更像违规 |
| 存在多久 | 原 3 个动作早于 2026-07-30；新增两颗是本轮 |
| 回滚方式 | R2 恢复后去掉「半屏/全屏」那颗；「沉浸」移入 ⋮ 菜单（配 H1 保留点空白） |

### R6｜探索/世界页筛选条：一行 → 两行

| 项 | 内容 |
|---|---|
| 原行为 | 排序与筛选项在同一行（自绘胶囊，30dp） |
| 现行为 | 拆成「排序行（SegmentedButton）+ 筛选行」，胶囊 40dp |
| 原设计违反 M3 吗 | **一半**：30dp 命中区偏小（该修）；但「排序与筛选混在一排、长得一样」是可用性问题，不是 M3 条文 |
| 存在多久 | 筛选条自 `7eb1413` **2026-10-01**（社区模块合入）→ **46 天 / 9 个 tag** |
| 回滚方式 | **合回一行**（保留形态区分：排序用分段控件、筛选用 chip），**保留 40dp 命中区** |

### R7｜积分明细列宽定死 92dp

| 项 | 内容 |
|---|---|
| 原行为 | `ListTile` + `Row` + `Spacer`（列不对齐，但**永不溢出**） |
| 现行为 | 金额/余额各套 `SizedBox(width: 92)` 右对齐（列齐了，但长数字可能顶出去） |
| 原设计违反 M3 吗 | **不违反**：M3 没有表格组件，「列对齐」是排版偏好 |
| 我的问题 | 我用「好看一点」换来「可能出错」，且**没有验证金额长度上限**（`formatPoints` 不加千分位） |
| 回滚方式 | 改成「最小宽 + 自适应」右对齐，保留等宽数字 |

---

## 2. 折中：H1 沉浸模式入口

| 项 | 内容 |
|---|---|
| 原行为 | 点屏幕上半区空白 → 切换沉浸（顶栏与输入岛一起隐藏）。`0932f21` **2026-08-21**，**87 天 / 9 个 tag** |
| 现行为 | 顶栏按钮进入；沉浸态右上角「退出沉浸」 |
| 原设计违反 M3 吗 | **违反无障碍硬线**：不可见、无语义，读屏与键盘不可达。但「点空白切换」这个手势本身是沉浸式阅读器的通行做法 |
| 正确修法 | **加一个可见入口，而不是删掉热区**：按钮留着（发现性 + 无障碍），热区也还回来 |
| 回滚方式 | 保留顶栏/角落按钮；恢复「点空白切沉浸」；按钮移入 ⋮ 菜单以腾出顶栏空间（见 R5） |

---

## 3. 保留：原设计确实有问题（K1–K4）

### K1｜导航判据：横竖屏 → 宽度类
原实现用 `MediaQuery.orientation == landscape` 决定「底栏 or 260 侧栏」（`HEAD:lib/widgets/app_section.dart` 483-490）。**这是真的违反 M3 自适应指引**：640×360 的手机横屏会被判成宽窗口塞进侧栏。现改为 compact(≤600)/medium(601–839)/expanded(≥840)。
**代价**：601–839 竖屏平板从底栏变侧栏，旧肌肉记忆失效——这是**改动代价**，不是原设计的错（上一版此处归因错了）。
可调项：分界要不要从 600 提到 640，覆盖更多手机竖屏。

### K2｜发送键 38 → 48dp、语音按钮加文字
M3/无障碍要求可点区域 ≥48dp，原 38dp 不达标。代价是输入岛变高约 10–20dp。

### K3｜命中区 30 → 40dp（筛选胶囊）
M3 的 chip 视觉高度可小，但**可点目标应≥48dp**；40dp 是「一行要横排 6–8 个」下的折中，已在注释说明。

### K4｜双栏阈值 900 → 840（生图详情、角色展示）
840 是 M3 expanded 下界，900 是魔法数。**需肉眼验** 840–899 区间是否过挤；挤就回 900。

### U1｜评论区改无限滚动
你本轮明确要求（「无限滚动,给 AppAlpha 扩档,干完」）。原「加载更多」按钮本身合规，不作为回归。

### 3.6 破坏性确认（`delete_confirm_page.dart`）—— **作者决定保留长按 5 秒**

2026-11 我把它改成了「复核页 + error 色按钮 + 确认对话框」。作者评估后认为**长按 5 秒更合适**：
它有"按住不放 + 页面自动滚动供复核"这个组合动作，比对话框更能挡住误触。已**整段还原原实现**
（含两种模式：`requireName=true` 输入名称确认 / `requireName=false` 长按 5 秒），
并在长按按钮上补了 `Semantics(button, label: '删除', hint: '按住 5 秒确认，松开取消')`——
只补语义、不改交互；读屏用户的可达路径仍是「输入名称确认」（设置项 `requireNameToDelete` 默认开启）。

配套：`test/delete_confirm_jitter_test.dart` 恢复（原"长按期间滚动不抖"回归测试），
我写的 `test/delete_confirm_test.dart`（对话框契约）删除。

---

## 4. 专章：`FitText` 缩字（R3）—— 我推翻了作者的决定

### 4.1 时间线（现场取自 git）

| 事件 | 提交 | 日期 | 至今 |
|---|---|---|---|
| 短文本「缩字保单行」引入（≤6 字 + FittedBox） | `db6af1b` feat(ui): 使用 FitText 替换文本组件以自适应字体大小 | **2026-07-30** | **109 天 / 18 个 tag** |
| 作者正面处理「字号真正全局生效」，并新增 `minShrink`（默认 0 = 维持既有行为） | `cb3a0da` fix(排版): 字号真正全局生效 —— 封闭低层渲染逃逸口，并改为系统×应用组合 | **2026-10-29** | 18 天 |

### 4.2 原设计的意图（证据在代码与提交信息里）

* 文件头注释：「文本短于 6 个字时，若因空间不足需要换行，则通过缩小字号保持在单行；6 字及以上保持原生 Text 行为。」
* `minShrink` 注释：「**默认 0 保持既有行为**：全项目 750 余处调用观感不变，**需要的地方再逐个开**。」
* `cb3a0da` 提交信息写明了整套策略：字号改为「系统倍率 × 应用档位」夹在 0.8–2.0；把 `RichText`/`TextPainter` 的逃逸口**封死**（唯一豁免是 `fit_text.dart` 的测量）；**给短标签缩字一个下限，但默认不开**；并新增行为级验收（同段文字在标准/超大两档高度必须增长），还给 smoke 测试加了注记「只证明不溢出，不证明生效」。

> 也就是说：**「字号没生效」这个真问题，作者早已修掉了；短标签缩字是被评估过、并明确决定保留的例外。**

### 4.3 我改成了什么，错在哪

我把默认改成「字号倍率 > 1 时自动启用 0.85 下限」（不再缩字、改为换行），等于：
1. **推翻 `cb3a0da` 的决定**——注释白纸黑字写着「默认 0、逐个开」；
2. 一次性改掉 750+ 处调用行为（改默认值=改全局）；
3. 触发作者自己写的两个验收测试（`font_scale_smoke_test` / `font_scale_effect_test`），我又靠给 `SegmentedButton` 加 `wrapWhenTooNarrow` **打补丁绕过去**——而作者的做法是「把逃逸口封死、只给测量开唯一豁免」。

### 4.4 正确的修法（符合原意图）

* **回滚默认值**：`minShrink` 默认恢复 0（历史行为）；保留 `wrapWhenTooNarrow`（它只服务于显式传 `minShrink` 的场景）。
* **改容器而不是改文字策略**：短标签之所以要缩，是因为容器高度锁死（`AppSize.tileSingle/72`、固定高卡片等）。把这类位置从「定高」改成「最小高」，文字就能既放大又不碎行。
* **需要放大的具体位置逐个开 `minShrink`**——正是作者注释里那句话。

---

## 5. 逐文件覆盖（117 个改动文件，全部归类）

**主题 / 令牌 / 共享组件（12）**

| 文件 | ± | 处置 | 说明 |
|---|---|---|---|
| `lib/theme/tokens.dart` | +104/−2 | M | 新增令牌 |
| `lib/utils/dialogs.dart` | +2/−1 | M | alpha 令牌化 |
| `lib/utils/ui_feedback.dart` | +12/−1 | C | snackbar 兜底 1s→4s |
| `lib/widgets/app_bottom_nav.dart` | +87/−53 | K1 | 目的地元数据（配套） |
| `lib/widgets/app_section.dart` | +96/−27 | K1 | 导航宽度类 |
| `lib/widgets/export_import/conversation_picker_dialog.dart` | +82/−33 | C | 多选列表 dialog→sheet |
| `lib/widgets/export_import/export_options_dialog.dart` | +2/−1 | M | alpha 令牌化 |
| `lib/widgets/fit_text.dart` | +40/−9 | R3 | 缩字默认值 |
| `lib/widgets/liquid_glass.dart` | +5/−2 | M | alpha 令牌化 |
| `lib/widgets/model_picker.dart` | +22/−27 | C | 假 radio→RadioGroup |
| `lib/widgets/setting_collapsible.dart` | +42/−6 | C | 折叠行 48dp＋展开语义 |
| `lib/widgets/setting_section.dart` | +27/−13 | C | 字段页去每组一卡 |

**状态 / 服务 / 模型（3）**

| 文件 | ± | 处置 | 说明 |
|---|---|---|---|
| `lib/models/app_settings.dart` | +17/−2 | M | snackbar 默认值 |
| `lib/services/settings_service.dart` | +3/−1 | M | snackbar 默认值 |
| `lib/state/app_controller.dart` | +11/−12 | C | 排序下标口径＋默认值 |

**聊天（11）**

| 文件 | ± | 处置 | 说明 |
|---|---|---|---|
| `lib/pages/chat_page.dart` | +1851/−1757 | R2 | 半屏滚动自动切换 |
| `lib/pages/chat/actions/chat_actions_inspiration.dart` | +250/−178 | C | 双模态合并成一个 sheet |
| `lib/pages/chat/actions/chat_actions_snapshots.dart` | +88/−34 | C | 存档管理 dialog→sheet |
| `lib/pages/chat/actions/chat_actions_summary_ui.dart` | +98/−6 | C | 编辑摘要 dialog→sheet |
| `lib/pages/chat/builders/chat_stream_handlers.dart` | +43/−2 | C | 失败态可恢复 |
| `lib/pages/chat/state/chat_state_mixin.dart` | +1/−1 | M | alpha 令牌化 |
| `lib/pages/chat/ui/chat_quick_sidebar.dart` | +5/−4 | C | 侧栏把手 28→48dp |
| `lib/pages/chat/ui/chat_ui_helpers.dart` | +168/−111 | C | 菜单分组＋长文编辑→sheet |
| `lib/pages/chat/ui/widgets/chat_app_bar.dart` | +71/−6 | R5/H1 | 顶栏多两颗（回滚）＋沉浸入口（折中） |
| `lib/pages/chat/ui/widgets/chat_input_bar.dart` | +98/−70 | K2 | 48dp 命中区 |
| `lib/pages/chat/ui/widgets/chat_message_list.dart` | +186/−108 | R1 | 动作排 5→1 |

**编辑器 / 表单 / 引导（12）**

| 文件 | ± | 处置 | 说明 |
|---|---|---|---|
| `lib/pages/conversation_create_page.dart` | +149/−108 | R4 | 保存入口 |
| `lib/pages/conversation_edit_page.dart` | +142/−121 | R4 | 保存入口 |
| `lib/pages/delete_confirm_page.dart` | +191/−326 | C | 破坏性确认（§3.6） |
| `lib/pages/dialogue_style_page.dart` | +10/−9 | R4 | 添加范例入口 |
| `lib/pages/dialogue_style/dialogue_style_form.dart` | +3/−4 | M | 删 ignore |
| `lib/pages/group_create_page.dart` | +180/−135 | R4 | 保存入口 |
| `lib/pages/group_edit_page.dart` | +180/−149 | R4 | 保存入口 |
| `lib/pages/identity_editor_page.dart` | +105/−59 | R4 | 保存入口 |
| `lib/pages/oobe/oobe_steps.dart` | +28/−28 | C | 四步去整屏 Card |
| `lib/pages/ta_editor/image_slot.dart` | +3/−4 | M | 删 ignore |
| `lib/pages/world_editor_page.dart` | +11/−3 | R4 | 保存入口 |
| `lib/pages/world_editor/world_editor_form.dart` | +93/−76 | C | 去卡＋nameError＋initialValue |

**主页面 / 列表（8）**

| 文件 | ± | 处置 | 说明 |
|---|---|---|---|
| `lib/pages/group_home_page.dart` | +9/−14 | C | 空态换共享组件 |
| `lib/pages/home/home_widgets.dart` | +34/−40 | C | 空态＋菜单项＋onReorderItem |
| `lib/pages/identity_page.dart` | +9/−13 | C | 空态换共享组件 |
| `lib/pages/my_home_page.dart` | +3/−5 | C | onReorderItem |
| `lib/pages/my_home/tag_filter_bar.dart` | +3/−2 | C | ChoiceChip→FilterChip |
| `lib/pages/settings_page.dart` | +45/−20 | C | 设置主页去每组一卡 |
| `lib/pages/ta_showcase_page.dart` | +71/−54 | K4 | 双栏 840＋TabBar |
| `lib/pages/world_page.dart` | +3/−5 | C | onReorderItem |

**设置区（25）**

| 文件 | ± | 处置 | 说明 |
|---|---|---|---|
| `lib/pages/settings/about_page.dart` | +2/−3 | M | alpha 令牌化 |
| `lib/pages/settings/advanced_settings_page.dart` | +3/−3 | M | alpha 令牌化 |
| `lib/pages/settings/ai_service_more_page.dart` | +0/−1 | M | 删 ignore_for_file |
| `lib/pages/settings/ai_service_settings_page.dart` | +56/−11 | C | ⋮ 打开整页→就地菜单 |
| `lib/pages/settings/ai_service/advanced_view.dart` | +9/−18 | C | 空态换共享组件 |
| `lib/pages/settings/ai_service/simple_view.dart` | +2/−2 | M | alpha 令牌化 |
| `lib/pages/settings/app_icon_page.dart` | +64/−34 | C | 单列→响应式网格 |
| `lib/pages/settings/appearance_display_spec.dart` | +6/−3 | R2 | dynamicHalfScreen 标签回滚原义 |
| `lib/pages/settings/authors_page.dart` | +1/−1 | M | alpha 令牌化 |
| `lib/pages/settings/conversation_prompt_strategy_page.dart` | +8/−9 | M | alpha 令牌化 |
| `lib/pages/settings/data_settings_page.dart` | +13/−2 | C | 破坏性动作强调 |
| `lib/pages/settings/models/model_edit_page.dart` | +3/−2 | M | value→initialValue |
| `lib/pages/settings/models/model_list_body.dart` | +18/−27 | C | 空态＋Radio 迁移 |
| `lib/pages/settings/models/model_list_page.dart` | +0/−1 | M | 删 ignore_for_file |
| `lib/pages/settings/models/model_sampler_settings_page.dart` | +0/−1 | M | 删 ignore_for_file |
| `lib/pages/settings/models/provider_edit_page.dart` | +6/−6 | M | value→initialValue |
| `lib/pages/settings/models/provider_list_body.dart` | +6/−20 | C | 空态换共享组件 |
| `lib/pages/settings/models/provider_list_page.dart` | +0/−1 | M | 删 ignore_for_file |
| `lib/pages/settings/prompt_strategy_advanced_page.dart` | +72/−23 | C | 预览 dialog→sheet |
| `lib/pages/settings/quick_replies_page.dart` | +156/−82 | C | 表单 dialog→sheet＋就地校验 |
| `lib/pages/settings/regex_rules_page.dart` | +150/−71 | C | 同上＋onReorderItem |
| `lib/pages/settings/settings_search_page.dart` | +15/−11 | C | 结果卡→列表行 |
| `lib/pages/settings/spec/settings_fields_page.dart` | +33/−23 | C | RadioGroup＋下拉 initialValue |
| `lib/pages/settings/tts_cache_page.dart` | +5/−1 | C | 「确认清空」改 error 语义 |
| `lib/pages/settings/update_dialog.dart` | +2/−3 | M | alpha 令牌化 |

**社区 lib/island_app（38）**

| 文件 | ± | 处置 | 说明 |
|---|---|---|---|
| `lib/island_app/appearance_settings_body.dart` | +95/−23 | C | 取色器 dialog→sheet |
| `lib/island_app/card_detail_page.dart` | +113/−119 | C | 评论 sheet→独立页＋小标签收口 |
| `lib/island_app/explore_body.dart` | +112/−132 | R6/K3 | 筛选条拆行回滚；命中区保留 |
| `lib/island_app/home_body.dart` | +12/−11 | C | 骨架屏列数同构 |
| `lib/island_app/image_gen_body.dart` | +1/−1 | M | alpha 令牌化 |
| `lib/island_app/image_gen_detail_page.dart` | +3/−2 | K4 | 双栏 840 |
| `lib/island_app/me_page.dart` | +71/−56 | C | 失败态＋世界行＋菜单项 |
| `lib/island_app/my_cards_page.dart` | +90/−100 | C | 去每行一卡＋标签收口 |
| `lib/island_app/my_collections_page.dart` | +8/−0 | C | 失败态 |
| `lib/island_app/notifications_page.dart` | +7/−1 | C | 加版心 |
| `lib/island_app/points_page.dart` | +67/−37 | R7 | 列宽定死 |
| `lib/island_app/proxy_config_page.dart` | +1/−1 | M | alpha 令牌化 |
| `lib/island_app/punishments_page.dart` | +62/−59 | C | 去卡＋错误种类 |
| `lib/island_app/recommend_page.dart` | +2/−2 | M | alpha 令牌化 |
| `lib/island_app/root_shell.dart` | +67/−59 | C | 顶栏手搓 tab→TabBar＋宽度类 |
| `lib/island_app/search_page.dart` | +174/−155 | C | 手搭 tab→TabBar＋排序收敛 |
| `lib/island_app/server_settings_body.dart` | +4/−2 | M | alpha 令牌化 |
| `lib/island_app/server_setup_page.dart` | +4/−2 | M | alpha 令牌化 |
| `lib/island_app/settings_body.dart` | +5/−2 | M | alpha 令牌化 |
| `lib/island_app/sponsor_body.dart` | +5/−5 | M | alpha 令牌化 |
| `lib/island_app/swipe_body.dart` | +5/−5 | M | alpha 令牌化 |
| `lib/island_app/teahouse_body.dart` | +35/−17 | C | 排序收敛＋阈值集中 |
| `lib/island_app/teahouse_compose_page.dart` | +28/−7 | C | 校验改 errorText |
| `lib/island_app/teahouse_post_page.dart` | +20/−4 | C | 加版心 |
| `lib/island_app/teahouse_topics_page.dart` | +6/−14 | C | 错误文案人话化 |
| `lib/island_app/tickets_page.dart` | +61/−45 | C | 去卡＋气泡宽度封顶 |
| `lib/island_app/widgets/card_tile.dart` | +18/−50 | C | 小标签→StatusBadge |
| `lib/island_app/widgets/comment_section.dart` | +56/−41 | U1 | 无限滚动（用户要求） |
| `lib/island_app/widgets/load_more_list.dart` | +54/−0 | C | 统一分页判定 |
| `lib/island_app/widgets/plus_hub.dart` | +1/−1 | M | alpha 令牌化 |
| `lib/island_app/widgets/report_sheet.dart` | +18/−24 | C | 手搓 radio→RadioListTile |
| `lib/island_app/widgets/responsive_card_grid.dart` | +83/−21 | C | 列数算法收口 |
| `lib/island_app/widgets/teahouse_post_tile.dart` | +152/−70 | C | 统计行 48dp＋去描边卡＋点赞色 |
| `lib/island_app/widgets/world_card_tile.dart` | +25/−73 | C | 状态徽章只读＋收口 |
| `lib/island_app/world_detail_page.dart` | +4/−2 | C | 无回调 Chip→只读徽章 |
| `lib/island_app/world_publish_page.dart` | +73/−8 | C | 校验改字段错误条 |
| `lib/island_app/worlds_body.dart` | +75/−136 | R6/K3 | 筛选条拆行回滚；瀑布流保留 |
| `lib/island_app/worlds_list_page.dart` | +14/−22 | C | 标签→StatusBadge |

**测试（8）**

| 文件 | ± | 处置 | 说明 |
|---|---|---|---|
| `test/ai_service_page_render_test.dart` | +13/−11 | T | 测试同步 |
| `test/app_editor_frame_test.dart` | +23/−14 | T | 测试同步 |
| `test/app_section_test.dart` | +79/−0 | T | 测试同步 |
| `test/delete_confirm_jitter_test.dart` | +0/−108 | T | 测试同步 |
| `test/fit_text_shrink_test.dart` | +142/−49 | T | 测试同步 |
| `test/ta_gender_test.dart` | +11/−5 | T | 测试同步 |
| `test/ta_showcase_test.dart` | +16/−5 | T | 测试同步 |
| `test/ta_tag_filter_test.dart` | +5/−2 | T | 测试同步 |

### 新增（7）

| 文件 | 性质 |
|---|---|
| `docs/MATERIAL_DESIGN_AUDIT.md` | 规范审计文档 |
| `docs/REGRESSION_AUDIT.md` | 本文（v2） |
| `lib/island_app/widgets/status_badge.dart` | 新增只读标签组件（替代 5–6 套私有实现） |
| `lib/island_app/widgets/world_list_tile.dart` | 新增紧凑世界行 |
| `test/status_badge_test.dart` · `test/card_grid_metrics_test.dart` · `test/delete_confirm_test.dart` · `test/reorder_semantics_test.dart` | 新增测试（共 22 条） |

### 删除（1）

| 文件 | 原因 |
|---|---|
| `test/delete_confirm_jitter_test.dart`（−108） | 被测机制（长按 5 秒）已移除，由 `test/delete_confirm_test.dart` 顶替新契约 |

---

## 6. 复核命令

```powershell
git show HEAD:<文件>                                   # 原实现
git diff -w -- <文件>                                  # 真实改动（chat_page.dart 必须 -w）
git log --oneline --date=short --pretty='%h %ad %s' -S '<关键字>' | Select-Object -Last 3
git for-each-ref --sort=creatordate --format='%(creatordate:short) %(refname:short)' refs/tags
git show --stat cb3a0da                                # 作者那次「字号真正生效」的提交
```

---

## 7. 回滚清单（已执行）

| 编号 | 回滚内容 | 状态 |
|---|---|---|
| R1 | 恢复消息气泡动作排（朗读/复制/重说/继续说）+ 三个开关原义 | ✅ 已回滚（保留 48dp 命中区与读屏标签） |
| R2 | 恢复滚动自动半屏/全屏（滚轮 + 滚动方向 + 近底 24px 三条判定）＋ 设置项标签回「滚动时自动全半屏」 | ✅ 已回滚 |
| R3 | `FitText` 默认值恢复 0（缩到装下为止）；`wrapWhenTooNarrow` 保留，仅服务于显式传 `minShrink` 的定宽布局 | ✅ 已回滚 |
| R4 | 编辑器保存回右下 FAB（7 处：会话/群聊/身份/世界/对话范例） | ✅ 已回滚（顶栏不再放同一个动作） |
| R5 | 聊天顶栏回到 3 个动作；沉浸收进 ⋮ 菜单 | ✅ 已回滚 |
| R6 | 探索/世界页筛选条合回一行（控件换型与 40dp 命中区保留） | ✅ 已回滚 |
| R7 | 积分金额列改「最小宽 72 + 自适应」，长数字可撑开、不裁切 | ✅ 已回滚（等宽数字保留） |
| H1 | 沉浸：⋮ 菜单入口 + 沉浸态退出按钮 + **点上半区空白** 三者并存 | ✅ 已回滚 |

**保留未回退的改动**（这些不构成退化）：
触摸目标 ≥48dp；读屏标签与 `Semantics`；失败态可恢复（行内错误条 + 重试）；空态/错误态收敛；`StatusBadge` 与状态映射收口；`TabBar` 替换手搓 tab；导航按宽度类；分页规则收口；令牌化（`AppAlpha`/`AppRadius`/`AppBreakpoints`）；去「每组一卡/每行一卡」；破坏性动作 error 语义；`onReorderItem` + 下标口径修正。

**测试同步**（都按新契约改，不是删断言换绿）：
`test/fit_text_shrink_test.dart`（断言改回「默认缩字 / 显式 minShrink 才换行 / 定宽布局可退出换行」）、
`test/app_editor_frame_test.dart`（断言 FAB 存在、顶栏无保存按钮）。

**补充（同一轮）**：排序/筛选控件的命中区统一到 40dp —— 去掉 `teahouse_body`、`comment_section`、`search_page` 三处 `SegmentedButton` 的 `visualDensity: compact`（compact 会压到 36dp，与探索/世界页的 40dp 不一致）。**再修订（密集控件例外）**：把「触摸目标 ≥48dp」当成「把控件做成 48dp」是我第二次误解规范——气泡动作排 26→48（面积 +240%）、帖子统计行 21→48（每条帖子行高翻倍）被作者判为「按钮太大」。已按 `docs/DESIGN_SPEC.md` §7.2 的**密集控件例外**回滚：气泡动作排与朗读球回 **26（图标 15）**、帖子统计行回 **21（图标 17 + Padding(4,2)）**、角色卡底部两颗回 **40（compact）**、帖子/评论输入区图标回 **40（compact）**、代理页复制回 compact。**保留 48 的**：独立图标按钮、文本按钮（40 视觉 / 48 命中）、所有破坏性动作。

**验证**：`flutter analyze --no-pub lib test` 无 issue；`flutter test --no-pub --exclude-tags live` **846 通过 / 2 跳过**。
**提交状态**：未提交（HEAD 仍 `50c3c4f`）。
