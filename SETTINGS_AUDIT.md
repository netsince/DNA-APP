# 设置页信息设计诊断

> **状态:已全部落地**(2026-09-27)。本文件同时作为改造记录留存。
>
> | 指标 | 改造前 | 改造后 |
> |---|---|---|
> | 手写 `Card > Padding > Column` 样板(设置页) | **26 处 / 13 页** | **0 处** |
> | `SettingSection` 使用 | 10 处(仅 3 页) | **47 处** |
> | `SettingTile` 业务使用 | **0 处** | 2 处 |
> | 超 20 字提示文案 | **11 条**(最长 71 字) | **2 条**(均为宏名说明,实际渲染约 12 字宽) |
> | 数值项折叠组件 | 0(仅整卡 `ExpansionTile`) | **28 处**(整型 8 / 文本 3 / 浮点 17) |
> | 折叠粒度 | 一次展开 3~10 个控件 | **每个参数独立折叠** |
> | 最大设置页 | `ai_service_settings_page` **796 行单文件** | 拆为 8 文件,**主文件 104 行**(-87%) |
> | 新增约束测试 | — | `test/settings_design_test.dart`(7 项) |
>
> **顺带修掉的真实缺陷**:
> * `repetitionPenaltySlope` 滑块上限 `10.0`,但 `AppController` 里 `clamp(0.0, 1.0)`
>   —— **90% 的可拖区间是无效的**,一保存就被夹掉。已把上限改为 `1.0`。
> * `ai_service_settings_page` 密钥框原为永久 `obscureText: true`,无法核对已填内容。已加显示/隐藏按钮。
> * **折叠组件用 `AnimatedCrossFade` 实现,等于没折叠** —— 该组件会把两个子树
>   **都**建进 widget tree(只做透明度/尺寸动画),收起态依然创建 `Slider`、
>   说明文字等控件。已改为 `AnimatedSize` + 条件插入,收起态子树根本不存在。
>   *此缺陷由运行时测试(`test/settings_widget_runtime_test.dart`)发现 —— 静态
>   正则数数完全看不出来,只有真正渲染才能暴露。*

---

## 一、核心结论

现有做法是 **"有一个设置项,就平铺一行"**。所以:

* 页面越长越乱,**与分类粒度无关** —— 哪怕拆成 10 个页面,每页还是这个样子;
* 所有设置项的**视觉重量完全相同**,眼睛没有落点,只能逐行阅读;
* 说明文字与正文**同等醒目**,大量重复的"默认值/范围"文字淹没真实内容。

**一句话:这些页面是"配置项清单",不是"信息设计"。**

---

## 二、四个量化病因

### 病因 1:组件族建了但没用起来(最严重)

我在 P2 建立了 `SettingSection` / `SettingSwitch` / `SettingTile` / `SettingHint` 组件族,用于固化「图标 + 标题 + 说明 → 设置项」的视觉语序。

**实测使用情况:**

| 组件 | 全项目使用 | 实际分布 |
|---|---|---|
| `SettingSection` | 10 处 | `appearance_display_page`(5)、`security_settings_page`(2)、`tts_settings_page`(1)、组件自身定义(2) |
| `SettingSwitch` | 15 处 | `appearance_display_page`(9)、`security_settings_page`(3)、`tts_settings_page`(1)、定义(2) |
| `SettingTile` | **1 处** | **仅组件自身定义,零业务使用** |
| `SettingHint` | **3 处** | 2 处业务 + 1 处定义 |

**25 个设置页里,只有 3 个真正用了组件族**(其中 2 个是我上轮刚写的)。
**13 个页面仍在手写 `Card > Padding > Column` 样板**,合计 **26 处**。

后果:设置主页(新写的,用了规范语序)和子页(手写样板)长得**不一样** —— 用户点进去会感觉"换了个 App"。

### 病因 2:卡片标题层级扁平

`titleMedium + AppWeight.medium` 是唯一的卡片标题样式,**所有卡片标题一样大一样重**。

| 文件 | 卡片标题数 |
|---|---|
| `tts_settings_page` | 4 |
| `conversation_summary_page` | 3 |
| `voice_input_settings_page` | 3 |
| `data_settings_page` | 3 |
| `conversation_advanced_page` | 2 |
| `conversation_send_page` | 2 |

**问题**:当一页有 3~4 张卡时,卡片标题本该是"导航锚点",但因为完全同质,反而变成了**噪音**。用户在 `conversation_summary_page` 里看到 3 个同样大小的标题,无法一眼判断"哪张卡是我要的"。

### 病因 3:提示文字过长(11 条需折行)

`hintText` / `subtitle` 超过约 30 个中文字符就会折行,破坏"一行一个信息"的节奏。

