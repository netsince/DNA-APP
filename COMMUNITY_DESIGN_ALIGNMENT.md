# 社区（DNAISLAND）与主程序的设计接轨方案

>本文回答一个问题：**社区那一半界面，怎么长得像主程序？**
>
>结论先行：社区和主程序**已经共享颜色主题**（内嵌时直接用主程序的 `Theme`），
>但**不共享设计语言** ——对齐、字重、组件、动效、版心各写各的。
>因此接轨不是「重做视觉」，而是**把社区换成主程序的那套零件**。

## 1.现状：接轨到什么程度（P0/P2 完成后的实测）

下面是**脚本现场统计**的结果（`lib` =主程序 213 个 dart 文件，`lib/island_app` =社区 86 个）。
数字随代码变化，**重新生成即可，不要手抄**。

|令牌 |主程序 |社区 |判定 |
|---|---:|---:|---|
| `AppSpacing` | 270 | 167 | ✅已接轨 |
| `AppRadius` | 52 | 109 | ✅已接轨 |
| `AppInsets` | 44 | 31 | ✅已接轨 |
| `AppElevation` | 8 | 0 | ❌未采用 |
| `AppBorder` | 8 | 0 | ❌未采用 |
| `AppTextStyles` | 48 | 0 | ❌未采用 |
| `AppMotion` | 21 | 12 | ⚠️部分采用 |
| `AppSize` | 73 | 4 | ⚠️部分采用 |
| `AppFontSize` | 45 | 56 | ✅已接轨 |
| `AppWeight` | 90 | 10 | ⚠️部分采用 |
| `AppLineHeight` | 10 | 14 | ✅已接轨 |

|裸写 |主程序 |社区 |判定 |
|---|---:|---:|---|
| BorderRadius.circular(裸值) | 64 | 0 | ✅已清零 |
| EdgeInsets.all(裸值) | 70 | 0 | ✅已清零 |
| FontWeight.w800/w700/bold | 0 | 0 | ✅已清零 |
| centerTitle:true | 0 | 0 | ✅已清零 |
| Duration(milliseconds:裸值) | 56 | 3 | ⚠️同量级 |

> `Duration(milliseconds:裸值)` 残留的 3 处是**故意保留**的：`api/client.dart` 的重试间隔、
> `fade_in_image.dart` 的 1400ms、`shimmer.dart` 的 1500ms ——它们不是交互动效。

### 一眼可见的四个「两个世界」（P0 已修掉前两个）

1. ~~**AppBar标题对齐**：主程序57个 AppBar 全部左对齐；社区37个里17个居中。~~ **已修：社区现在 0 处居中**
2. ~~**字重**：主程序 `w600/w700/bold` 为 0（内置字体只有 400/500，更强字重会被 Flutter 人为描边伪造，中文小字会糊）；社区有 2 处 `w800`。~~ **已修：社区现在 0 处**
3. **空状态**：主程序用 `AppEmptyState`，社区自建 `EmptyState`，图标尺寸、间距、字号层级都不同 ——
 同样是「暂无数据」，两边长得不一样。**（这就是 P1 要解决的事，见第 4 节）**
4. **版心**：主程序由栏目壳统一收窄（消息760 /我家1040 /设置900），
 社区这一栏是 `contentMaxWidth: double.infinity`，**铺满整窗**。（已给主要页面补了版心，见 `wide_body.dart`）

## 2.三条接轨原则

### 原则一：**不建第二套令牌**

主程序 `lib/theme/tokens.dart`里有15个令牌类：
`AppRadius` / `AppSpacing` / `AppInsets` / `AppElevation` / `AppBorder` / `AppShadows` /
`AppAlpha` / `AppSize` / `AppFont` / `AppFontSize` / `AppWeight` / `AppLineHeight` /
`AppTextStyles` / `AppMotion` / `AppColors`。

社区只有1个 `island_app/theme/app_dimensions.dart`（`kRadiusSm/Md/Lg`、`kPagePadding`、`kCardGap`）。

**做法**：社区**直接用主程序的令牌**，`app_dimensions.dart`逐步退场（保留一个版本周期做迁移缓冲，
每个常量在注释里标注它对应主程序哪个令牌）。**不要在社区新增任何裸数字常量**。

### 原则二：**共享件下沉，而不是让社区将就**

