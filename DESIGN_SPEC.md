# DNA 设计规范 v1.0

> 基于对 `lib/pages` 下 **80 个文件 / 50 个含 `Scaffold` 的独立页面 / 34,991 行代码**的逐页语义分析产出。
> 本规范**只定义标准,不改动任何代码**。落地时按「附录 B：落地清单」执行。

---

## 0. 结论摘要

当前 UI 的问题**不是审美**,而是**没有全局设计规范**:

| 视觉属性 | 现状 | 问题 |
|---|---|---|
| 圆角 | **156 处**硬编码,**13 种**值 | 同类卡片在不同页面圆角不同 |
| 间距 | **520 处**硬编码,**21 种**值 | 无统一节奏,页面间呼吸感不一致 |
| 内边距 | **279 处**硬编码,4 种写法混用 | 同上 |
| 卡片样式 | **235 处**手写(`RoundedRectangleBorder` 82 + `elevation:0` 77 + `BorderSide` 76) | 本该由 `cardTheme` 管理 |
| 字号 | **37 处**硬编码,**9 种**值 | 与 `textTheme` 混用 |
| 颜色 | **10 处**硬编码 `Color(0xFF…)` | 游离于配色体系外 |
| **合计** | **≈ 1,086 处魔数** | 收敛目标:**约 25 个令牌** |

**唯一的全局样式来源**是 `main.dart` 的 `ColorScheme.fromSeed` —— 它只管颜色,**不管形状与节奏**。
`ThemeData` 中自定义子主题数量为 **0**(无 `cardTheme` / `appBarTheme` / `listTileTheme` / `inputDecorationTheme` / `fontFamily`)。

**修复方向**:建立设计令牌 + 补齐主题子项 + 批量替换。**零功能改动、零交互改动。**

---

## 1. 页面语义图谱

### 1.1 页面总览(50 个独立页面)

