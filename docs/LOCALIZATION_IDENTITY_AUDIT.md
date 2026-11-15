# 本地化身份审计：谁在拿「名字」当 key

> 触发原因：设置分组曾用中文字符串当 key（`settingsGroupOrder` + `Map<String, IconData>{'AI 接入': …}`），
> 一旦出英文界面，Map 全部失配、排序退化。同类问题被顺扫了一遍。
>
> 扫描范围：`lib/` 全部 dart 文件。精确判据（排除三元表达式与字符串拼接的误报）：
> 中文当映射键、中文当 `case`/`==` 比较、中文当控件 `value`、中文当查找条件。
>
> 结论：**中文当映射键 0 处**；中文当比较 1 处；中文当控件 value 4 处（同一处性别下拉）；
> 另有两处「拿 Dart 标识符当持久化 key」。

## 已修

* **设置分组用稳定 id**（2026-11）：`SettingsGroupId` 枚举 + `SettingsGroupSpec(id, title, icon)`
  单一列表（列表顺序即界面顺序），入口用 `groupId` 而不是 `groupTitle`。
  见 `lib/pages/settings/spec/settings_spec.dart`、`spec/settings_tree.dart`。
  守卫测试：入口 groupId 必须存在、分组 id 唯一、"第 7 组是社区"按 id 断言。
* **设置搜索去掉 aliases**：别名是第二份真相（改文案不同步、翻译要再翻一遍），
  检索面已由「分组名 + 入口标题/副标题 + id + 分组标题/说明 + 字段标题/副标题/hint + 选项文案」覆盖。
  真出现搜不到的案例再加，并配测试。

---

## A 级 · 名字被当成持久化身份（会丢数据或断逻辑）

### A1. `TA.gender` 用中文字面量当枚举 —— **已按「中文即 ID」方案处理**

原状：`ta.gender` 的取值 `'男' / '女' / '无性' / '其他'` 同时是存储值、
导出值、社区接口值与显示文案（`card_payload.dart:24` 原样发给服务端）。
默认值 `'无性'` 曾在四处各写一遍。

**决定（2026-11）**：不改服务端、不迁存档。**让既有中文值直接当稳定 ID**，
显示统一走映射：

| 层 | 位置 | 规则 |
|---|---|---|
| 身份 | `lib/models/ta_gender.dart` 的 `TaGender.id` | `'男' / '女' / '无性' / '其他'`，一字不改（存档与服务端靠它） |
| 显示 | `TaGender.label` + `TaGender.labelOf(id)` | 已知 ID → label；**未知 ID 原样返回**（社区卡可能带任意字符串，不能吞数据）；null/空 → 空串 |
| 写入 | `TaGender.selectable`（value=id，child=label） | 编辑页下拉不再把中文字面量写两遍 |

为什么这不是「换个地方继续用中文当 key」：ID 从此**只出现在存储与协议边界**，
界面一律经 `labelOf` 转换，代码里不再有「拿 gender 字符串做判断」的分支。
将来出英文界面只改 `label` 这一列，存档、导出文件、服务端协议都不用动。

已改的显示点：`ta_showcase_page`、`delete_preview_builders`、`ta_editor_form`
（下拉 value/label 分离，未知值补一项避免 Dropdown 断言）、
`island_app/card_detail_page`、`island_app/widgets/card_tile`、
`island_app/swipe_body`。

守卫：`test/ta_gender_test.dart` 钉住「四个 ID 逐字不变」「未知值原样显示」
「显示点必须走 labelOf」「编辑页 value 是 id 而不是中文字面量」。

**留的尾巴**：`'无性'` 仍作为默认值散在导入路径里
（`ta.dart:132`、`ta_export_import_models.dart:135`、`ta_export_import_service.dart:273`），
可以逐步换成 `TaGender.fallbackId`，不影响本次结论。

### A2. 拿错误文案做控制流

`lib/island_app/punishments_page.dart:143`

```dart
onRetry: _error == '请先登录后再查看' ? null : _load,
```

改一个字，重试按钮就出现/消失了。
**修法**：换成错误码（`enum LoadError { needLogin, network, unknown }`），文案只负责显示。

### A3. 导出文件的兜底名是中文，会写进文件

`lib/services/conversation_export_import_service.dart:246-260`：
`'群聊'` / `'对话'` / `'角色'` 作为缺省名写进导出包。语言一变，导出内容跟着变。

---

## B 级 · 拿代码标识符当持久化 key（改个名字就静默丢设置）

| 位置 | 现象 |
|---|---|
| `lib/models/prompt_strategy.dart:650-660` | `_byName<T extends Enum>` 用 `v.name` 反解持久化值 |
| `lib/widgets/glass_quality.dart:46` | SharedPreferences 存 `q.name` |

不是本地化问题，是稳定性问题：重命名枚举成员即令旧数据读不回来。

**对照正确做法**：`lib/services/app_icon_service.dart:55-78` 的
`AppIconOption(key, label, assetPath, alias)` —— 持久化用 `key`、显示用 `label`、
平台通道用 `alias`，三件事分开。

---

## C 级 · 确认无问题（避免重复排查）

| 位置 | 模式 |
|---|---|
| `AppIconOption` | key / label / alias 三分离 |
| `VoiceModelOption`（`lib/models/voice_models.dart:20-33`） | `id` + `label` |
| `AppNavTarget`（`lib/island_app/app_drawer.dart:126-138`） | 枚举当目标，中文是单独传入的文案 |
| `WorldPersonGender` / `WorldEntryType` | 枚举 + ASCII JSON 映射 |
| `QuickReply` | `id` + `label` + `group` |
| Hive box 名 / SharedPreferences 键 | 全 ASCII 常量 |
| 设置声明层（`lib/pages/settings/spec/**`） | 分组用 `SettingsGroupId`，字段用英文 id |

## D 级 · 文案硬编码，但不是身份问题（暂不动）

`lib/services` 里约 110 处中文字面量，全是错误提示 / 按钮 / 确认框文案；
聊天侧还有中文 prompt 直接拼进模型 payload（`lib/pages/chat/builders/chat_payload_builders.dart`、
`lib/pages/chat/chat_summary.dart`）。这些是**值**不是 key，做 i18n 时统一抽字符串表即可。

另外记一笔：社区性别筛选的取值来自服务端（`lib/island_app/explore_body.dart:398-402`
直接用 `_meta.genders` 渲染并回传），即**协议里已经有中文枚举值在跑**，
这一条只改客户端解决不了。

---

## 修复顺序建议

1. ~~`TA.gender`（A1）~~ —— 已按「中文即 ID + 显示映射」处理，见上。
2. `punishments_page` 的错误码（A2）。
3. `_byName` 两处（B）—— 显式 key 映射表，并加「旧值仍能读回来」的测试。
