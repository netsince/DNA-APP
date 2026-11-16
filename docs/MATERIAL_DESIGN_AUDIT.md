# Material Design 规范审计（全项目）

> 触发：设置区那轮之后，发现「很多页面只是用了 M3 的组件，但没按 M3 的规范设计」。
> 本文对 `lib/` 全部界面代码做一次系统审计，重点是**表现形式的误用**——
> 用了 M3 的零件，但选错了「这件事该用什么来表达」。
>
> **审计方式**：三名审计员分模块逐页读（社区 / 聊天+主模块 / 设置区），
> 加一轮全项目量化扫描（组件与布局形态的分布、缺席的形态）。
> **只读**：本次未修改任何业务代码。
>
> **边界**：并非每个文件都逐行读完。各章的覆盖范围写在第 9 节；
> 没读的地方不下结论。

---

## 1. 结论

**整体判定：只用了 M3 组件，没有按 M3 设计。**

M3 的「表层」（颜色角色、圆角/间距/字号令牌、共享三态组件、部分组件选型）做得不错，
但「表现形式」这一层大面积选错：**该用 list 的地方包成卡片、该用 bottom sheet 的地方用
dialog、该用 NavigationRail 的地方用抽屉、该用 TabBar 的地方手搓 tab、
该用 RadioListTile 的地方自绘图标、该用表格对齐的地方用 ListTile 拼列。**

三块的自审（技能 self-audit，0=不合格 / 1=部分 / 2=合格）：

| 维度 | 社区模块 | 聊天+主模块 | 设置区 |
|---|---|---|---|
| Task clarity | 1 | 1 | 1 |
| Information hierarchy | 1 | 1 | 1 |
| **Component semantics** | **0** | **0** | **0** |
| Token discipline | 1 | 1 | 1 |
| **Adaptive behavior** | 1 | 1 | **0** |
| **States & feedback** | **0** | **0** | 1 |
| **Accessibility** | **0** | **0** | **0** |
| Expressive restraint | 2 | 1 | 2 |

按技能的准入规则：**Component semantics 与 Accessibility 三块全 0，
States & feedback 两块为 0 —— 当前状态不能按 M3 验收。**

三个 0 分项的共同特征不是"写错了"，而是"**M3 已经有现成的组件/形态，却手写了一遍**"，
于是控件自带的语义、状态层、48dp 命中区、键盘与读屏行为全部一起丢掉。

---

## 2. 全项目量化底表

扫描 `lib/` 全部 309 个 dart 文件（grep 计数，非估算）：

| 含义 | 命中文件数 |
|---|---|
| `Card(` | 36 |
| `ListTile(` | 53 |
| `showDialog<` | 33（共 41 个调用点） |
| `showModalBottomSheet` | 12 |
| `TabBar(` | 5 |
| `SegmentedButton<` | 3 |
| `NavigationBar(` | 1 |
| `Drawer(` | 2 |
| `FloatingActionButton` / `AppEditorFab` | 10 |
| Chip 族（Choice/Filter/Action/Input） | 20 |
| `GridView.` | 3（全部在社区模块） |
| Masonry 瀑布流 | 2（`image_gen_body`、`my_home_page`） |
| `ReorderableListView` | 5 |
| **`DataTable` / `Table`** | **0** |
| **`NavigationRail` / `NavigationDrawer`** | **0** |
| **`Dismissible`（滑动删除）** | **0** |
| **`Semantics` / `semanticsLabel`** | **0** |
| **等宽数字（`FontFeature.tabularFigures`）** | **0** |

两条值得单独点出来：

* **`NavigationRail`/`NavigationDrawer` 全项目 0 处** —— 桌面/平板/横屏的持久导航
  全部靠"把 Drawer 塞进固定宽度 SizedBox"手搭（见 3.4）。
* **等宽数字 0 处** —— 积分、工单、处罚、余额这些"多列数字"页面，
  数字列不可能对齐（见 3.3）。

---

## 3. 表现形式误用（本文核心）

分级：**A = 结构性错误**（选错形式，影响任务完成或造成误解）；
**B = 语义/一致性错误**（能用但不符合 M3 语义）；**C = 打磨**。

### 3.1 用"手搓控件"替代 M3 既有组件

同一件事，项目里既有正确样板，又有手搓版本——这正是"只用了组件、没按规范"的典型证据。

| 现象 | 证据 | 应该用 | 级 |
|---|---|---|---|
| 顶栏「推荐 / 刷一刷 / 探索」用 `InkWell` + 手画 2px 下划线手搭 tab | `island_app/root_shell.dart:650-681` | `AppBar.bottom` + `TabBar` + `TabBarView` | A |
| 搜索结果「全部/角色卡/世界/用户/茶馆帖」是第三套手搭 tab：`SizedBox(height:48)`+Row+`InkWell`，**无指示器**，选中态只有颜色 | `island_app/search_page.dart:563-613`（`596-598` 两支权重都是 w500，死代码） | `TabBar`（本次查询的 5 个平级视图） | A |
| 角色展示页「介绍 / 已有聊天」用自绘胶囊 + `GestureDetector` 伪装 tab，类名还叫 `_buildTabBar` | `pages/ta_showcase_page.dart:313-359` | `TabBar` + `TabBarView` | A |
| 「我的」页 tab 用的是**正统 `TabBar`**（说明团队会写） | `island_app/me_page.dart:616-649` | —— 作为正确样板 | ✅ |
| 消息搜索做成顶栏溢出菜单里的 `CheckedPopupMenuItem`（勾选），与"动作"混在一起 | `pages/chat/ui/widgets/chat_app_bar.dart:193-200` | 顶栏专用 `IconButton(Icons.search)` + search app bar | A |
| 「谁在说话」身份行：一排裸头像 + `GestureDetector`，当前发言者只靠底色 | `pages/chat_page.dart:1045-1098` | `FilterChip`（带头像）或 `SegmentedButton`；至少 `InkWell` + `Semantics(selected:)` | A |
| 单选集合用 `ChoiceChip`（服务商、思考强度、字数档位、标签筛选） | `widgets/provider_config_form.dart:163-177`、`settings/ai_service/simple_view.dart:194-208`、`conversation_prompt_strategy_page.dart:298-337`、`my_home/tag_filter_bar.dart:64-73` | ≤3 短项 = `SegmentedButton`；集合筛选 = `FilterChip`（保留 checkmark）；互斥多行 = `RadioListTile` | B |
| 假 radio：列表项用 `Icon(radio_button_checked)` 自行画选中态 | `widgets/model_picker.dart:168-186`、`settings/ai_service/advanced_view.dart:87-92`、`island_app/widgets/report_sheet.dart:63-85`、`island_app/widgets/teahouse_post_tile.dart` 等 | `RadioGroup` + `RadioListTile`（读屏会念"已选中"） | B |
| 单选但用卡片 + 勾选图标 + 底部「使用」两段式（重说候选） | `pages/chat/actions/chat_actions_inspiration.dart:187-202,236-250` | `RadioListTile`，或"点候选即生效" | B |
| 折叠数值行自绘 `InkWell` + 放大箭头，无 expanded 语义 | `widgets/setting_collapsible.dart:117-144,335-362,484-511` | `ExpansionTile`；或 `ListTile` + `Semantics(expanded:)` | B |
| 删除确认靠"长按右下角圆钮 5 秒"（自绘 96dp 圆 + `GestureDetector`，无 ink/无键盘） | `pages/delete_confirm_page.dart:373-421`、`:61` | `AlertDialog` + error 色确认按钮；门槛更高时用"输入名称" | A |
| 发送键自绘 `Material+InkWell+38×38` 圆钮 | `pages/chat/ui/widgets/chat_input_bar.dart:1034-1071` | `IconButton.filled`（48dp + 语义） | A |
| 语音主按钮用裸 `Listener` 自行判长按/点击（同一控件长按=录完即发、点击=开始/停止） | `chat_input_bar.dart:705-730,732-787` | `FilledButton.icon` + 明确的长按语义与提示 | A |
| 侧栏把手 `IconButton(iconSize:18, compact)` 装在 28dp 列里 | `chat/ui/chat_quick_sidebar.dart:241-262`、`theme/tokens.dart:469` | 可见的全屏/收起按钮，命中区 ≥48dp | B |
| 排行榜式的"票数"行用裸 `Text` 拼列 | `island_app/points_page.dart:224-285` | 见 3.3 | A |

