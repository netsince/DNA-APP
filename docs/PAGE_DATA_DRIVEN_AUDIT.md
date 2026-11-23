# 页面数据驱动改造统计（v1）

> 只读审计：**没有改动任何业务代码**。基线 `release/0.4.0`，2026-11-16。
> 数字全部现场统计（行数、4 行片段重合度、grep 计数），标注"已核实"的都跑过命令。

## 0. 三句话结论

1. 设置区那条路已经跑通：**11 个 `*_spec.dart`、3247 行**描述数据，取代了手写页面（先例 `appearance_display_spec` 396 行替掉 604 行手写页）。
2. 但**现有词汇表一个编辑器需要的字段都没有**——`settings_spec.dart` 只有开关/单选/整数/小数/动作/说明六种，**没有自由文本、没有实体选择器、没有集合、没有校验钩子**（已核实：该文件里 `TextField` 出现 0 次）。所以"适合"指的是**要先补描述符**才适合。
3. 第一个该做的既不是页面渲染器，也不是编辑器——是两件更底层的东西：**分页列表控制器**（16 个文件各手写一份五态状态机）和**动作表**（导出/导入 3 处、编辑器外壳 5 处、每行菜单随状态变）。再往下才是页面。

## 0.1 进度表

> 这张表才是「现在做到哪」的唯一入口；下面的 §5 顺序表是**原始计划**，别拿它当进度看。

| 项目 | 状态 | 落点 | 备注 |
|---|---|---|---|
| 删零引用死文件 | ✅ | `bbc8293` | 2 个文件、349 行；`appearance_settings_body` 与 `settings_body` |
| 分页列表控制器 | ✅ | `lib/widgets/paged_controller.dart`（165 行）+ 12 条测试 | 审计时 16 个手写状态机的文件已全部换掉；18 个页面在用 |
| 分页阈值收口 | ✅ | 同上 | 9 处裸 `maxScrollExtent - 400` + 2 处 `extentAfter < 200/300` 已清 |
| 表单共享层 | ✅ | `form_draft`（77）+ `form_fields`（244）+ `form_sheet`（95） | 8 个文件在用 |
| 编辑器第一批（会话×2 / 群聊×2 / 快速回复 / 正则 / 词条弹窗） | ✅ | `535cfbc` | 前六个净减 419 行；词条弹窗为保观感 +61 行 |
| 动作表 | ✅ | `lib/utils/action_table.dart`（285 行）+ 3 条测试，`81565db` | 导出/导入 3 处、放弃确认 5 处、行内菜单 2 处；10 个文件在用 |
| 列表项模板（五态骨架） | ✅ | `lib/widgets/paged_list_body.dart`（108 行） | 四页全部换完：我的卡、我的收藏（网格）、通知、我的世界卡；顺带修掉通知页的**双版心缩进**（宽屏被缩两次，1200 宽时内容只剩约 320px） |
| 详情区块（`DetailSectionSpec`） | 🚧 2/3 | `lib/widgets/detail_section.dart`（163 行） | 卡片详情 ✅（6 个区块，其中 3 个 `custom`）、角色展示 ✅（4 个区块）；**世界详情保持原样**——它的头卡是「状态横幅 + 名称 + 统计 + 简介 + 标签 Wrap + 作者行」的不规则组合，两种 style 都套不上，套了就是改观感 |
| 动作表剩余同类 | ✅ | 同上（`action_table.dart` 扩到 3 种项样式） | 七处全部换完：卡片详情、评论回复、世界详情、聊天顶栏（9 项含勾选/禁用）、世界列表、会话列表、群聊列表（归档两套表 → 一张表 + `visible` + `dividerAfter`）。共享层新增 `icon / child / iconSize / iconGap / itemStyle(listTile · listTilePadded · listTileRegular) / checked / dividerAfter / per-item 覆盖` |
| 表单 + submit 描述符 | ✅ | `lib/widgets/submit_form.dart`（118 行）+ 5 条测试 | 代理配置（草稿 + 3 字段 + 提交 + 就地错误横幅）、服务器地址（保留已是共享件的 `ServerAddressForm`，只接草稿与提交状态）、工单新建、积分兑换。`FormTextField` 顺带补了 `focusNode` / `obscureText` / `suffixIcon` / `maxLength` |
| 异常显性化（配套，非本审计项） | ✅ | `utils/error_display.dart` + `DESIGN_SPEC.md` §7.3 | 49 处「失败，请重试」改成「前缀：真实原因」 |

**口径更新**：§5 的待办顺序表已全部执行完毕（死文件 → 分页控制器 → 动作表 → 编辑器第一批 → 列表项模板 → 详情区块 → 动作表剩余同类 → 表单+submit）。

**结项说明**（2026-11-20）：