有一种情况是**社区做得更好**：它有三态齐全的 `EmptyState` / `LoadingState` / `ErrorState`
（还有 `compact`变体，能嵌进卡片和网格），而主程序的空态只有一个 `AppEmptyState`，
加载/错误态则是散在22处裸用的 `CircularProgressIndicator`。

**做法**：把这套三态组件**提到共享层**（如 `lib/widgets/state_views.dart`），两边都用它；
主程序现有 `AppEmptyState`退化为它的薄封装（保持旧调用点不动）。
接轨方向应当是**向更好的那一侧收敛**，而不是让社区自降一档。

### 原则三：**用测试守住，而不是靠记性**

项目已有这个传统（`font_spec_test`、`settings_design_test`、`font_scale_test`都是静态扫描），
但**扫描范围目前只覆盖 `lib`、未显式包含 `island_app`**，所以社区能悄悄破规则。

**做法**：把现有静态约束的扫描范围明确扩到 `lib/island_app`，并新增两条：
*禁止 `w600/w700/w800/bold`（已有测试，扩范围即可）；
*禁止 `AppBar(...)`出现 `centerTitle: true`（新增）。

这样「接轨」不是一次性的清理，而是**结构上不再退化**。

## 3.分四批落地

|批次 |内容 |涉及处数 |预计 |风险 |状态 |
|---|---|---:|---|---|---|
| **P0硬规则** |①2处 `w800` → `AppWeight.medium`；②17处 `centerTitle: true`删除 |19处 |约1小时 |极低 | ✅已完成 |
| **P2数值收敛** |社区 `BorderRadius.circular(裸值)`93处、`EdgeInsets.all(裸值)`69处 → `AppRadius` / `AppSpacing` / `AppInsets`；12处交互动效 → `AppMotion` |174处 |约1天 |中（圆角/间距有肉眼可见变化） | ✅已完成 |
| **P1组件** |三态组件下沉共享层（详见第 4 节） |43处调用 +3个组件 |约半天 |中（要动主程序） | ✅已完成 |
| **P3描边与动效** |`AppBorder.cardShape`/`dividerIndent`、`AppElevation.flat`、`AppTextStyles.buildTextTheme` 引入社区 |6处 +2处主题 |约半天 |低 | ✅已完成 |

### P0 / P2的验收标准（已达标，可复查）

```
grep -r "FontWeight.w[678]00\|FontWeight.bold" lib/island_app  # 空
grep -r "centerTitle: true" lib/island_app                      # 空
grep -rE "BorderRadius\.circular\(\s*[0-9]" lib/island_app     # 空
grep -rE "EdgeInsets\.all\(\s*[0-9]" lib/island_app            # 空
flutter analyze                                                  # No issues
```

### P0 / P2 实测结果

|指标 |改前 |改后 |
|---|---:|---:|
| `BorderRadius.circular(裸值)` |93 |**0** |
| `EdgeInsets.all(裸值)` |69 |**0** |
| `FontWeight.w800` |2 |**0** |
| `centerTitle: true` |17 |**0** |
| `Duration(milliseconds:裸值)`（交互动效） |12 |**0** |
| `AppRadius` 采用 |16 |**109** |
| `AppSpacing` 采用 |129 |**167** |
| `AppInsets` 采用 |**0** |**31** |
| `AppMotion` 采用 |**0** |**12** |

> 动效替换时**故意保留了** `1400ms` / `1500ms`（骨架屏与 Shimmer 的循环节奏，不是交互动效）和 `400ms`（网络重试间隔）。把它们塞进 `AppMotion` 会破坏语义。

> ⚠️ 批量替换 `const Duration(...)` → `AppMotion.fast` 时，**必须同时去掉 `const`**：
> `AppMotion.fast` 是常量**引用**不是构造函数，`const AppMotion.fast` 直接编译失败。
> `EdgeInsets` 改成 `AppInsets.card` 同理。这两类替换一漏就是几百条 error。

## 4.P1方案：三态组件下沉（✅已完成）

### 4.1为什么不是「社区改成用 AppEmptyState」

这是本方案里**唯一一处方向相反**的接轨：社区那一套更完整，应当**向社区收敛**。