### 3.2 容器选错：dialog / bottom sheet / 页面

41 个 `showDialog` 调用点里，约 10 个承载的是"选择任务 / 长文本编辑 / 管理列表"，
这些在 M3 下该是 bottom sheet 或独立页；真正该用 dialog 的是"需要明确决定"的场景。

| 现象 | 证据 | 应该用 | 级 |
|---|---|---|---|
| 3 字段的快速回复表单塞进 `AlertDialog`（宽度硬编码 360），且**校验发生在关闭之后**，输入丢失只剩 snackbar | `settings/quick_replies_page.dart:82-148` | 全屏编辑页或 `showModalBottomSheet(isScrollControlled:true)` + 就地 `errorText` | A |
| 2 字段的清洗规则表单塞进 dialog；pattern 为空直接静默 `return null`（零反馈） | `settings/regex_rules_page.dart:75-130` | 同上 | A |
| 「存档管理」（列表 + 新建/加载）整块塞进 `AlertDialog` + `ListView.builder` | `pages/chat/actions/chat_actions_snapshots.dart:17-55` | 全屏管理页或大号 sheet；dialog 只留给"确认覆盖当前对话" | A |
| 「添加群成员」= `AlertDialog` + `ListView` + `CheckboxListTile` | `pages/chat_page.dart:911-966` | 全屏选择页（带搜索） | B |
| 导出时"选择要导出的对话"= 多选列表塞进 dialog，高度写死 400 | `widgets/export_import/conversation_picker_dialog.dart:16-42` | sheet（`DraggableScrollableSheet`）或全屏页 | B |
| 「编辑 AI 消息文字」「编辑摘要」= dialog + 3~8 行 `TextField` | `chat/ui/chat_ui_helpers.dart:501-527`、`chat/actions/chat_actions_summary_ui.dart:43-50` | sheet 或独立页（同项目世界词条编辑已用 sheet，不一致） | B |
| 「提示词预览」（长文本）用 dialog | `settings/prompt_strategy_advanced_page.dart:131` | 全屏预览页或大 sheet | B |
| AppBar「⋮」打开的不是菜单，而是**另一个带 3 个 Tab 的整页** | `settings/ai_service_settings_page.dart:224-235` → `ai_service_more_page.dart:79-118` | `PopupMenuButton` 就地给 3-5 条命令 | A |
| 角色卡「评论」做成 0.9 屏高的 bottom sheet（里面再放滚动列表 + 底部输入条） | `island_app/card_detail_page.dart:609-627` | 评论是主要内容：详情页内一级 section / 独立页；sheet 只给轻量上下文 | A |
| 取色器用全屏 `AlertDialog` 装 ColorPicker（同模块举报表单却正确用了 sheet） | `island_app/appearance_settings_body.dart:68-92` | 与非阻断配置一致：sheet 或内联展开 | B |
| 「灵感主题」输入用 dialog，结果又弹 sheet —— 连续两个模态面 | `chat/actions/chat_actions_inspiration.dart:92-100,111-262` | 合并成一个 sheet（顶部输入 + 下方候选） | B |

**该保留 dialog 的（判断正确，不用改）**：放弃修改确认 ×4、删除确认 ×7、退出登录、
重置访问令牌、撤回世界卡、跳过引导、确认回溯、点数不足、导入方式（仅追加/全部替换）。

### 3.3 列表 / 网格 / 表格：形式与内容不匹配

这一节是"应该用瀑布流却用了表格"这一类问题的实际落点。