- 本审计的改造项到此为止，剩下的两条都是**书面决定的例外**，不是待办：
  1. `swipe_body`（刷一刷）：批次语义 + PageView 预取，不套 `PagedController`（原因写在文件头注释里）；
  2. **V2 主页**：作者决定不做。占位页与设置链路已在 `d13c567` 撤掉，相关文档不再保留计划。
- 以后再要动页面结构，先看 §0.1 这张表；新加的共享件（分页控制器 / 列表骨架 / 动作表 / 表单与草稿 / 提交态 / 详情区块）已经有测试守着，改它们比改页面便宜。

---

## 1. 现状基线

### 1.1 已有的声明式面

| 位置 | 规模 | 管什么 |
|---|---|---|
| `pages/settings/*_spec.dart`（10 个） | 2846 行 | 外观/对话/摘要/采样/TTS/安全/更新/自由剪图（`voice_input` 随 STT 移除） |
| `settings/spec/settings_spec.dart` | 547 行 | 6 种字段：Toggle / Choice / Int / Double / Action / Info |
| `settings/spec/settings_fields_page.dart` | 548 行 | 字段树渲染器 |
| `settings/spec/settings_tree.dart` | 180 行 | 分组 + 入口表 |

### 1.2 已有的共享件（不是从零开始）

- `widgets/app_editor_frame.dart`：编辑器外壳，**11 个页面**在用
- `SectionPageData`（`widgets/app_section.dart`）：栏目装配已是三个 builder 的声明式
- `island_app/widgets/state_views.dart`：空/错/载态，**15 个文件**在用
- `responsive_card_grid.dart` + `card_grid_metrics`：网格列数已收口
- `load_more_list.dart`：只收了**阈值和监听**，没收状态机

### 1.3 重复的硬证据

**页面级孪生**（4 行片段重合度）：

| 页面对 | 重合片段 | jaccard |
|---|---|---|
| `group_create` ↔ `group_edit` | 178 / 352 | **0.51** |
| `conversation_create` ↔ `conversation_edit` | 131 / 313 | **0.42** |
| `teahouse_body` ↔ `teahouse_topics_page` | 107 / 579 | 0.18 |
| `quick_replies` ↔ `regex_rules` | 63 / 590 | 0.11 |

**横向重复**（已核实计数）：

| 东西 | 复制份数 | 规模 |
|---|---|---|
| 分页状态机（`_noMore` / `_loadingMore`） | **16 / 17 个文件** | 每份 30–40 行 |
| 手写实体选择器 `DropdownButtonFormField` | **10 个**（conversation×3+3、group×2+2） | 每个 25–50 行，合计 ≈350 行 |
| 私有 `_section()` 分组头 | **6 个文件** | 每份 25–30 行，≈170 行 |
| 「放弃修改？」+`PopScope` 外壳 | **5 个文件** | 每处 ≈30 行 |
| `_revealFirstError` 滚回第一个错误 | **5 个文件** | 每处 15–20 行 |
| 底部 sheet 表单骨架 | 2 份逐字同构 + 1 个变体（world 词条弹窗） | 137 / 132 / 420 行 |
| 导出·导入 UI 接线 | 3 处（identity / world_editor_page / ta_editor_form） | 100–200 行/处 |
| 裸写阈值 | `maxScrollExtent - 400` **9 处**、`extentAfter < 200/300` **2 处** | — |
| 在 `LoadMoreListView` 外重抄三段态 | 4 个页面 | — |

**错误呈现有 4 套写法**（同一件事）：`errorText` 挂字段（identity/conversation/quick_replies/regex）／宿主校验后注入 `nameError`（world）／列表上方单独 `FitText`+`GlobalKey`（group 成员）／标了 `*` 但完全不校验（ta 名字）。

### 1.4 两个零引用的死文件（已核实 0 处 import）

- `lib/island_app/appearance_settings_body.dart`（256 行）— 功能已被 `appearance_display_spec.dart` 取代
- `lib/island_app/settings_body.dart`（93 行）— `settings_tree.dart` 的手写前身

## 2. 判据

### 2.1 什么算"适合"

四条同时成立才值得做：结构同构；独有业务薄；描述符表达得了；**至少存在第二份**（抽象一次省 ≥2 份，否则只是搬家）。

### 2.2 一个决定性的前提：写通道不一样

设置区是「改了就落盘」（patch + `saveMode` + 每个 `key` 对应 `AppSettings` 的字段）；
编辑器是「**草稿 + 显式保存 + `isDirty` + 放弃确认**」。

所以**不能把编辑器直接挂到 `SettingsFieldsPage` 上**。正确切法是抽出「spec → widget、写值走回调」的纯渲染层：
设置侧保留自己的 patch 通道，编辑器侧接自己的草稿 controller。这条判断比任何单页结论都重要。

## 3. 分级清单

### A. 编辑器 / 表单族