| # | 页面 | 层级 | 语义 | 作用 | 行数 |
|---|---|---|---|---|---|
| 1 | `splash_page` | L0 | 品牌启动 | Logo 动画 + 初始化,无交互 | 88 |
| 2 | `auth_page` | L0 | 安全门禁 | 生物识别验证入口 | 123 |
| 3 | `oobe_page` | L0 | 首次引导 | 多步新手引导 | 351 |
| 4 | `home_page` | L1 | **对话中枢** | 会话列表(单聊),最高频入口 | 98 |
| 5 | `group_home_page` | L1 | 群聊中枢 | 群聊会话列表 | 297 |
| 6 | `my_home_page` | L1 | **角色资产** | TA 列表 + 归档切换 + 创建 | 282 |
| 7 | `world_page` | L1 | **世界资产** | 世界列表 | 251 |
| 8 | `identity_page` | L1 | **身份资产** | User Persona 列表 | 158 |
| 9 | `settings_page` | L1 | 设置中枢 | 4 大模块 9 入口 | 263 |
| 10 | `chat_page` | L2 | **核心场景** | 聊天主界面 | 954 |
| 11 | `search_page` | L2 | 全局搜索 | 跨 TA/世界/会话/消息 | 217 |
| 12 | `delete_confirm_page` | L2 | 危险操作确认 | 输入名称 + 5 秒滚动反悔 | 356 |
| 13 | `ta_editor_page` | L2 | TA 创建/编辑 | 13+ 字段,含 3 形象槽 | 759 |
| 14 | `world_editor_page` | L2 | 世界创建/编辑 | 含词条子管理 + 抽屉编辑 | **1029** |
| 15 | `identity_editor_page` | L2 | 身份编辑 | User Persona 表单 | 230 |
| 16 | `dialogue_style_page` | L2 | 对话风格 | Few-shot 示例配置 | 183 |
| 17 | `conversation_create_page` | L2 | 会话创建 | 选择 TA/世界/备注 | 200 |
| 18 | `conversation_edit_page` | L2 | 会话编辑 | 同上 | 164 |
| 19 | `group_create_page` | L2 | 群聊创建 | 选成员 + 群设定 | 234 |
| 20 | `group_edit_page` | L2 | 群聊编辑 | 同上 | 205 |
| 21 | `ai_service_settings_page` | L3 | AI 服务 | 简易/高级双模式 | 799 |
| 22 | `conversation_settings_page` | L3 | 对话与策略入口 | 4 子页导航 | 99 |
| 23 | `conversation_prompt_strategy_page` | L4 | 提示词策略 | 推进/沉浸策略 + 字数 | 308 |
| 24 | `conversation_summary_page` | L4 | 摘要与上下文 | 摘要阈值/Token 预算/世界书 | 276 |
| 25 | `conversation_send_page` | L4 | 回复与发送 | 回车/括号键/灵感/快速回复 | 162 |
| 26 | `conversation_advanced_page` | L4 | 消息与高级 | 删除/分叉/宏/正则 | 134 |
| 27 | `appearance_settings_page` | L3 | 外观入口 | 3 子页导航 | 91 |
| 28 | `appearance_theme_page` | L4 | 主题与颜色 | 明暗模式 + 强调色 | 192 |
| 29 | `appearance_app_page` | L4 | 应用与启动 | 图标/开场动画/底栏/仪表盘 | 183 |
| 30 | `appearance_chat_page` | L4 | 聊天界面 | 气泡/遮罩/半屏/快捷按钮 | 267 |
| 31 | `app_icon_page` | L4 | 换图标 | 大图预览 + 即时切换 | 166 |
| 32 | `security_settings_page` | L3 | 安全与隐私 | 生物识别 + 删除防误触 | 163 |
| 33 | `tts_settings_page` | L3 | 端侧语音合成 | 开关/朗读/Seed/模型/缓存 | 479 |
| 34 | `tts_cache_page` | L4 | 语音缓存 | 占用展示 + 清理 | 174 |
| 35 | `voice_input_settings_page` | L3 | 离线语音输入 | 模型选择/下载源/管理 | 369 |
| 36 | `bgm_settings_page` | L3 | 角色背景音乐 | 音量 + 大小上限 | 144 |
| 37 | `data_settings_page` | L3 | 数据管理 | 自动备份/ZIP/JSON 导出 | 370 |
| 38 | `advanced_settings_page` | L3 | 高级命令 | 开发者指令控制台 | 105 |
| 39 | `about_page` | L3 | 关于与开源 | 版本/成员/社区/许可入口 | 278 |
| 40 | `authors_page` | L4 | 参与人员名单 | 成员与分工 | 206 |
| 41 | `license_page` | L4 | 许可证全文 | 源码 + 美术资源许可 | 76 |
| 42 | `open_source_page` | L4 | 开源组件 | 第三方依赖清单 | 446 |
| 43 | `quick_replies_page` | L4 | 快速回复管理 | 一键发送按钮增删改 | 284 |
| 44 | `regex_rules_page` | L4 | 正则规则管理 | 正则 + 替换对 | 264 |
| 45 | `sampler_settings_page` | L4 | 全局采样参数 | 8 滑块 + 场景预设 | 405 |
| 46 | `provider_list_page` | L4 | 服务商列表 | 高级模式入口 | 260 |
| 47 | `provider_edit_page` | L5 | 服务商编辑 | 协议/BaseURL/Key | 329 |
| 48 | `model_list_page` | L5 | 模型列表 | 模型预设管理 | 293 |
| 49 | `model_edit_page` | L5 | 模型编辑 | 名称/ID/能力开关 | 476 |
| 50 | `model_sampler_settings_page` | L6 | 模型专属采样 | 与 #45 功能对齐的 7 滑块 | 439 |

### 1.2 层级与导航结构

```
L0  启动 / 认证 / 引导          splash · auth · oobe
     │
L1  资产中心(底部导航 4 项 + 抽屉 6 项)
     ├── home          对话中枢        ← 底栏 ①
     ├── group_home    群聊中枢        ← 底栏 ②
     ├── my_home       角色资产        ← 底栏 ③
     ├── world         世界资产        ← 底栏 ④
     ├── identity      身份资产        ← 仅抽屉(半隐藏)
     └── settings      设置中枢        ← 仅抽屉(半隐藏)
          │
L2  功能页 / 编辑页 / 设置分类入口
     ├── chat · search · delete_confirm
     ├── ta_editor · world_editor · identity_editor · dialogue_style
     └── conversation_create/edit · group_create/edit
          │
L3  设置主项                      ai_service · conversation_settings
                                  appearance_settings · security · tts
                                  voice_input · bgm · data · advanced · about
          │
L4  设置子项 / 二级管理            prompt_strategy · summary · send · advanced
                                  theme · app · chat · app_icon · tts_cache
                                  authors · license · open_source
                                  quick_replies · regex_rules · sampler
                                  provider_list · model_list
          │
L5  实体编辑                      provider_edit · model_edit
          │
L6  模型专属采样                  model_sampler_settings
```