|能力 |主程序 `AppEmptyState` |社区 `EmptyState`/`ErrorState`/`LoadingState` |
|---|---|---|
|空态 |✅ |✅ |
|**错误态** |❌ 无（主程序靠散落的 `CircularProgressIndicator` 或手拼） |✅ `ErrorState`（含重试按钮） |
|**加载态** |❌ 无（22 处裸用 `CircularProgressIndicator`） |✅ `LoadingState`（可带提示文字） |
|**紧凑变体** |❌ 无 |✅ `compact`（图标 32，用于嵌进卡片/网格） |
|图标尺寸走令牌 |✅ `AppSize.iconEmpty`=48 |⚠️ 硬编码 44/40/32 |
|文字支持缩放 |✅ `FitText` |✅ `Text`（都合规） |
|按钮层级 |`FilledButton`（主操作） |`OutlinedButton`（次操作） |

**结论**：主程序缺的是**错误态和加载态**，社区缺的是**令牌化**。
下沉到共享层时，以社区的 API 为骨架，把它的硬编码数值换成令牌。

### 4.2目标文件与职责

新建 `lib/widgets/state_views.dart`（共享层，两套 App 都能用）：

```dart
// 空态 / 错误态 / 加载态，全局唯一实现。
class AppEmptyState  extends StatelessWidget { ... }  // 承载原 AppEmptyState 的全部参数
class AppErrorState  extends StatelessWidget { ... }  // 新增：主程序此前没有
class AppLoadingState extends StatelessWidget { ... }  // 新增：主程序此前没有
```

三者的**参数合并表**（必须全部保留，否则既有调用点会破）：

|组件 |参数 |来源 |
|---|---|---|
| `AppEmptyState` | `icon`(可空)、`title`、`description`、`actionLabel`、`onAction`、`actionIcon` |主程序 `AppEmptyState` 全部 |
| | `message`（= `description` 的别名）、`compact` |社区独有，**合并时保留** |
| `AppErrorState` | `message`（默认「加载失败」）、`onRetry`、`compact` |社区 `ErrorState` 全部 |
| `AppLoadingState` | `message`（可空） |社区 `LoadingState` 全部 |

> ⚠️ **`description` 与 `message` 是同义参数**，合并时二选一为主名，另一个保留为兼容别名，
> 否则要么改主程序 4 处调用、要么改社区 2 处调用。**优先不改调用点**。

### 4.3图标尺寸与间距：统一到令牌（这是真正的「统一设计值」）

探查到的三方差异，下沉时必须拉平：

|项 |主程序 |社区 |下沉后 |
|---|---|---|---|
|空态图标 | `AppSize.iconEmpty` = **48** |硬编码 **44**（compact 32） | `AppSize.iconEmpty` / `AppSize.iconEmptyCompact`（新增=32） |
|错误态图标 |（无） |硬编码 **40** | `AppSize.iconEmptyCompact`=32 或用 48，**统一取 40 的最近档** |
|空态内边距 | `AppInsets.page`（h16/v16） | `EdgeInsets.all(AppSpacing.xl)` = **24** | `AppInsets.page` |
|图标与标题间距 | `AppSpacing.hLg`（16） | `SizedBox(height: 10)`（**非栅格**） | `AppSpacing.sm`（8）或 `md`（12） |
|标题字号 | `ts.bodyLarge` | `ts.titleMedium` + `w500` | `ts.bodyLarge`（主程序口径，标题不该比正文大两档） |
|操作按钮 | `FilledButton` +可选 icon | `OutlinedButton` | `FilledButton`（空态的主操作） |
|错误态重试按钮 |（无） | `OutlinedButton` | `OutlinedButton`（错误态是次操作，与空态区分） |

> **`SizedBox(height: 10)` 是个典型信号**：10 不在 4pt 栅格里（可用的只有 2/4/8/12/16/24）。
> 这类「顺手写的数」是社区视觉和主程序对不齐的微观来源。

### 4.4迁移路径（三步，每步可独立回滚）

**第 1 步：新建共享件（不改任何调用点）**

1. 写 `lib/widgets/state_views.dart`，三个组件、参数为 4.2 的并集、数值为 4.3 的令牌化结果。
2. 删掉 `lib/widgets/app_empty_state.dart` 里的旧实现，整个文件只剩一行转发：

```dart
// 旧名 AppEmptyState 由共享件提供，主程序 7 处调用一行都不用改。
export 'state_views.dart' show AppEmptyState;
```

> **为什么是 `export` 而不是留一个同名薄封装**：薄封装等于永久保留「两套实现」的可能性——
> 以后有人只改其中一个，就又是一次不一致。`export` 是单向的：只有一份代码，两个名字指向它。