| 页面 | 行数 | 关键事实 | 结论 |
|---|---|---|---|
| `conversation_create` / `conversation_edit` | 255 / 242 | 两页近乎逐字；字段 = 1 必填实体选择器 + 2 可选 + 1 单行文本 | **强适合**（一眼能改完的一对） |
| `group_create` / `group_edit` | 291 / 293 | jaccard 0.51；多一个成员多选 | **强适合** |
| `quick_replies_page` / `regex_rules_page` | 366 / 347 | 同一骨架：说明段 + 空态 + 卡片行 + 底部 sheet（字段 3 / 2 个） | **强适合**（列表模板最标准样本） |
| `world_editor_form` 的**词条弹窗** | 420/1076 | **17 个控件**：10 文本框（3 个数字带 clamp）+ 4 下拉 + 3 Chip + 1 分段；**5 个字段按类型条件显示** | **强适合** |
| `world_editor_form` 外层 6 字段 | 656 | 名称必填 + 3 文本 + 标签 + 策略覆盖 | 有条件 |
| `ta_editor_form` | 888(+109) | 8 个标量 + 3 个图片槽 + 子页入口 + 导出导入 220 行内嵌；**零校验但标了 `*`** | 有条件（要先有图片槽/子页描述符） |
| `dialogue_style_form` | 234 | 轮次列表，每轮 2 个文本域；收益在"至少一条"规则统一 | 有条件 |
| `identity_editor_page` | 370 | 只有 2 个字段；真正重复的是导出/导入那段 | 有条件（动作表） |
| `world_editor_page`（外壳） | 335 | 0 个字段；`放弃修改` 壳 + 导出导入 | 有条件（动作表） |
| `prompt_strategy_advanced_page` | 889 | 10 个文本域形态统一，但语义重、要预设联动 | 有条件（等"表单+submit"） |
| `oobe/oobe_steps` | 982 | **0 个输入控件**，四步元信息已经在 `kOobeSteps` 表里 | **不适合** |
| `settings/authors_page` | 233 | `const List<_Author>` + 一个渲染器，已经是"数据+渲染器" | **不适合（已经是目标状态）** |

### B. 列表 / 网格族

| 页面 | 行数 | 关键事实 | 结论 |
|---|---|---|---|
| `my_collections_page` | 134 | 状态机 38 行；独有业务≈0 | **强适合**（网格样板） |
| `my_cards_page` | 321 | 与上条 `_load` 同构；独有 = 审核徽章 + 5 个动作 | **强适合** |
| `notifications_page` | 274 | 又一份 `_load`；外部重抄三段态 | **强适合** |
| `worlds_list_page` | 381 | 又一份 39 行状态机；6 个管理动作 | **强适合** |
| `punishments_page` | 389 | 自己手写五段；独有 = 申诉表单 80 行 | **强适合** |
| `teahouse_body` | 527 | 文件内两份状态机；`Favorites` 与 topics 帖子流 65% 重合 | **强适合** |
| `teahouse_topics_page` | 301 | 帖子流那半段是复制 | **强适合（半页）** |
| `search_page` | 1096 | **4 套状态机**（16 个状态字段）+ 4 份 loader + 4 支 `_onScroll` | **强适合，但别第一批**（见 §5） |
| `points_page` | 541 | 状态机 + 外部重抄三段态；余额渐变卡 46 行、兑换表单 | 有条件 |
| `image_gen_body` | 1061 | 第二份状态机；工作台参数 + 任务轮询是真业务 | 有条件（只历史列表） |
| `recommend_page` | 341 | 无分页；两份 50 行卡拼装 | 有条件 |
| `pages/search_page`（本体搜索） | 297 | 样板约 30 行 | 不建议（ROI 太低） |

### C. 详情族（区块已经"像表"，只是写成了 if 列表）

| 页面 | 行数 | 关键事实 | 结论 |
|---|---|---|---|
| `card_detail_page` | 2251 | 1043-1082 已是「图标+标题+正文」堆叠 ×4 | 有条件（区块强适合） |
| `ta_showcase_page` | 689 | 411-453 与 card_detail 同一套语义的第二份实现 | 有条件（与上条合并做一份） |
| `world_detail_page` | 889 | 447-506 头卡 = 6 个可选段落堆叠 | 有条件 |
| `image_gen_detail_page` | 767 | 宽窄两栏共用 `_columnChildren` | 有条件 |
| `teahouse_post_page` | 905 | 第三个阈值（`<200`）；回复流与 `comment_section` 重复 | 有条件 |
| `proxy_config_page` | 433 | 编辑态 = 3 文本 + 1 开关纯手写 | 有条件（需"表单+submit"） |
| `server_settings_body` | 122 | 单字段表单 | 有条件 |
| `sponsor_body` | 376 | 字段来自远端，用字段树会撒谎 | 不建议 |
| `swipe_body` | 427 | 卡片滑动，不是列表 | 不适合 |