| 现象 | 证据 | 应该用 | 级 |
|---|---|---|---|
| **积分明细**（时间/变化/余额/来源）用 `ListTile` 的 title-Row + subtitle-Row 拼出来，列不对齐、数字不等宽 | `island_app/points_page.dart:224-285` | 多列可比数字：宽屏**列对齐 + 等宽数字**（`FontFeature.tabularFigures`）+ 表头；窄屏退化为两行但仍保留表头。全项目等宽数字 0 处 | A |
| 工单 / 处罚 / 我的卡列表：每行一张 Card（结构同构、需要线性扫读） | `island_app/my_cards_page.dart:216-218`、`tickets_page.dart:214-216`、`punishments_page.dart:229` | 裸 list + `Divider`/间距；Card 只给独立内容单元 | B |
| 世界列表手搓瀑布流：`Row` 塞 N 个 `Column`，按 `i % columns` 分桶（注释自述"不用 GridView/Wrap"） | `island_app/worlds_body.dart:352-397` | 真 sliver 瀑布流（项目已有正确写法 `island_app/image_gen_body.dart:421` 的 `MasonryGridView.count`）；现状还导致整块一次性构建、读屏逐列读 | A |
| 应用图标选择是**单列巨型卡片**，宽窗口只拉宽 | `settings/app_icon_page.dart:49-96` | 响应式网格 2-4 列 | B |
| 角色卡网格有 3 套列数算法 | `island_app/widgets/responsive_card_grid.dart:39-64`（对比`search_page.dart:709-718` 写死 220/0.62、`explore_body.dart:285-299` 骨架屏再写一遍） | 收口到一个网格组件 | B |
| 世界卡有 3 种形态（瀑布流卡 / ListTile+Divider / ListTile+chevron） | `worlds_body.dart:352-397`、`me_page.dart:1160-1173`、`search_page.dart:735-790` | 同一实体同一形态 | B |
| 列表行变卡片 + 一行四个 trailing（置顶/拖拽把手/溢出菜单/chevron） | `pages/home/home_widgets.dart:149-303`、`world_page.dart:146-256`、`group_home_page.dart:157-306` | 裸 `ListTile` + 单一溢出菜单；拖拽把手只在排序模式出现 | B |
| 设置主页 7 个分组 = 7 张 Card（组内还有 Divider） | `pages/settings_page.dart:176-188` | 列表贴 surface + 分组小标题 + 间距 | C（品牌化决策） |
| 字段页每个分组一张 Card | `widgets/setting_section.dart:64` | 同上 | C（品牌化决策） |
| 搜索结果每条包一张 Card | `settings/settings_search_page.dart:180-191` | list item | A |
| 编辑器每个字段组一张 Card（会话/群聊/身份/世界/OOBE 四步） | `conversation_create_page.dart:94-204`、`group_create_page.dart:97-235`、`oobe/oobe_steps.dart:379,656,790,865` | 无容器分区（字号阶 + 间距）；卡片只给"可整体操作"的单元 | B |
| 帖子流每行是 `Container(1px 描边 + surface 底)`——背景与页面同色，只能靠描边区分 | `island_app/widgets/teahouse_post_tile.dart:51-61` | feed 用 list + 间距；要卡片就用 `surfaceContainerLow` 承担层级 | B |
| 卡片上的小标签有 5 套实现（`_PinBadge`/`_GenderBadge`/`_EntryChip`/`_StatusPill`/`_Chip`） | `card_tile.dart:184-230`、`world_card_tile.dart:167-233`、`card_detail_page.dart:2047-2087`、`my_cards_page.dart:284-330` | 一个共享 `StatusBadge`；**不可点击的元信息不要做成 chip 外观** | B |

### 3.4 导航与自适应：按"方向"而不是"宽度"决策

| 现象 | 证据 | 应该用 | 级 |
|---|---|---|---|
| **全项目 0 处 `NavigationRail`/`NavigationDrawer`**；横屏把抽屉内容塞进固定 260 宽 `SizedBox` 当侧栏 | `widgets/app_section.dart:484-485,508-529`；`island_app/root_shell.dart:344-370,354-356` | M3 宽度类：<600 `NavigationBar`；600–839 `NavigationRail`；≥840 rail + 内容双栏 | A |
| 断点用 `MediaQuery.orientation`，不是可用宽度 —— 640×360 手机横屏会得到 260 侧栏 + 380 内容；1024 竖屏平板被判成手机 | 同上 | `LayoutBuilder`/宽度类 | A |
| 「社区」栏目隐藏主项目 AppBar 与底栏，竖屏下既无抽屉也无底栏（自述"退出靠横向滑动或系统返回"） | `widgets/app_section.dart:424-428,547-552`、`pages/community_page.dart:43-46` | 换皮可以，导航动作不能让位：竖屏保留底栏或返回按钮，横屏用 rail | A |
| 宽屏聊天左侧「快速切换侧栏」是 `BackdropFilter` 磨砂浮层，收起后只剩 28dp 把手 | `chat/ui/chat_quick_sidebar.dart:185-262` | 真正的 list-detail（rail + 次级列表列）或可折叠 supporting pane | B |
| 断点魔法数互不一致：600 / 720 / 860 / 900 / 1000 / 220 / 200 / 240 / 180 | `island_app/card_detail_page.dart:825`、`image_gen_detail_page.dart:349`、`recommend_page.dart:111`、`settings_body.dart:24`、`worlds_body.dart:362`、`responsive_card_grid.dart:15`、`wide_body.dart:74`、`me_page.dart:1080` | 统一到 600 / 840 / 1200（M3 宽度类） | B |
| 工单详情气泡宽 = 屏宽 × 0.78（1920 下 ≈1500px，一行近百字） | `island_app/tickets_page.dart:719-721` | 按内容列版心（`WideContent.reading`） | B |
| 帖子详情不做版心，而 feed 做了（同一条内容，行长从 760 变整屏） | `island_app/teahouse_post_page.dart:589` vs `teahouse_body.dart:270-276` | 统一版心工具 | B |
| 设置区：主页限宽 900 + 全屏 push 子页；子页 `ListView` 全宽拉伸 | `settings_page.dart:63-91`、`data_settings_page.dart:241-243`、`tts_cache_page.dart:88-90` | 宽屏 list-detail / supporting pane；正文限行宽 | B |

### 3.5 状态与反馈：形式选错

| 现象 | 证据 | 应该用 | 级 |
|---|---|---|---|
| **「我的」页三个 tab + 我的卡/我的收藏把请求失败渲染成"暂无内容"**（catch 里只复位 loading） | `island_app/me_page.dart:1063,1242,1294`、`my_cards_page.dart:64-70`、`my_collections_page.dart:68-75` | 失败走共享 `ErrorState(onRetry:)`；"没发过内容"是错误结论 | A |
| LLM 请求失败只弹 1 秒 snackbar，无重试、无 inline 错误，气泡停在半截像"生成完了" | `chat/builders/chat_stream_handlers.dart:37-40`、`utils/ui_feedback.dart:5` | 气泡内嵌 error 条 + 行内「重试」 | A |
| 表单校验用 snackbar 而不是字段 `errorText`（新建会话/群聊/身份/世界发布/茶馆发帖…） | `conversation_create_page.dart:38-42`、`group_create_page.dart:41-45`、`identity_editor_page.dart:57-64`、`island_app/world_publish_page.dart:338`、`teahouse_compose_page.dart:158` | 就地 `errorText` + 滚动到首个错误 | B |
| 错误态把原始异常字符串直接抛给用户 | `island_app/teahouse_topics_page.dart:266-275`、`search_page.dart:631-641`、`comment_section.dart:576-587`、`data_settings_page.dart:83,144,173,224` | 人话文案 + 重试 | B |
| 提交中无进行态（编辑器只有防连点的 `_saving`，按钮不变灰不转圈） | `ta_editor_page.dart:60-66` | 按钮内嵌 spinner + 禁用（备份页已有正确写法 `data_settings_page.dart:276-280`） | B |
| 话题标签点了只弹 1 秒 snackbar（`TeahouseTopicPage` 其实已存在） | `island_app/widgets/teahouse_post_tile.dart:176-181` | 直接 push 目的地；SnackBar 只做非阻断反馈 | A |
| 收藏数是 `favorited ? 1 : 0` —— 布尔状态伪造成计数 | `teahouse_post_tile.dart:292` | 填充/描边图标表达二值，不要假计数 | B |
| 「对方正在输入…」是手搓气泡且位于消息列表之外、不参与滚动 | `pages/chat_page.dart:1529-1549` | 作为消息列表末尾项渲染 | B |
| 分页两套语义（同页"加载更多"按钮 vs 无限滚动） | `comment_section.dart:613-617` | 同一页统一一种 | C |