> ⚠️ 注意 `export` 只导出 `AppEmptyState`。主程序若还要用 `AppErrorState`/`AppLoadingState`，
> 调用点得改成 `import 'widgets/state_views.dart';`（这是第 3 步的事，与 P1 主路径无关）。

**第 2 步：社区换引用（44 处，机械替换）**

1. `lib/island_app/widgets/state_views.dart` 改为**转发文件**：
 `export 'package:dna/widgets/state_views.dart';`
 这样社区 44 处 `import 'widgets/state_views.dart'` **一行都不用改**。
2. 删掉社区本地的三个类实现。
3. `flutter analyze` 必须零问题 —— 任何参数没对齐的地方会立刻暴露。

**第 3 步：主程序补用错误态/加载态（可选，单独一批）**

主程序 22 处裸用 `CircularProgressIndicator` 里，**只有整页级的加载**该换成 `AppLoadingState`；
按钮内的小转圈（`SizedBox(width:16, child: CircularProgressIndicator(strokeWidth:2))`）**不要动**，
它不是「页面状态」。

### 4.5风险与陷阱

|陷阱 |说明 |
|---|---|
| **`const` 构造丢失** |社区 11 处调用写的是 `const EmptyState(...)`。下沉后组件构造函数必须仍是 `const`，否则这 11 处编译失败 |
| **`import '../../theme/tokens.dart'` 层级** |共享件在 `lib/widgets/` 下，引用令牌是 `../theme/tokens.dart`（少一层）。社区转发文件不能带自己的 tokens import，会 unused |
| **`FitText` 依赖链** |`AppEmptyState` 用了 `FitText`（`lib/widgets/fit_text.dart`），它只依赖 `tokens.dart`，下沉无循环依赖。但**社区原本用 `Text`**，换成 `FitText` 后短文本会套 `FittedBox`——空态标题多为 4~10 字，正好命中 6 字阈值，**字号调大时行为会变**，需实测 |
| **`text_scaling_guard_test` 会扫到新文件** |它扫整个 `lib` 目录、禁止 `RichText(`/`TextPainter(`。`FitText` 是白名单内的唯一文件，共享件**不能**自己用 `TextPainter` |
| **图标尺寸改变是肉眼可见的** |空态图标 44→48、错误态 40→32，社区所有空态/错误态的观感都会变。**这是预期内的**，但需要逐页看一眼确认没有把布局撑破 |

### 4.6验收标准

```
#1. 社区不再有本地实现（只剩转发）
grep -r "class EmptyState" lib/island_app                     # 空
grep -r "class ErrorState" lib/island_app                     # 空
grep -r "class LoadingState" lib/island_app                   # 空

#2. 全项目只有一份实现
grep -rn "class AppEmptyState" lib                             # 只有 1 处（state_views.dart）
grep -rn "class AppErrorState" lib                             # 只有 1 处
grep -rn "class AppLoadingState" lib                           # 只有 1 处

#3. 44 处调用点一行未改，且编译通过
flutter analyze                                               # No issues
flutter test                                                  # 全绿
```

**外加一条静态测试**（建议随 P1 一起加，防止退回）：

```dart
// test/state_views_single_source_test.dart
// 断言：lib 下 class EmptyState / ErrorState / LoadingState 的出现次数为 0
// （只允许 AppEmptyState / AppErrorState / AppLoadingState）
```

## 5.数值映射表（P2，已完成）

> ⚠️ **本节曾写错并已修正**：`AppRadius` 的真实档位是 `xs=8 / sm=12 / md=16 / lg=20 / pill=999`。
> 旧稿误把 8 对到 `sm`、12 对到 `md`，**整体偏移一档**。改数值前必须先确认令牌实际值，不要凭印象。

### 圆角 → `AppRadius`

|社区裸值 |映射到 |实际值 |说明 |
|---|---|---:|---|
| `circular(8)` | `AppRadius.xs` |8 |精确匹配 |
| `circular(12)` | `AppRadius.sm` |12 |精确匹配 |
| `circular(16)` | `AppRadius.md` |16 |精确匹配 |
| `circular(20)` | `AppRadius.lg` |20 |精确匹配 |
| `circular(999)` | `AppRadius.pill` |999 |胶囊 |
| `circular(10)` | `AppRadius.sm` |12 |就近（10 更接近 12） |
| `circular(14)` | `AppRadius.md` |16 |就近 |
| `circular(18)` | `AppRadius.lg` |20 |就近 |
| `circular(24)` | `AppRadius.lg` |20 |主程序最大档 |
| `circular(9/7/6/1)` | `AppRadius.xs` |8 |最小档；**这些是手写值，主程序里没有** |