**实测 11 条超长**(最长 71 字):

| 字数 | 文件 | 文本 |
|---|---|---|
| **71** | `conversation_advanced_page` | 支持在人设与对话中解析 `{{char}}`、`{{user}}`、`{{roll 1-100}}`、`{{random 选项A\|选项B}}` 等动态占位符。 |
| **60** | `conversation_advanced_page` | 已配置 N 条过滤/替换规则 |
| 41 | `conversation_send_page` | 生成灵感候选项时一并携带剧情摘要,建议更贴合上下文(默认关闭以节省 Token)。 |
| 38 | `conversation_send_page` | 在输入框旁放置「()」按钮,一键插入括号并聚焦中间,方便撰写动作与神态描写。 |
| 38 | `sampler_settings_page` | Top-P / Top-K / Min-P / 重复惩罚。多数模型无需调整。 |
| 34 | `conversation_advanced_page` | 自动按正则表达式过滤或替换消息内容(如清除口癖、特定标记或错别字)。 |
| 33 | `voice_input_settings_page` | 国内优先走 ModelScope 镜像,海外自动尝试 GitHub |
| 32 | `conversation_advanced_page` | 右键消息可选择「从此处分叉」,从历史节点另起新会话探索不同支线。 |
| 31 | `tts_settings_page` | 含引号时仅读说话台词,跳过动作与旁白描写(括号内容始终跳过)。 |
| 30 | `conversation_advanced_page` | 长按或右键消息时显示「删除本条」选项,仅移除选中的单条消息。 |
| 30 | `sampler_settings_page` | 温度、频率惩罚、存在惩罚。不确定时建议直接使用上方场景预设。 |

**`conversation_advanced_page` 一页独占 5 条**,是重灾区。

**更根本的问题**:这些长句里的信息**大部分不是用户此刻需要的**。
例如 71 字那条,`{{char}}` / `{{user}}` 是可用的宏名 —— 这属于**参考手册**,不该塞在设置项旁边。

### 病因 4:数值输入用"文字描述范围"

`conversation_summary_page` 的 7 个输入框全部这样写:

```
┌─────────────────────────────────┐
│ 按对话轮数触发（轮）              │  ← labelText
│ 默认 200，范围 10-1000           │  ← hintText
└─────────────────────────────────┘
```

**问题**:`hintText` 在描述一个**数值范围**,而范围本可以是控件的物理属性。

对比:`sampler_settings_page` 已经在用**滑块**,范围由滑块边界表达,不需要任何文字:

```
温度                        ──●────────  0.8
                          0          2.0
```

**同一个 App 里,两页采用了两种根本不同的数值输入范式。**

而且 `conversation_summary_page` 282 行里,有 **7 个 TextField + 7 个 save 方法 + 7 个 controller**,样板代码占比极高。

---

## 三、逐页诊断

按"乱"的程度排序。**P0 = 明显需要改,P1 = 建议改,P2 = 可不动。**

### P0:重度问题

| 页面 | 行数 | 设置项 | 主要问题 |
|---|---|---|---|
| **`conversation_summary_page`** | 283 | 8 | 7 个输入框全部"label + 范围提示"双行;3 张卡标题同质;**世界书 3 个参数混入,与摘要主题无关** |
| **`conversation_advanced_page`** | 136 | 5 | **5 条超长提示(最长 71 字)**;4 个开关全是"高级能力",用户难以判断该不该开 |
| **`tts_settings_page`** | 538 | 4 | 4 张卡;538 行里大量手写样板;功能最多但结构最散 |

### P1:中等问题

| 页面 | 行数 | 设置项 | 主要问题 |
|---|---|---|---|
| `sampler_settings_page` | 423 | 10 | 10 个滑块平铺,靠折叠缓解中;但 2 条提示超 30 字 |
| `models\model_sampler_settings_page` | 446 | 9 | 与上页功能重复(设计规范已指出),9 个滑块 |
| `voice_input_settings_page` | 381 | 3 | 3 张卡但仅 3 个设置项,**卡片比内容多**;1 条 33 字提示 |
| `conversation_send_page` | 162 | 3 | 3 张卡,2 条超长提示 |
| `quick_replies_page` | 299 | 3 | **1 条 52 字提示** |
| `ai_service_settings_page` | **833** | 4 | **全项目最大的设置页**;8 张卡;简易/高级双模式导致复杂度高 |
| `models\model_edit_page` | 508 | 5 | 2 张手写卡,2 条超长提示(25 字) |

### P2:可不动