---

## 4. 其他维度（非表现形式，但仍属规范问题）

### 4.1 组件语义与按钮层级

* **同一主操作两个入口**：编辑器 AppBar ✓ + FAB 同时存在 —— `ta_editor_page.dart:161-165/175-179`、
  `conversation_create_page.dart:84-88/207-211`、`conversation_edit_page.dart:77-81/213-217`、
  `group_create_page.dart:87-91/238-242`、`group_edit_page.dart:89-93/254-258`、
  `identity_editor_page.dart:256-260/316-320`、`world_editor_page.dart:307-311/319-323`。**A**
* **FAB 语义自相矛盾**：一页用 FAB 承载次要动作「添加对话范例」(`dialogue_style_page.dart:123-127`)，
  另一页把 FAB 当"保存键"(`app_editor_frame.dart:53-75`)，而创建类页面又用它做"创建"。**B**
* **破坏性动作的强调不一致**：删除消息用 error `FilledButton`(`chat_ui_helpers.dart:273-280`)，
  「回溯」（丢弃之后全部记录）却用 primary(`:559-562`)；备份页「全部替换」是 `FilledButton`、
  「仅追加」是 `TextButton`(`data_settings_page.dart:89-99`)；清缓存用 primary FilledButton
  无 error 语义(`tts_cache_page.dart:150-157`)。**B**
* **裸 `GestureDetector` 承担可点区域**（无涟漪/焦点/语义）：`teahouse_post_tile.dart:108`、
  `world_card_tile.dart:221`、`card_detail_page.dart:1114`、`chat_message_list.dart:288-302`。**B**
* **导航项混进动作菜单**：「我的」页把编辑资料/我的工单/我的处罚塞进 ⋮ 菜单
  (`island_app/me_page.dart:735-789`)；M3：导航改变"我在哪"，动作改变"这个对象怎样"。**B**
* **即时开关埋进菜单**：置顶/隐藏靠菜单文案变化表达(`my_cards_page.dart:237-276`)。**B**
* **菜单项里套 `ListTile`**（双重内边距、行高错乱）：`chat_app_bar.dart:163-222`、
  `chat_ui_helpers.dart:58-206`、`home_widgets.dart:241-289`、`me_page.dart:758-787`。**B**
* 正面：`AsyncActionButton` 贯穿提交态、`report_sheet` 未选原因时禁用提交、
  FAB 在"新增类"页面用对了。

### 4.2 层级：靠"加容器/加颜色"而不是字号阶 + surface 角色

* 章节标题大量用 **primary 色**建立层级：`ta_showcase_page.dart:438-453`、`search_page.dart:221-229`、
  `dialogue_style_form.dart:130-143`、`world_editor_form.dart:246-251`；设置区分组头同样是
  `primary`(`settings_page.dart:167-170`、`setting_section.dart:73`)。M3：primary 是交互与选中色，
  静态层级用 `onSurfaceVariant`。**B**
* 说明文字用带底色 `Container` 承载（info/error 都靠 alpha 底）：
  `conversation_prompt_strategy_page.dart:178-191,245-258`、`ai_service/simple_view.dart:53-85`。**C**
* 卡片里再套描边容器（双层容器语言）：`plus_hub.dart:231-242`、`world_editor_form.dart:234-268`。**C**
* 字号阶用得偏保守：社区模块 `headlineSmall` 全模块只出现 1 次(`world_detail_page.dart:469`)。

### 4.3 无障碍（三模块共同的重灾区）

* **`Semantics`/`semanticsLabel` 全项目 0 处**（grep 实证）。
* **触摸目标 < 48dp**：
  - 消息操作圆钮 26×26(`chat_message_list.dart:534-567`)、发送键 38×38(`chat_input_bar.dart:1047`)、
    侧栏把手 28(`tokens.dart:469`)、快捷回复行 38(`chat_input_bar.dart:795`)、
    帖子统计行 ≈21×23(`teahouse_post_tile.dart:300-324`)、状态徽章 ≈14 高(`world_card_tile.dart:224`)、
    筛选胶囊 ≈30(`explore_body.dart:538`)、角色卡操作条 40 且显式 `tapTargetSize: shrinkWrap`
    (`card_detail_page.dart:1651-1671`)、折叠设置行 ≈44(`setting_collapsible.dart:117`)、
    举报原因行 ≈32(`report_sheet.dart:68`)。
* **只用颜色表达状态**：搜索 tab 选中(`search_page.dart:563-613`)、群聊发言者(`chat_page.dart:1063-1067`)、
  标签筛选 `showCheckmark:false`(`tag_filter_bar.dart:66-70`)、角色展示页自绘 tab(`ta_showcase_page.dart:346-354`)、
  设置主页禁用态(`settings_page.dart:220,226,241`)。
* **字体缩放被缩回**：`FitText` 对 <6 字文本无条件 `FittedBox(scaleDown)`，默认 `minShrink=0`
  (`widgets/fit_text.dart:5-6,36-47,149-156`)，设置区无一处传 `minShrink`；
  顶栏 tab 也套了 `FittedBox`(`root_shell.dart:631-648`)。系统大字号下短标签反而被压小。**A**
* 瀑布流破坏读屏顺序（`worlds_body.dart:380-394` 逐列读）。
* 正面：图标按钮普遍带 tooltip（设置区 20 处）、`FitText` 的墨色对比度自适应
  (`fit_text.dart:98-107`)、真 `SwitchListTile`/`RadioListTile` 处语义完整。

### 4.4 令牌纪律（整体是加分项，但仍有缺口）

* 有完整的 `lib/theme/tokens.dart`（圆角/间距/字号/透明度/描边/尺寸/动效），
  颜色走 `ColorScheme.fromSeed`；设置区 **0 处** `Color(0x...)`。