### 内边距 → `AppInsets` / `AppSpacing`

|社区裸值 |映射到 |实际值 |说明 |
|---|---|---:|---|
| `EdgeInsets.all(16)` | `AppInsets.card` |all 16 |主程序卡片内边距就是 16 |
| `EdgeInsets.all(12)` | `EdgeInsets.all(AppSpacing.md)` |12 | |
| `EdgeInsets.all(8)` | `EdgeInsets.all(AppSpacing.sm)` |8 | |
| `EdgeInsets.all(24)` | `EdgeInsets.all(AppSpacing.xl)` |24 | |
| `EdgeInsets.all(14)` | `EdgeInsets.all(AppSpacing.md)` |12 |就近 |
| `EdgeInsets.all(10)` | `EdgeInsets.all(AppSpacing.md)` |12 |就近 |
| `EdgeInsets.all(2)` | `EdgeInsets.all(AppSpacing.xxs)` |2 |精确匹配 |

### 动效 → `AppMotion`

|社区裸值 |映射到 |实际值 |说明 |
|---|---|---:|---|
| `200ms` | `AppMotion.fast` |200 |精确匹配 |
| `300ms` | `AppMotion.medium` |300 |精确匹配 |
| `450ms` | `AppMotion.transform` |450 |精确匹配 |
| `180ms` | `AppMotion.fast` |200 |就近 |
| `220ms` | `AppMotion.fast` |200 |就近 |
| `400ms` | `AppMotion.transform` |450 |就近 |
| `500ms` | `AppMotion.medium` |300 |就近 |
| `1400ms` / `1500ms` | **保留** |— |骨架屏/Shimmer 的循环节奏，**不是交互动效** |
| `400ms`（`api/client.dart` 重试间隔） | **保留** |— |网络退避，不是动效 |

### 不需要改的

|项 |原因 |
|---|---|
| `strokeWidth: 2` |已是事实统一值（25 处里绝大多数是 2） |
| `Colors.white/black` |82 处里绝大多数是图片上的浮层文字，必须用固定黑白保证对比度 |

## 6.相对间距 vs绝对间距（容易踩错）

P2会撞到一个语义问题：`EdgeInsets.all(16)`有两类用途，**映射目标不同**。

|用途 |例子 |映射到 |
|---|---|---|
| **卡片/容器的内边距** | `Card > Padding(padding: EdgeInsets.all(16))` | `AppInsets.card` |
| **元素之间的间距** | `SizedBox(height:16)`的同类 | `AppSpacing.lg` |

判别方法：**它包住的是一块内容，还是隔开两个东西**。包内容 → `AppInsets`；隔开东西 → `AppSpacing`。

## 7.不做什么（避免过度接轨）

|不做 |原因 |
|---|---|
| **不统一为「全居中」或「全左对齐」的新规范** |主程序已经是全左对齐，社区跟随即可；重新定义对齐规则没有收益 |
| **不动 `Colors.white/black`** |社区82处里绝大多数是**图片上的浮层文字**（封面标题、图上角标），这类必须用固定黑/白保证对比度，走主题色反而会看不清 |
| **不动社区独立运行时的 `ThemeData`** |社区有独立入口（`island_app/main.dart`），那里没有主程序的设置，本来就需要自己的主题 |
| **不追求「零裸值」** |主程序自己也有64处 `BorderRadius.circular(裸值)`、70处 `EdgeInsets.all(裸值)`。目标是**社区不超过主程序的密度**，不是绝对为零 |

## 8.验收方式（每批都要跑）

1. **静态**：`flutter analyze`零问题；`flutter test`全绿（尤其 `font_spec_test` / `font_scale_test` / `settings_design_test`）。
2. **统计**：重新生成本文第1节的表，对比改动前后 —— **数字必须朝正确方向动**（令牌采用数↑、裸写数↓）。
3. **目视**：社区在**同一窗口宽度**下截两张（手机390 /桌面1600），与主程序同尺寸对比：
 AppBar标题位置、卡片圆角、空态外观、按钮高度应一致。

## 9.一句话总结

接轨 = **换零件**，不是**重画设计**：
把社区的裸值换成主程序令牌、把两套空态合成一套、把17个居中标题改成左对齐，
再用静态测试把这条约束钉住。**颜色早就通了，不通的是零件**。