| 页面 | 说明 |
|---|---|
| `appearance_display_page` | 已用组件族(上轮新写) |
| `security_settings_page` | 119 行,已用组件族,结构干净 |
| `data_settings_page`、`about_page`、`regex_rules_page`、`app_icon_page`、`tts_cache_page`、`authors_page`、`open_source_page`、`license_page` | 结构简单或以展示为主 |
| `models\provider_list_page`、`models\model_list_page`、`models\provider_edit_page` | 列表/编辑页,非设置项堆叠 |
| `advanced_settings_page` | 117 行,结构简单 |
| `conversation_prompt_strategy_page` | 325 行,4 项,相对清晰 |

---

## 四、统一改法(四条规矩 + 一套组件)

### 规矩 1:设置项必须"可折叠"

**收起时显示「名称 + 当前值」,展开后才显示控件。**

```
▼ 阶段剧情摘要                          [开关]
   按对话轮数触发            200 轮     ← 收起态:一行只读
   按新增字数触发           6000 字
```

* 一屏从"看 5 个输入框"变成"看 5 行摘要",**视觉噪音减半**;
* 需要改哪个再展开,**改的时候才有控件**。

**已有先例**:`sampler_settings_page` 的 8 个滑块已做默认折叠。**把同样手法推广到所有数值设置**。

### 规矩 2:数值输入优先用滑块,而非文本框

范围由**滑块边界**表达,不需要 `hintText` 描述。

| 场景 | 控件 |
|---|---|
| 有明确上下限、步进可枚举 | **滑块 + 右侧数值**(如 0-100 的强度) |
| 范围极大或不定(如 Token 预算 0-100000) | **文本框**,但范围提示移到展开后的说明区 |
| 布尔 | 开关 |

**统一后收益**:`conversation_summary_page` 的 7 个输入框可减少到 2~3 个,且提示文字从 7 条降到 2~3 条。

### 规矩 3:长说明移到"展开后",不在收起态占位

| 信息类型 | 位置 |
|---|---|
| **一句话价值**(≤ 20 字) | 收起态的 subtitle |
| **参数范围 / 默认值** | 展开后的说明文字 |
| **宏名、语法、示例** | **参考手册**,移到独立页面或用 `SettingHint` 折叠 |

**特别是 71 字那条宏变量说明** —— `{{char}}` 等宏名属于参考手册,应移出设置项旁边。

### 规矩 4:卡片标题建立层级

| 层级 | 样式 | 用途 |
|---|---|---|
| **分区标题** | `AppTextStyles.sectionTitle`(16/Medium)+ **图标** | 一页 3~4 处,作为导航锚点 |
| **设置项标题** | `bodyLarge`(16/Regular) | 具体设置项 |
| **说明** | `bodySmall`(12/outline) | 收起态一句话价值 |

**关键**:分区标题**必须带图标**,且与设置项标题**字重不同**(Medium vs Regular)—— 现在两者完全相同,是扁平感的来源。

### 组件:推广 `SettingSection` 组件族

强制所有设置页使用 `SettingSection` / `SettingSwitch` / `SettingTile` / `SettingHint`,
**禁止手写 `Card > Padding > Column`**。

收益:
* 视觉语序统一,设置主页与子页不再"像两个 App";
* 13 个页面、26 处样板代码消除;
* 后续改视觉只需改组件。

---

## 五、建议的落地顺序

| 批次 | 范围 | 内容 |
|---|---|---|
| **第 1 批** | 2 个 P0 页面 | `conversation_summary_page`(折叠 + 滑块化 + 拆世界书)、`conversation_advanced_page`(重写 5 条长提示 + 分组) |
| **第 2 批** | 组件族推广 | 13 个手写卡片页改用 `SettingSection`;`SettingTile` 接入业务 |
| **第 3 批** | 长提示清理 | 清理剩余 6 条超 30 字提示;建立文案长度约束测试 |
| **第 4 批** | 数值输入统一 | 评估 `sampler_settings_page` / `model_sampler_settings_page` 的滑块范式,抽取共享组件 |

**建议先做第 1 批** —— 用两个最严重的页面验证"折叠 + 滑块化 + 层级"这套改法是否真的解决了问题,
再决定是否推广。**避免一次性大改后发现方向不对。**

---

## 六、附带发现

1. **`ai_service_settings_page` 833 行**,是全项目最大文件,内含 8 张卡 + 简易/高级双模式。**建议单独评估**是否拆分。
2. **`SettingTile` 零业务使用** —— 组件建了却没接入,说明当时推广不彻底。
3. **`model_sampler_settings_page` 与 `sampler_settings_page` 功能重复**(设计规范已记录),两页共 869 行、19 个滑块。
4. **数值输入的两种范式并存**:摘要页用文本框,采样页用滑块 —— 同一 App 内不一致。