* 缺口：裸 `Colors.grey` 9 处（`explore_body.dart:266,387`、`teahouse_body.dart:305`、
  `search_page.dart:621`、`tickets_page.dart:124` 等）；手写 `BorderRadius.circular(999/16/12)`、
  手写 `BoxShadow`（`chat_input_bar.dart:893-901`、`chat_message_list.dart:310-316`）、
  手写 `Duration`/`Curves`；设置区 17 个文件带 `// ignore_for_file: deprecated_member_use`，
  其中两处仍在用**已弃用**的 `Radio(groupValue)` API
  (`spec/settings_fields_page.dart:299-307`、`models/model_list_body.dart:137-145`)。

---

## 5. 跨页面不一致（同一件事 N 种做法）

| 语义 | 实现数 | 位置 |
|---|---|---|
| 排序控件 | **5** | `explore_body.dart:518-566`、`worlds_body.dart:452-500`、`teahouse_body.dart:228-233`、`search_page.dart:664-699`、`comment_section.dart:546-556` |
| tab | **3** | 正统 `me_page.dart:616-649`｜手搭 `root_shell.dart:650-681`｜手搭无指示器 `search_page.dart:563-613` |
| 单选控件 | **4** | `SegmentedButton`(`appearance_display_spec.dart:154-176`)、`ChoiceChip`、`RadioListTile`、裸 `Radio`(`model_list_body.dart:137`) |
| 选模型 | **3** | 内嵌限高列表 `model_picker.dart:155-201`｜bottom sheet `model_edit_page.dart:141-186`｜卡片+radio `model_list_body.dart:111-145` |
| 列表行 | **4** | 卡片壳+ListTile `home_widgets.dart:150-152`｜多列 ListTile 卡 `group_home_page.dart:119-131`｜裸 InkWell+Row `world_page.dart:150-154`｜裸 ListTile `search_page.dart:234-267` |
| 空态 | **3** | `AppEmptyState`｜手写 Column+`FilledButton`｜一行 `FitText` |
| 错误态 | **3** | 共享 `ErrorState`(40 处)｜手搓 `Text('$e')`｜**静默丢弃** |
| 加载态 | **3** | 骨架屏｜居中 spinner｜共享 `LoadingState` |
| 保存/创建入口 | **3** | 顶栏 ✓ + FAB 双份｜只有 FAB｜只有顶栏 |
| 破坏性确认色 | **2** | error 色｜primary 色 |
| 长文本编辑 | **3** | bottom sheet｜dialog+TextField｜通用 TextInputDialog |
| 版心 | **3** | `wideInset()`｜`WideBody`/ConstrainedBox｜不处理 |
| 分页 | **2 套机制** | 共享 `LoadMoreListView`｜手写 `NotificationListener`（阈值 400/300 各写） |
| 图片全屏查看 | **2** | `image_viewer.dart`｜`comment_section.dart:325-355` 内联重写 |
| 菜单项写法 | **3** | `PopupMenuItem`+ListTile｜Row(Icon+Text)｜纯 Text |

---

## 6. 修复优先级（建议分四批）

**第 1 批 · 会误导用户的**（性价比最高）
1. 三处"加载失败伪装成空态" → `ErrorState(onRetry:)`（`me_page`、`my_cards_page`、`my_collections_page`）。
2. 聊天失败的可恢复性：气泡内嵌错误 + 重试，snackbar 时长从 1000ms 提到 ≥4s。
3. 表单校验从 snackbar 改到字段 `errorText`；错误态停止直接抛异常字符串。

**第 2 批 · 触摸目标与语义**（无障碍硬线）
4. 26/28/38/40dp 的交互元素全部提到 48：消息操作、发送键、侧栏把手、快捷回复、角色卡操作条、折叠设置行。
5. 自绘控件补语义：折叠行 `expanded`、统计行 label（"评论 12"）、假 radio 换真 `RadioListTile`。
6. `FitText` 默认 `minShrink: 0.85`（或允许换行），停止在系统大字下缩字。

**第 3 批 · 表现形式换成 M3 控件**
7. 三处手搭 tab → `TabBar`/`TabBarView`（`root_shell`、`search_page`、`ta_showcase_page`）。
8. 导航按宽度类决策 → `NavigationBar`/`NavigationRail`/`NavigationDrawer`（替换 `SizedBox(width:260)` 的手搭侧栏）。
9. dialog → sheet/页面的 8-10 处（快速回复、清洗规则、存档管理、群成员、对话选择、长文本编辑、提示词预览、⋮ 当导航）。
10. 积分/工单/处罚的"多列数字"：列对齐 + 等宽数字；宽屏考虑表头。

**第 4 批 · 容器与一致性（改动面大，建议单独一轮）**
11. 去"每组一卡/每行一卡"，改 surface + 字号阶 + 间距（设置主页、编辑器、社区 feed、列表页）。
12. 收敛跨页不一致：排序控件 1 种、空态/错误态/加载态各 1 套、保存入口 1 处、版本版心 1 套。
13. 令牌补齐：裸 `Colors.grey`、手写圆角/阴影/时长、弃用 `Radio(groupValue)`。

---

## 7. 值得保留的正确样板

审计里也验证了一批"按 M3 做对了"的地方，改动时别把它们一起推平：

* 主导航用 `NavigationBar`（`widgets/app_bottom_nav.dart:66-77`）；
* 「我的」页 tab 用正统 `TabBar` + 吸顶 `SliverPersistentHeader`（`island_app/me_page.dart:616-649`）；
* 角色卡详情宽屏左右双栏（`card_detail_page.dart:825,947,973`）+ 统一版心工具
  （`widgets/wide_body.dart`）；
* 瀑布流的正确写法（`image_gen_body.dart:421` `MasonryGridView.count`）、角色卡自适应列数
  （`my_home_page.dart:171-251`）、OOBE 双栏（`oobe_page.dart:621-669`）；
* 统一三态组件（`widgets/state_views.dart`）与提交态按钮（`widgets/async_action_button.dart`）；
* 举报表单用 bottom sheet（`report_sheet.dart`）、FAB 用于"新增"类主操作；
* 设置区：分组/字段声明化（`settings/spec/**`）、动效令牌与扁平描边的克制表达。

---

> ⚠️ **部分整改项已按 [`REGRESSION_AUDIT.md`](REGRESSION_AUDIT.md) 回滚**：本文档把「不符合 M3」当唯一判据，
> 其中若干条实际是**我的判断越界**，不是原设计的问题。已回滚：FitText 缩字默认值、消息动作排收敛、
> 半屏/全屏滚动自动切换、编辑器保存 FAB、顶栏动作收敛、筛选条拆两行、积分列定宽。
> 判定以 `REGRESSION_AUDIT.md` 为准。

## 7.5 修复进度

按第 6 节的四批推进，逐条回填。状态：✅ 已改并自检 / 🟡 已评估但需单独一轮 / ⬜ 未开始。
"自检" = `flutter analyze --no-pub lib test` 干净 + 相关测试通过。
本轮结束时的整体验证：**818 个测试通过 / 2 跳过，analyze 无 issue**。