### 1.3 页面类型分类(供规范引用)

| 类型 | 数量 | 页面 | 规范要点 |
|---|---|---|---|
| **导航骨架** | 3 | splash, auth, oobe | 无返回导航,全屏沉浸 |
| **一级资产页** | 6 | home, group_home, my_home, world, identity, settings | `AppScaffold` + `AppBottomNav` |
| **功能页** | 4 | chat, search, delete_confirm, dialogue_style | 专用布局 |
| **重表单编辑页** | 8 | ta_editor, world_editor, identity_editor, conv_create/edit, group_create/edit | `SettingSection` 分区 |
| **入口分类页** | 2 | conversation_settings, appearance_settings | `SettingTile` 列表 |
| **设置开关页** | 20 | 多数 L3/L4 设置页 | `SettingSection` + `SettingSwitch/Slider` |
| **实体列表页** | 3 | provider_list, model_list, quick_replies | 列表 + FAB |
| **内容展示页** | 4 | about, authors, license, open_source | 长文滚动 |

---

## 2. 设计令牌(Design Tokens)

> 落地位置建议:`lib/theme/tokens.dart`(纯常量,无依赖)。

### 2.1 圆角 `AppRadius`

**现状 13 种值 → 收敛为 5 档。**

| 令牌 | 值 | 用途 | 覆盖的现状值 |
|---|---|---|---|
| `AppRadius.xs` | **8** | 徽章、标签、小图标块、头像裁剪 | 3, 4, 6, 8, 10 |
| `AppRadius.sm` | **12** | 卡片内嵌子卡片、图片槽 | 12, 14 |
| `AppRadius.md` | **16** | **主卡片(默认)** | 16 |
| `AppRadius.lg` | **20** | 输入栏浮岛、大容器 | 19, 20, 22 |
| `AppRadius.pill` | **999** | 胶囊按钮、圆形 | 999, 28 |

**规则**
1. **默认一律 `md(16)`**。
2. 仅"卡片内嵌卡片"降级用 `sm(12)`。
3. 徽章类用 `xs(8)`。
4. **禁止新增其他圆角值**;`BorderRadius.circular("裸数字")` 视为违规。

### 2.2 间距 `AppSpacing`(8pt 栅格)

**现状 21 种值 → 收敛为 6 档。**

| 令牌 | 值 | 用途 |
|---|---|---|
| `AppSpacing.xxs` | **2** | 图标与紧邻文字(唯一非 4 倍数的例外) |
| `AppSpacing.xs` | **4** | 标题与副标题之间 |
| `AppSpacing.sm` | **8** | 行内元素间隔、图标与文字 |
| `AppSpacing.md` | **12** | 列表项之间、分组内元素 |
| `AppSpacing.lg` | **16** | **卡片之间(默认)**、卡片内边距 |
| `AppSpacing.xl` | **24** | 模块分区间隔、页面上下留白 |

