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

### A1. `TA.gender` 用中文字面量当枚举，且已经写进服务端协议

| 位置 | 现象 |
|---|---|
| `lib/models/ta.dart:27` | `final String gender;` —— 取值 `'男'` / `'女'` / `'无性'` / `'其他'` |
| `lib/pages/ta_editor/ta_editor_form.dart:608-611` | `DropdownMenuItem(value: '男', …)`：显示文案 == 存储值 |
| `lib/models/ta.dart:105` | 存进 Hive：`'gender': gender` |
| `lib/services/ta_export_import_models.dart:92` | 写进导出文件 |
| `lib/island_app/card_payload.dart:24` | **发进社区接口**：`'gender': ta.gender` |
| `lib/island_app/card_detail_page.dart:1219` | 从服务端取回后原样显示 |

默认值 `'无性'` 在四处各写一遍：`ta.dart:132`、`ta_export_import_models.dart:135`、
`ta_export_import_service.dart:273`、`ta_editor_form.dart:160`。

**同一仓库里已有正确做法**：`lib/models/world.dart:101-154` 的 `WorldPersonGender`
是枚举 + ASCII JSON 映射（`'male'` / `'female'` / `'other'`）。

**修法**：新建 `TaGender` 枚举 + ASCII 映射；读取时兼容老存档里的四个中文值；
发布 payload 改发 ASCII（需要与服务端确认兼容策略，属于跨端改动）。

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

1. `TA.gender`（A1）—— 唯一已经污染服务端协议的，改早比改晚便宜。
2. `punishments_page` 的错误码（A2）。
3. `_byName` 两处（B）—— 显式 key 映射表，并加「旧值仍能读回来」的测试。