### 批次① 状态与误导 —— ✅ 全部完成

| 条目 | 改动位置 |
|---|---|
| 「我的」四个 tab 失败伪装空态 | `island_app/me_page.dart`：四个 `_load*` 增加错误位，失败且列表为空走 `ErrorState(onRetry:)` |
| 我的卡 / 我的收藏 失败静默 | `my_cards_page.dart`、`my_collections_page.dart`：错误优先于空态 |
| 茶馆发帖校验 | `teahouse_compose_page.dart`：`errorText` + `FocusNode`，随输入清除 |
| 世界发布 / 本地世界编辑校验 | `world_publish_page.dart`、`world_editor_page.dart`、`world_editor_form.dart`：新增 `nameError/onNameChanged`，字段级 `errorText` + 表单顶部可播报错误条 |
| 5 个编辑器表单校验 | `conversation_create/edit`、`group_create/edit`、`identity_editor`：`errorText` + `Scrollable.ensureVisible` 定位首个错误 |
| 裸异常文案 | `teahouse_topics_page.dart`、`search_page.dart`、`comment_section.dart`：人话 + 重试 |
| 聊天失败无恢复路径 | `chat_stream_handlers.dart`：生成失败登记 `_streamErrors`（不清空已生成内容）；`chat_message_list.dart` 新增 `_StreamErrorBanner`（errorContainer + 行内「重试」+`liveRegion`）；`chat_page.dart` 接现有重试动作 |
| snackbar 1 秒 | `app_settings.dart` 新增唯一来源 `kDefaultSnackDurationMs = 4000`，`settings_service` / `app_controller` 重置路径 / `ui_feedback` 全部引用它 |

### 批次② 无障碍 —— ✅ 完成

| 条目 | 状态 | 说明 |
|---|---|---|
| 聊天 26/38/28dp 触摸目标 | ✅ | 消息操作/发送键/侧栏把手：`IconButton`/`IconButton.filled` + 48dp + tooltip；侧栏把手令牌 28→48 |
| 语音主按钮裸 `Listener` | ✅ | 保留长按语义，外包 `Semantics(button/label/hint/onTap/onLongPress)` + 可见按下态 + 「按住说话」文字 |
| 群聊发言者仅颜色区分 | ✅ | `GestureDetector` → `Semantics(selected) + InkWell`，选中态加 2dp 主色环（非颜色冗余）；列表高 56→60 修掉了 2px 溢出 |
| 假 radio（`model_picker` / `report_sheet`） | ✅ | 换 `RadioGroup` + `RadioListTile` |
| 折叠设置行 44dp / 无展开语义 | ✅ | `setting_collapsible.dart` 抽出 `_CollapsedHeader`：48dp + `Semantics(expanded)` |
| `FitText` 在系统大字下缩字 | ✅ | 改成**按字号倍率生效**：倍率 = 1 保持历史行为，用户调大字号后启用 0.85 下限（详见批次④表最后一行） |

### 批次③ 表现形式 —— ✅ 完成

| 条目 | 状态 | 改动位置 |
|---|---|---|
| 角色展示页手搓 tab | ✅ | `ta_showcase_page.dart`：「介绍 / 已有聊天」→ `TabBar.secondary` + `TabController`（宽屏 `TabBarView` 各自滚动；窄屏保留交叉淡入，避免把长滚动页压成定高容器） |
| 搜索页 5 个手搭 tab | ✅ | `island_app/search_page.dart` → `TabBar`（图标+文字）+ `TabBarView`；滚动控制器按 tab 拆开（`TabBarView` 过渡期两页同时在树上），状态收进 `_resultsShell` |
| dialog → sheet（7 处） | ✅ | 快速回复、清洗规则（含 `errorText` 就地校验，不再"关掉才报错"）、存档管理、导出选择对话（`DraggableScrollableSheet`）、编辑 AI 消息文字、提示词预览、AI 服务「⋮」（改为就地 `PopupMenuButton` 三条命令） |
| 导航按宽度类 + `NavigationRail` | ✅ | `app_section.dart`：`compact(≤600) → NavigationBar` / `medium(601–839) → NavigationRail` / `expanded(≥840) → 常驻 AppDrawer`；不再用 `orientation` 判断。目的地元数据抽到 `AppBottomNav.metaFor/railDestination`，底栏与侧栏共用一份 |
| 多列数字列对齐 | ✅ | `island_app/points_page.dart`：金额/余额/大卡数字加 `FontFeature.tabularFigures()`（全项目此前 0 处） |
| 社区 `root_shell` 第三套手搓 tab | ✅ | `island_app/root_shell.dart`：`Row`+`InkWell`+手画 2px 下划线 → `TabBar`（`isScrollable` + `TabAlignment.center`，控制器与`_tab`双向同步）；顺带去掉那层把字整体缩小的 `FittedBox`（装不下时改横向滚动） |
| 岛内按横竖屏切外壳 | ✅ | 同文件：`OrientationBuilder` → `LayoutBuilder`，`≥840` 才走常驻侧栏；社区底栏只有 5 格，compact/medium 都保留底栏（不额外引一套 rail） |
| 角色卡评论 0.9 屏 sheet | ✅ | `card_detail_page.dart`：改为独立路由页（`CommentSection` 契约上有界高度，塞进详情页滚动区会炸；审计给了「页内 section / 独立页」两个选项，选后者），底部输入条仍固定在底部 |
| 添加群成员 dialog | ✅ | `chat_page.dart`：大号 sheet + 搜索框 + 已选计数，多选与返回语义不变 |
| 编辑摘要 / 编辑 AI 消息文字 | ✅ | 均改为 `isScrollControlled` sheet + 键盘避让 |
| 灵感「dialog 再 sheet」双模态 | ✅ | `chat_actions_inspiration.dart`：合并成一个 sheet（主题输入 → 生成 → 候选 → 使用） |
| 取色器全屏 dialog | ✅ | `appearance_settings_body.dart`：改 sheet，与同模块举报表单同范式 |
| `⋮` 当导航（AI 服务） | ✅ | 改 `PopupMenuButton` 就地三条命令 |

### 批次④ 容器与一致性 —— ✅ 完成