**规则**
1. **所有间距必须是 4 的倍数**(`2` 为唯一例外)。
2. **禁止出现 3 / 6 / 10 / 14 / 80 / 240** 等值。归并方向:
   - `3 → 4`
   - `6 → 4` 或 `8`
   - `10 → 8` 或 `12`
   - `14 → 12` 或 `16`
   - `20 → 16` 或 `24`
   - `32 → 24`
   - `80 / 240 → 改用 `Expanded`/`Spacer` 或命名布局常量

### 2.3 内边距 `AppInsets`(页面级)

**现状 4 种写法混用 → 固定 3 种。**

| 令牌 | 值 | 用途 | 现状覆盖 |
|---|---|---|---|
| `AppInsets.page` | `symmetric(h:16, v:16)` | **所有滚动页 `ListView`(默认,禁改)** | 22/47 已符合 |
| `AppInsets.card` | `all(16)` | 卡片内容内边距 | 97 处 |
| `AppInsets.tile` | `symmetric(h:16, v:8)` | 列表项 | — |

**规则**
1. 滚动页 `ListView.padding` **一律** `AppInsets.page`(`h16/v16`)。
2. 现状 `h16/v6`(5)、`h8/v2`(5)、`h16/v12`(4)、`h12/v4`(3) 等 20+ 种变体**全部归并**。
3. 卡片内边距一律 `AppInsets.card`。
4. 卡片内 `SwitchListTile` 一律 `contentPadding: EdgeInsets.zero`。

### 2.4 高度/阴影 `AppElevation`

| 令牌 | 值 | 用途 |
|---|---|---|
| `AppElevation.flat` | **0 + 描边** | **默认:所有卡片** |
| `AppElevation.raised` | 1 档柔光 `BoxShadow(black@0.04, blur 6, offset(0,1.5))` | 浮动元素:输入栏、FAB、气泡 |

**规则**
- DNA 的视觉语言是**扁平 + 细描边**,不是阴影。
- 依据:现状 `elevation: 0` 用了 **77 处**,`BoxShadow` 仅 **2 处** —— **方向已确立,只需固化**。
- 全局 `BoxShadow` 定义收敛到 1 处(`AppShadows.soft`)。

### 2.5 描边 `AppBorder`

| 令牌 | 值 |
|---|---|
| `AppBorder.card` | `BorderSide(color: outlineVariant.withValues(alpha: 0.5), width: 1)` |
| `AppBorder.divider` | `color: outlineVariant.withValues(alpha: 0.5)`,缩进 `indent: 56` |

> **这段被手写了 76 遍**(`side: BorderSide(`),必须进 `cardTheme`。

### 2.6 透明度 `AppAlpha`

**现状 132 处 `withValues(alpha:)` 凭手感 → 收敛为 4 档。**

| 令牌 | 值 | 用途 |
|---|---|---|
| `AppAlpha.faint` | **0.04** | 极淡阴影、分隔 |
| `AppAlpha.subtle` | **0.05** | 卡片描边、弱背景 |
| `AppAlpha.half` | **0.5** | 半透明遮罩、强调容器 |
| `AppAlpha.muted` | **0.7 ~ 0.75** | 次级文字 |

### 2.7 尺寸 `AppSize`

| 令牌 | 值 | 用途 |
|---|---|---|
| `AppSize.iconInline` | **16** | 行内小图标 |
| `AppSize.iconCard` | **20** | 卡片头图标 |
| `AppSize.iconEmpty` | **48** | 空状态图标 |
| `AppSize.tileHeight` | **56 / 72** | 单行 / 双行列表项 |
| `AppSize.touchTarget` | **48** | 最小触摸目标 |
| `AppSize.contentMaxWidth` | **520** | 聊天内容区上限 |
| `AppSize.settingsMaxWidth` | **900** | 设置页内容上限 |
| `AppSize.drawerWidth` | **260** | 侧边栏宽度 |

---

## 3. 排版规范

**现状 37 处硬编码 `fontSize`(9 种值)+ 与 `textTheme` 混用。**

| 层级 | 令牌 | 字号/字重 | 用途 |
|---|---|---|---|
| 页面标题 | `titleLarge` | 20 / w600 | AppBar 标题 |
| 卡片标题 | `titleMedium` | 16 / **w700** | 卡片区块主标题 |
| 列表主文本 | `bodyLarge` | 16 / w400 | ListTile title |
| 正文 | `bodyMedium` | 14 / w400 | 消息气泡正文 |
| 说明文字 | `bodySmall` + `onSurfaceVariant` | 12 / w400 | 副标题、提示 |
| 标签 / 徽章 | `labelSmall` | 11 / w600 | `BetaTag`、状态标签 |

**规则**
1. **禁止 `fontSize:` 硬编码**,全部走 `textTheme` + `copyWith(fontWeight:)`。
2. 正文行高统一 `height: 1.45`(消息气泡已在用)。
3. **字体**:规范要求显式声明 `fontFamily`,不再依赖系统默认(当前唯一的"完全未定制"项)。
4. 所有文本**一律使用 `FitText`**(现状已执行,需保持),传入 `contrastBackground` 以自动适配对比度。

---

## 4. 色彩规范

| 令牌 | 来源 | 用途 |
|---|---|---|
| `primary` | `ColorScheme` | 强调、图标、选中态 |
| `onSurfaceVariant` | `ColorScheme` | 说明文字、副标题 |
| `outline` | `ColorScheme` | 更弱的说明文字 |
| `outlineVariant` @0.5 | `ColorScheme` | 卡片描边、分割线 |
| `surfaceContainerLow` | `ColorScheme` | 次级卡片背景 |
| `surfaceContainerLowest` | `ColorScheme` | 思考内容框 |
| `tertiaryContainer` @0.55 | `ColorScheme` | 搜索高亮 |
| `error` | `ColorScheme` | 错误提示 |

**规则**
1. **禁止硬编码 `Color(0xFF…)`。** 现有 10 处需清理:

| 现状值 | 出现 | 替换为 |
|---|---|---|
| `0xFF49454F` | 2 | `onSurfaceVariant` |
| `0xFF888888` | 1 | `outline` |
| `0xFF1a1a1a` | 1 | `surface`(闪屏,可保留为命名常量) |
| `0xFF1B1B1F` | 1 | `surface` |
| `0xFF1D1B20` | 1 | `onSurface` |
| `0xFF3B383E` | 1 | `onSurfaceVariant` |
| `0xFF6B6670` | 1 | `outline` |
| `0xFF147B74` | 2 | **保留**(品牌种子色,命名为 `AppColors.seed`) |

2. 遮罩类 `Colors.black/white` 允许保留,但需命名为 `AppColors.scrim` / `AppColors.onScrim`。
3. **统一用 `withValues(alpha:)`**,现状 21 处旧 `withOpacity(` 需迁移。
4. 透明度取值只用 `AppAlpha` 四档。

---

## 5. 组件规范

### 5.1 卡片 `AppCard`(强制统一)

现状:235 处手写(`RoundedRectangleBorder` 82 + `elevation:0` 77 + `BorderSide` 76)。

**规范:通过 `cardTheme` 全局统一,业务代码只写 `Card(child: ...)`。**

| 属性 | 值 |
|---|---|
| `elevation` | `AppElevation.flat` (0) |
| `shape` | `RoundedRectangleBorder(AppRadius.md, side: AppBorder.card)` |
| `margin` | `only(bottom: AppSpacing.lg)` |
| 内容内边距 | `AppInsets.card` |

**三种卡片变体**

| 变体 | 圆角 | 背景 | 用途 |
|---|---|---|---|
| `AppCard.primary` | 16 | `surface` + 描边 | 设置分组、表单区 |
| `AppCard.secondary` | 12 | `surfaceContainerLow` | 卡片内嵌项 |
| `AppCard.entry` | 16 | `surfaceContainerLow` | 带 icon 的导航入口 |

### 5.2 页面骨架

| 模式 | 适用页面 | 规范 |
|---|---|---|
| 主页面 | home / group_home / my_home / world / identity / settings | `AppScaffold` + `AppBottomNav` |
| 次级页面 | 所有设置子页、编辑页 | `Scaffold` + `AppBar(title: FitText)` |
| 全屏沉浸 | `chat_page` | 无 AppBar,自定义顶栏 |

**统一要求**
1. 次级页面 `body` 一律 `ListView(padding: AppInsets.page)`。
2. AppBar 标题一律 `FitText`(现状已执行,需保持)。
3. 内容宽度上限:设置页 `900`、聊天区 `520`(现状 `settings_page` 已用 900)。
4. 横竖屏由 `AppScaffold` 统一处理(横屏侧栏常驻 260 / 竖屏抽屉),页面不自行判断。

### 5.3 设置项组件族(**当前缺失,需新建**)

现状:设置项靠手工拼 `Card > Padding > Column > Row > Icon + FitText + SwitchListTile`,在 30 个设置页里重复。

| 组件 | 用途 |
|---|---|
| `SettingSection` | 一个卡片分组(标题 + 说明 + 若干项) |
| `SettingGroupHeader` | 分组标题行:`Icon(20, primary)` + `titleMedium w700` |
| `SettingDescription` | 分组说明:`bodySmall` + `outline` |
| `SettingSwitch` | 开关项(`SwitchListTile` + `contentPadding: zero`) |
| `SettingSlider` | 滑块项(label + 当前值 + Slider + 说明) |
| `SettingTile` | 可点击导航项(title + subtitle + chevron) |
| `SettingTextField` | 输入项(label + hint + 说明) |
| `SettingRadioGroup` | 单选组 |

### 5.4 空状态 `AppEmptyState`

现状:各页面手写 `Center > Column > FitText + FilledButton`。

**规范**:统一组件 = `Icon(48, outline)` + 标题(`bodyLarge`) + 说明(`bodySmall`) + 可选 `FilledButton`。

### 5.5 卡片内语序(已确立,需固化)

```
[Icon(20, primary)] + [标题 titleMedium w700]
              ↓ AppSpacing.xs (4)
        [说明文字 bodySmall, outline]
              ↓ AppSpacing.sm (8)
        [设置项 / SwitchListTile ...]
```

### 5.6 弹窗规范(已存在,需保持)

统一使用 `lib/utils/dialogs.dart`:

| 函数 | 用途 |
|---|---|
| `showConfirmDialog` | 二次确认 |
| `showTextInputDialog` | 文本输入 |
| `showInfoDialog` | 信息展示 |

均支持 `accentColor` 参数以跟随角色取色 —— **这是本项目的特色能力,新弹窗必须复用**。

---

## 6. 导航与信息层级规范

| 层级 | 规范 |
|---|---|
| **L0** | 启动 / 认证 / 引导 —— 无导航 |
| **L1** | 6 个资产中心 —— 底部导航(4 项)+ 抽屉(6 项) |
| **L2** | 功能页、编辑页、设置分类入口 —— `← 返回` |
| **L3** | 设置主项 —— `← 返回` |
| **L4** | 设置子项 / 二级管理 —— `← 返回` |
| **L5~L6** | 实体编辑、模型采样 —— `← 返回` |
| **模态** | 弹窗 / 底部抽屉(词条编辑、导出选项) |

**规则**
1. **字段级不再单独开页**;一个设置页承载同一主题的全部字段。
2. **底部导航与抽屉不得功能重叠**:抽屉只保留低频入口(identity、settings 及各资产中心的跳转)。
3. **新增功能优先并入既有 L3 页面,不新开页面**。
   - 反例:`bgm_settings_page` 应并入 `tts_settings_page`(同属"语音与多模态")。
4. **层级目标**:常规设置路径 **不超过 L4**。当前 `sampler_settings`(#45)与 `model_sampler_settings`(#50)功能重复,规范要求 `#45` 作为默认项、`#50` 作为模型覆盖,并在 UI 上明确标注继承关系。

---

## 7. 交互与密度规范

| 项目 | 规范 |
|---|---|
| 卡片间距 | `AppSpacing.lg` (16) |
| 模块间距 | `AppSpacing.xl` (24) |
| 列表项高度 | 单行 56 / 双行 72 |
| 图标尺寸 | 行内 16 / 卡片头 20 / 空状态 48 |
| 触摸目标 | ≥ 48×48 |
| 输入栏 | 浮岛式,圆角 `AppRadius.pill`(28),半透明背景 |
| 危险操作 | 必须走 `delete_confirm_page`(输入名称 + 5 秒滚动反悔) |
| 操作反馈 | 统一 `showSnack` / `showConfirmDialog` |
| 动画 | 页面转场由 `pageTransitionsTheme` 统一(Android 预测式返回 / iOS·macOS Cupertino) |

### 7.1 信息密度规范(直接关系"心智负担")

> 依据:主要入口已有副标题说明(29 处 `subtitle`),分组已建立(4 大模块),但**高级参数仍全量平铺**。

| 规则 | 说明 |
|---|---|
| **默认折叠高级参数** | 滑块类参数(采样 8 项)默认只露「场景预设」四选一,点「高级」才展开 |
| **单一入口原则** | 同主题设置合并到一页,不再横向扩张页面数 |
| **场景优先** | 参数页必须提供"一键预设";预设名称用场景词(如"天马行空""防复读") |
| **术语通俗化** | 专业概念必须配通俗说明(`sticky` → 「词条附着持续轮数」) |
| **每个入口必须有副标题** | 现状已执行(settings 9 个入口全部有 subtitle) |

---

## 8. 术语与文案规范

| 规则 | 示例 |
|---|---|
| 面向用户用通俗词 | `sticky` → 「词条附着持续轮数」 |
| 高级参数标注影响 | 「Top-P(越大越发散)」 |
| 必填项标 `*` | 「名字 *」「设定(角色人设,发送给 AI)*」 |
| 区分「设定」与「介绍」 | 设定=发送给 AI 的人设;介绍=仅卡片展示的一句话 |
| 危险操作二次确认 | 输入名称 / 长按 5 秒 |
| 可选字段标「(可选)」 | 「开场白(可选)」「作者注释(可选)」 |

---

## 9. 规范速查卡

```
圆角:  8 / 12 / 16* / 20 / 999              (*默认)
间距:  2 / 4 / 8 / 12 / 16* / 24            (*卡片间)
透明:  0.04 / 0.05 / 0.5 / 0.7
页面:  ListView(padding: h16 v16)
卡片:  elevation 0 + 圆角16 + 描边 outlineVariant@0.5 + padding 16 + margin bottom 16
图标:  行内16 / 卡片头20 / 空状态48
尺寸:  触摸≥48 / 聊天区≤520 / 设置页≤900 / 侧栏260
字号:  titleLarge20 / titleMedium16w700 / bodyLarge16 / bodyMedium14 / bodySmall12 / labelSmall11
颜色:  只用 ColorScheme,禁止 Color(0xFF...)
文字:  一律 FitText;副标题 bodySmall + onSurfaceVariant
弹窗:  只用 showConfirmDialog / showTextInputDialog / showInfoDialog
危险:  必须走 delete_confirm_page
```

---

## 附录 A:现状 → 规范 映射表

| 属性 | 现状处数 | 现状取值数 | 规范令牌数 | 归并动作 |
|---|---|---|---|---|
| 圆角 | 156 | 13 | 5 | 3/4/6/10→8;12/14→12;16→16;19/20/22→20;28/999→999 |
| 间距(height) | 403 | 14 | 6 | 3→4;6→4/8;10→8/12;14→12/16;20→16/24;32→24;80/240→布局常量 |
| 间距(width) | 117 | 7 | 6 | 同上 |
| 内边距 | 279 | 4 种写法 | 3 | ListView 统一 h16/v16;卡片统一 all(16) |
| 卡片样式 | 235 | 手写 | 0(主题) | 全部进 `cardTheme` |
| 字号 | 37 | 9 | 6 | 全部改用 `textTheme` |
| 颜色 | 10 | 8 | 2(保留) | 其余映射到 ColorScheme |
| **合计** | **≈1,086** | — | **≈25** | — |

## 附录 B:落地清单(建议顺序)

| 阶段 | 内容 | 消除魔数 | 风险 | 功能影响 |
|---|---|---|---|---|
| **P0** | 新建 `lib/theme/tokens.dart`(AppRadius / AppSpacing / AppInsets / AppElevation / AppBorder / AppAlpha / AppSize / AppColors / AppShadows) | — | 无 | 无 |
| **P0** | `main.dart` 的 `ThemeData` 补 `cardTheme` + `appBarTheme` + `listTileTheme` + `inputDecorationTheme` + `dividerTheme` + `snackBarTheme` | **235** | 无 | 无 |
| **P1** | 批量替换硬编码圆角 / 间距 / 内边距为令牌 | **799** | 低 | 无 |
| **P1** | 清理硬编码颜色 + 迁移 `withOpacity` → `withValues` | **31** | 低 | 无 |
| **P2** | 注册 `fontFamily` + 统一 `textTheme`,移除硬编码 `fontSize` | **37** | 低 | 无 |
| **P2** | 新建 `SettingSection` 组件族,重构 30 个设置页 | — | 中 | 无 |
| **P2** | 新建 `AppEmptyState`,替换各页手写空状态 | — | 低 | 无 |
| **P3** | 导航重构:底栏与抽屉去重;`bgm_settings` 并入 `tts_settings` | — | 中 | 轻微 |
| **P3** | 高级参数默认折叠(采样页) | — | 中 | 交互微调 |

**P0 + P1 合计可消除约 1,065 处魔数,且不改动任何功能与交互。**

## 附录 C:验证方式

| 阶段 | 验证手段 |
|---|---|
| P0/P1 | `flutter analyze` 无新增告警;全局搜索确认无残留 `BorderRadius.circular("裸数字")`、无 `fontSize:`、无 `Color(0xFF…)` |
| P2 | `flutter test` 全绿(现有 100+ 用例);手动走查 5 个代表性页面(设置主页 / 摘要与上下文 / TA 编辑 / 聊天 / 世界编辑)的深浅色模式 |
| P3 | 手动走查导航闭环;确认无死链、无重复入口 |

---

*本规范为纯文档产出,未改动任何代码。*