### D. 本体主页 / 会话族

| 页面 | 行数 | 关键事实 | 结论 |
|---|---|---|---|
| `group_home_page` | 310 | 与 `home/home_widgets` 四步同构（过滤→排序→空态→列表） | **强适合**（共用"会话行模板"） |
| `home_page` + `home_widgets` | 92 + 299 | 同上；栏目装配已声明式 | 有条件 |
| `my_home_page` | 463 | 筛选已抽出；瀑布流是另一套算法 | 有条件（卡片模板适合，列数别动） |

## 4. 必须先补的描述符（不补就是空谈）

按依赖顺序：

1. `SettingText` —— 单行/多行、required、`errorText`（**现在完全没有**）
2. `SettingEntity` —— 数据源列表 + 「不选择」空项 + 空库提示 + required（吃掉 10 个手写下拉）
3. `SettingEntityMulti` —— 多选实体（群成员）
4. `SettingListSpec` —— 数据源 + item 模板 + 增删改 + 最小条数 + 是否可排序 + 空态文案 + **变更即落盘 / 草稿两种写模式**
5. `SettingImageSlot` / `SettingSubPage` / `SettingBlock` —— 图片槽、子页入口、嵌套策略块（ta_editor 需要）
6. **分页列表控制器** —— loader + key 提取 + 五态（首载/更多中/无更多/错误/空）。**优先级最高**
7. **动作表** —— 菜单项 = 图标 + 文案 + 可见条件 + 危险标记 + 执行体（导出导入、每行菜单、编辑器外壳共用）
8. **详情区块** —— 可见条件 + 图标 + 标题 + 正文来源 + 自定义 widget 逃生口
9. **表单 + submit** —— 代理/服务器/工单/兑换用；**不能**硬塞进"逐字段落盘"那套

## 5. 建议顺序

1. **删两个死文件**（349 行，零风险）：`appearance_settings_body.dart`、`settings_body.dart`。
2. **分页列表控制器**，顺手把 9 处裸 `-400`、2 处裸 `300/200` 收进阈值家族。不碰页面业务。
3. **动作表**（独立于字段声明，收益比任何单页都大）：导出/导入 3 处、编辑器外壳 5 处、「每行菜单随状态变」。
4. **第一批页面（全部强适合，重复得能被对账）**：conversation 两页 → group 两页 → quick_replies + regex_rules → world 词条弹窗。
5. **列表项模板**四页：`my_collections` → `my_cards` → `notifications` → `worlds_list`。
6. **详情区块**三页：`card_detail` + `ta_showcase` + `world_detail`。
7. **`search_page` 最后**：重复最严重，但 4 个 tab 结果模型（Map / 世界卡 / 帖子）与分页语义（`has_next` vs `r.hasNext`）都不同，适合当控制器成熟后的靶子。
8. **表单 + submit 最后做**，先把描述符补进 spec 同族。

## 6. 明确不做

聊天界面（`chat_surface` 刚抽成组件、业务最重）、生图工作台参数与轮询、图片查看器、瀑布流列数算法、左右滑动切角色、长按 5 秒删除确认、主题取色、OOBE 的品牌动画、authors_page（已是目标状态）。

理由统一：描述符表达不了手势时序、轮询状态机和视觉定制，抽象只会让它们更难读。

## 7. 规模与收益

- **强适合 14 个页面/片段**，合计约 **6000 行**
- **有条件 15 个**，合计约 **7800 行**（只有局部适合）
- 第一批（死文件 + 分页控制器 + 动作表 + 6 个编辑器页）改动面约 **2500 行**，能消掉 16 份状态机的大部分、10 个手写选择器、5 份外壳
- 收益口径要诚实：先例 `appearance_display_spec` 是 604 → 396 行，**只省 35%**。真正的收益是把「文案 / 范围 / 单位 / 读写键 / 可见性」收成一份**能被测试逐条对账**的数据。上面这些页面值得迁，是因为它们重复得能被对账，不是因为它们长。

## 8. 复核命令

```powershell
# 还在手写分页状态机的文件
Get-ChildItem -Recurse lib -Filter *.dart | Select-String -Pattern '_noMore' | Select-Object -ExpandProperty Path -Unique
# 手写实体选择器
Get-ChildItem -Recurse lib -Filter *.dart | Select-String -Pattern 'DropdownButtonFormField' | Group-Object Path | ForEach-Object { $_.Name + ' x' + $_.Count }
# 裸写阈值
Get-ChildItem -Recurse lib -Filter *.dart | Select-String -Pattern 'maxScrollExtent\s*-\s*400'
# 死文件确认（应无输出）
Get-ChildItem -Recurse lib -Filter *.dart | Select-String -Pattern "island_app/settings_body\.dart|appearance_settings_body\.dart"
```