| 条目 | 状态 | 改动位置 |
|---|---|---|
| 设置主页「每组一卡」 | ✅ | `settings_page.dart`：去掉 Card，分组改「标题（`titleSmall` + `onSurfaceVariant`）+ 24 间距」，组内最多一根 Divider；分组头左缘对齐到行 leading 图标列 |
| 字段页「每组一卡」 | ✅ | `setting_section.dart`：无容器 section（构造参数未变），层级改由字号阶 + 语义色 + 间距承担 |
| 搜索结果「每行一卡」 | ✅ | `settings_search_page.dart`：裸 `ListTile` + 缩进 Divider |
| 弃用 `Radio(groupValue:)` API | ✅ | `settings/spec/settings_fields_page.dart`（改 `RadioGroup` + `enabled`）、`settings/models/model_list_body.dart` |
| 编辑器每个字段组一张卡 | ✅ | `conversation_create/edit`、`group_create/edit`、`identity_editor`、`world_editor_form`：Card → 无容器分区（`titleSmall` + `onSurfaceVariant` + 组间 24 间距）；OOBE 四步的整屏 Card 也一并拆掉 |
| 同一主操作两个入口（AppBar ✓ + FAB） | ✅ | 会话/群聊/身份编辑器删 FAB，顶栏改文字按钮「保存/创建」；`dialogue_style_page` 的「添加对话范例」从 FAB 降为顶栏图标。`ta_editor_page` / `world_editor_page` 仍是「AppBar + FAB」，留在待收敛清单 |
| 列表页「每行一卡」 | ✅ | `my_cards` / `tickets` / `punishments` / `points` 兑换结果 → 裸 list item + 缩进 Divider |
| 帖子统计行 21×23 / 收藏假计数 / 配图裸手势 | ✅ | `teahouse_post_tile`：统计行 48dp + 读屏标签（`ExcludeSemantics` 挡掉裸数字）、收藏改填充/描边图标不再输出 1/0、配图 `InkWell`（透明 Material 作涟漪面） |
| 世界卡状态徽章（14dp、仅颜色） | ✅ | `world_card_tile`：改为只读徽章 + 状态图标 + `Semantics`；`onStatusTap` 保留但注明无调用点 |
| 筛选条「清除筛选」同权重 / 胶囊 30dp | ✅ | `explore_body` / `worlds_body`：清除筛选改低强调 `TextButton.icon`；胶囊 `minHeight 40` |
| 空态三套实现 | ✅ | `home_widgets` / `group_home_page` / `identity_page` / `model_list_body` / `provider_list_body` / `advanced_view` 全部改走 `AppEmptyState` |
| 标签筛选仅用颜色 | ✅ | `tag_filter_bar`：`ChoiceChip(showCheckmark: false)` → `FilterChip`（集合筛选 + 保留勾选） |
| 删除确认「长按 5 秒」 | 🔁 评估后保留原设计 | 曾改为「复核页 + 确认对话框」，作者评估后认为长按 5 秒更合适（按住 + 页面自动滚动复核的组合动作更防误触），已整段还原；仅在长按按钮上补了 `Semantics`（不改交互）。读屏可达路径 = 「输入名称确认」模式（设置项默认开启）。详见 `REGRESSION_AUDIT.md` §3.6 |
| 聊天视图状态无可见控件 | ✅ | 顶栏两颗 `IconButton`（半屏/全屏、沉浸，带 `Semantics` 念出当前视图名）；沉浸态右上角常驻「退出沉浸」；删掉点空白切沉浸的隐形热区；**去掉「滚动方向自动改布局」**（滚轮/滚动/近底三套阈值全删），布局只由用户显式操作改变。`ChatAppBar` 5 个新参数全部可选，默认不渲染 |
| 世界手搓瀑布流 | ✅ | `worlds_body.dart`：`Row`+`i % columns` 分桶 → `SliverMasonryGrid.count`（懒构建、读屏行优先、列高自动） |
| 应用图标单列巨型卡 | ✅ | `app_icon_page.dart`：→ `SliverGrid`（窄 2 列 / 宽最多 4 列） |
| 网格列数三套算法 | ✅ | `responsive_card_grid.dart` 新增 `cardGridMetrics()` 纯函数 + `CardGridMetrics`，探索/首页骨架屏与搜索页全部改调它，**骨架屏与真实网格同构**（新增 `test/card_grid_metrics_test.dart` 10 条锁边界：宽度 0/NaN、上下限列数、宽高自洽） |
| 菜单项套 `ListTile` | ✅ | 4 个文件 25 处 → `Row(Icon + 间距 + 文案)`（`home_widgets` / `chat_app_bar` / `chat_ui_helpers` / `me_page`） |
| 破坏性动作强调不一致 | ✅ | 「导入方式」把安全项「仅追加」放主按钮、「全部替换」降为 error 文字按钮；聊天「确认回溯」、TTS「确认清空」改 error 色 |
| 裸 `Colors.grey` | ✅ | 剩余 4 处（`server_setup` / `server_settings_body` / `teahouse_post_page` / `teahouse_compose`）换语义色 |
| 排序控件 5 种 | ✅ | 统一口径：**排序 = `SegmentedButton`**、**集合筛选 = `FilterChip`**、**清除筛选 = 低强调 `TextButton`**。覆盖 `explore_body`、`worlds_body`、`teahouse_body`、`comment_section`、`search_page`；删除两份重复的自绘胶囊（`_FilterPill` / `_Pill`），社区模块自绘胶囊归零 |
| 分页 2 套 | ✅ | `widgets/load_more_list.dart` 新增 `loadMoreListener()` / `isNearScrollEnd()` + 两个阈值常量（400 列表 / 300 feed，附「为什么不同」），探索/世界/茶馆/搜索四处改用它；**评论区也从「加载更多」按钮改成无限滚动**（尾部只有加载中 spinner 或空占位，失败重试与下拉刷新原样保留）。至此全项目一种分页语义 |
| 版心 3 套 | ✅ | 通知列表、帖子详情、工单气泡、茶馆 feed 全部走 `WideContent`/`wideInset`；设置/赞助两页的内容列上限收成 `AppSize.islandContentMaxWidth` |
| 断点魔法数 | ✅ | `AppBreakpoints`（600/840/1200）替换主壳、社区壳、推荐页、生图详情、角色展示页；设置/赞助的「内容列 720」收成 `AppSize.islandContentMaxWidth` |
| `WorldStatusChip`（第六套标签） | ✅ | → `StatusBadge`（色档与图标逐一对齐，公开类与构造签名保留） |
| 令牌：手写圆角/阴影/宽度 | ✅ | 输入岛/气泡/快速回复/语音结果框的 `circular(999/20/12/8)` → `AppRadius`；手写 `BoxShadow` → `AppShadows.soft`；`maxWidth: 520` ×4 → `AppSize.contentMaxWidth`。（气泡朝向头像那一角 4→8：`AppRadius` 最小档是 8，要保留 4 得给令牌加档） |
| `ignore_for_file: deprecated_member_use`（全库） | ✅ | 从 17 逐步清到 **0**（最后 6 个：4 处真弃用换成 `DropdownButtonFormField.initialValue`，另 4 个文件是预防性忽略直接删）。 `lib/pages/settings/**` 已归零：先删 ignore 再跑 analyze，只有 4 处是真弃用（3 处 `DropdownButtonFormField(value:)` → `initialValue:`、1 处 `onReorder` → `onReorderItem`，后者同时删掉手写的下标调整），其余 13 个是预防性忽略。全库还剩 6 处，都在本轮范围外 |
| 积分明细列对齐 | ✅ | `points_page`：金额与余额都套定宽 92 的右对齐容器 + 等宽数字，明细上下成列 |
| `settings.dynamicHalfScreen` 无效果 | ✅ | 接上真实作用：它现在决定**顶栏是否显示「展开为全屏」按钮**（文案改为「顶栏显示展开按钮」；key 保留旧名以不丢老用户的持久化值，模型层注释写明语义变更） |
| 世界卡 3 形态 | ✅ | 新建 `island_app/widgets/world_list_tile.dart`（紧凑行：名称 + 简介 + 元信息 + 审核徽章 + chevron），`me_page` 与 `search_page` 两处手写 ListTile 都改用它。**保留两种形态是刻意的**：浏览/发现用卡片（视觉可比），我的内容/搜索结果用行（扫读、密度），文档里写清了语义分工 |
| `chat_page` 的 `onCopyMessage` 死路径 | ✅ | 参数、字段与传参全部删除（复制已由长按菜单自己做） |
| 颜色 alpha 手写值 | ✅ | `AppAlpha` 从 5 档扩到「5 个语义别名 + 17 档数值阶梯」，全库 **91 处** `withValues(alpha: 0.xx)` 换成令牌（37 个文件），另有 2 处计算型（`half * bubbleOpacity`、`subtle * intensity`）也改了；只剩玻璃强度乘子（0.035/0.045/0.11）与 `1 - progress` 这类插值，属有意保留并写明理由 |
| 拖拽排序下标口径 | ✅ | 3 处 `ReorderableListView.onReorder`（已弃用）→ `onReorderItem`，连同 `AppController.reorderTas/reorderWorlds/reorderConversations` 去掉内部的 `newIndex -= 1`（新回调已预调整，再减就是双重调整，只在向后拖时才错）。新增 `test/reorder_semantics_test.dart` 3 条钉住口径 |
| 状态 → (色调, 图标) 映射三份 | ✅ | 收口到 `status_badge.dart` 的 `worldStatusStyle()`，`WorldCardTile` / `WorldStatusChip` / `WorldListTile` 三处都调它（文案仍取模型 `statusLabel`，避免同一个中文串两个来源） |
| 帖子流「1px 描边卡」 | ✅ | `teahouse_post_tile`：去掉 outlineVariant 描边，底色改 `surfaceContainerLow`（层级由 surface 角色承担），间距即分节；版心未动 |
| 点赞/收藏「已选中」颜色语义 | ✅ | `error`/`tertiary` → `primary`（`error` 在这个 App 里还表示「处罚生效中」，不能兼职「喜欢」） |
| 气泡尾巴圆角 | ✅ | `AppRadius` 补 `xxs = 4`，气泡朝向头像那一角从 8 还原成原始的 4 |
| `FitText` 缩放下限 | ✅ | **按字号倍率生效**：倍率 = 1 时保持历史行为（布局不变），用户调大字号后启用 0.85 下限——压到 85% 以下就不再压，改为换行。新增 `wrapWhenTooNarrow` 逃生阀：`SegmentedButton` 这类按**固有宽度**排版的容器必须关掉换行（换行分支内部是 `LayoutBuilder`，被查 intrinsic 时会抛断言），这一条是在修 `font_scale_smoke` 溢出时踩出来的。新增 4 条测试锁「倍率 1 不变 / 大字号换行 / 定宽控件可退出 / 宽容器不多余缩字」 |

> 备注（评审用）：`lib/pages/chat_page.dart` 在 git 里会显示成整文件改动，原因是该路径的索引条目被判定为 `i/-text`（EOL 归一化不生效），工作区是 CRLF——不是本次内容改动造成的。review 用 `git diff -w -- lib/pages/chat_page.dart` 看真实差异；根治需要 `.gitattributes` 或 `git add --renormalize`。

## 8. 判定口径说明

* 本文按 **M3 规范**判断，不按"好不好看"。凡是"M3 明确写了该用 A，项目用了 B"才算问题；
  品牌化偏离（liquid glass、胶片转场、扁平 + 细描边、装饰性渐变）单独标注，不计入违规。
* "每行一卡""每组一卡"在 M3 里属于明确的 anti-pattern（*Do not wrap every section or
  list row in a card*），但本项目把它写进了自有设计规范（`DESIGN_SPEC.md` 5.1/5.3），
  所以标为 **C（品牌化决策）**——需要产品确认后统一，不是纯技术修复。
* 触摸目标、只用颜色表达状态、语义标签属于可访问性硬线，不因品牌而豁免。

---

## 9. 覆盖范围与未覆盖

| 模块 | 逐行读 | 部分读 | 未覆盖（不下结论） |
|---|---|---|---|
| 社区 `lib/island_app` | 23 个文件（root_shell、explore/worlds/home/teahouse 各 body、points、punishments、my_cards、my_collections、notifications、settings_body、app_drawer、plus_hub、各 tile 等） | card_detail_page、me_page、search_page、comment_section、tickets、image_gen_body、teahouse_post_page、world_detail_page、appearance_settings_body | api/client.dart、models、utils、image_viewer、sticker_text、swipe_body、articles、recommend、sponsor、about_body、各 publish/compose 页、crop、preload |
| 聊天 + 主模块 | chat_page 全 1795 行、chat/ui/**、chat/actions/**、chat/builders/**、home/my_home/group/world/identity/search/community、oobe、各编辑器、widgets/** | chat/state/**、ta_editor_form、world_editor_form、liquid_glass 渲染细节 | splash/logo、chat_message_builder、chat_actions.dart |
| 设置区 | settings_page、catalog、search、spec/**、8 个 *_spec、quick_replies、regex_rules、tts_cache、data_settings、update_dialog、advanced、app_icon、license、ai_service/**、models 部分、setting_section、setting_collapsible、seed_input_field、model_picker、provider_config_form、tag_input、fit_text | conversation_prompt_strategy_page、provider_list_body、about/open_source/authors、strategy_* | utils/dialogs、conversation_export_import_dialogs、state_views 内部 |

**未做的事**：没有跑 App、没有截图、没有语义树/键盘 Tab 顺序实测；
触摸目标与对比度结论来自代码里的尺寸与颜色令牌，不是像素测量。
