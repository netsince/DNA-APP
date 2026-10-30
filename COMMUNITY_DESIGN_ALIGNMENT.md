# 社区（DNAISLAND）与主程序的设计接轨方案

>本文回答一个问题：**社区那一半界面，怎么长得像主程序？**
>
>结论先行：社区和主程序**已经共享颜色主题**（内嵌时直接用主程序的 `Theme`），
>但**不共享设计语言** ——对齐、字重、组件、动效、版心各写各的。
>因此接轨不是「重做视觉」，而是**把社区换成主程序的那套零件**。

## 1.现状：接轨到什么程度

下面是**脚本现场统计**的结果（`lib` =主程序213个 dart文件，`lib/island_app` =社区86个）。
数字随代码变化，重新生成即可，**不要手抄**。

### 令牌采用情况（越多越好）

|令牌 |主程序 |社区 |判定 |
|---|---:|---:|---|
| `AppSpacing` | 270 | 129 | ⚠️部分采用 |
| `AppRadius` | 52 | 16 | ⚠️部分采用 |
| `AppInsets` | 44 | 0 | ❌未采用 |
| `AppElevation` | 8 | 0 | ❌未采用 |
| `AppBorder` | 8 | 0 | ❌未采用 |
| `AppTextStyles` | 48 | 0 | ❌未采用 |
| `AppMotion` | 21 | 0 | ❌未采用 |
| `AppSize` | 73 | 4 | ⚠️部分采用 |
| `AppFontSize` | 45 | 56 | ✅已接轨 |
| `AppWeight` | 90 | 8 | ⚠️部分采用 |
| `AppLineHeight` | 10 | 14 | ✅已接轨 |
| `AppEmptyState` | 11 | 0 | ❌未采用 |

### 裸写情况（越少越好）

|写法 |主程序 |社区 |判定 |
|---|---:|---:|---|
| BorderRadius.circular(数字) | 64 | 93 | ❌社区明显更多 |
| EdgeInsets.all(数字) | 70 | 69 | ⚠️与主程序同量级 |
| FontWeight.w800/w700/bold | 0 | 2 | ❌社区明显更多 |
| centerTitle:true | 0 | 17 | ❌社区明显更多 |
| Duration(milliseconds:数字) | 56 | 15 | ⚠️与主程序同量级 |
| strokeWidth:数字 | 18 | 25 | ❌社区明显更多 |

### 一眼可见的四个「两个世界」

1. **AppBar标题对齐**：主程序57个 AppBar **全部左对齐**（主题里显式 `centerTitle: false`）；
社区37个里有 **17个居中**。这是用户一眼就能感到「不是同一个 App」的首要来源。
2. **字重**：主程序全项目 `w600/w700/bold`为 **0**（`font_spec_test`守着——内置字体只有400/500
两个真实字重，更强的字重会被 Flutter **人为描边**伪造，中文小字会糊）；社区有 **2处 `w800`**。
3. **空状态**：主程序用 `AppEmptyState`，社区自建 `EmptyState`，图标尺寸、间距、字号层级都不同 ——
同样是「暂无数据」，两边长得不一样。
4. **版心**：主程序由栏目壳统一收窄（消息760 /我家1040 /设置900），
社区这一栏是 `contentMaxWidth: double.infinity`，**铺满整窗**。

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

|批次 |内容 |涉及处数 |预计 |风险 |
|---|---|---:|---|---|
| **P0硬规则** |①2处 `w800` → `AppWeight.medium`；②17处 `centerTitle: true`删除；③把 `font_spec_test`扫描范围扩到社区 +新增对齐测试 |19处 +2条测试 |约1小时 |极低（纯机械） |
| **P1组件** |三态组件下沉共享层；社区17处 `EmptyState` /9处 `LoadingState` /18处 `ErrorState`改为引用共享件 |44处 |约半天 |低（视觉微调） |
| **P2数值收敛** |社区 `BorderRadius.circular(裸值)`93处、`EdgeInsets.all(裸值)`69处 → `AppRadius` / `AppSpacing`；`strokeWidth`25处统一为2 |187处 |约1天 |中（圆角/间距会有肉眼可见变化，需逐页看） |
| **P3动效与描边** | `Duration(milliseconds:裸值)`15处 → `AppMotion`；引入 `AppBorder` / `AppElevation` |约20处 |约半天 |低 |

### P0的验收标准（可直接当验收单）

```
grep -r "FontWeight.w[678]00\|FontWeight.bold" lib/island_app #必须为空
grep -r "centerTitle: true" lib/island_app #必须为空
flutter test test/font_spec_test.dart #必须绿
```

## 4.数值映射表（P2用）

社区现有的裸值 →主程序令牌。**先按这张表机械替换，再逐页目视一遍**。

|社区裸值 |映射到 |备注 |
|---|---|---|
| `BorderRadius.circular(8)` | `AppRadius.smAll` |两边都是8，纯换写法 |
| `BorderRadius.circular(12)` | `AppRadius.mdAll` |同上 |
| `BorderRadius.circular(16)` | `AppRadius.lgAll` |同上 |
| `BorderRadius.circular(999)` | `AppRadius.pillAll` |胶囊 |
| `BorderRadius.circular(1/6/7/9/14)` |就近归到 sm/md/lg | **这些是手写值，主程序里没有** |
| `EdgeInsets.all(16)` | `AppInsets.card`或 `AppSpacing.lg` |看用途，见第5节 |
| `EdgeInsets.all(12)` | `AppSpacing.md` | |
| `EdgeInsets.all(8)` | `AppSpacing.sm` | |
| `EdgeInsets.all(24)` | `AppSpacing.xl` | |
| `EdgeInsets.all(14)` |就近归到12或16 |手写值 |
| `Duration(milliseconds:200)` | `AppMotion.fast` | |
| `Duration(milliseconds:300)` | `AppMotion.medium` | |
| `Duration(milliseconds:450)` | `AppMotion.transform` | |
| `Duration(milliseconds:180/220/400)` |就近归到 fast/medium |手写值 |
| `Duration(milliseconds:1400/1500)` | **保留** |加载动画节奏，不是交互动效 |
| `strokeWidth:2` | **保留** |已是统一值 |
| `strokeWidth:3` |改2 |圆环粗细不齐 |

> ⚠️ **1400/1500ms那两个不要动**：那是骨架/加载动画的循环节奏，塞进 `AppMotion`会破坏语义。

## 5.相对间距 vs绝对间距（容易踩错）

P2会撞到一个语义问题：`EdgeInsets.all(16)`有两类用途，**映射目标不同**。

|用途 |例子 |映射到 |
|---|---|---|
| **卡片/容器的内边距** | `Card > Padding(padding: EdgeInsets.all(16))` | `AppInsets.card` |
| **元素之间的间距** | `SizedBox(height:16)`的同类 | `AppSpacing.lg` |

判别方法：**它包住的是一块内容，还是隔开两个东西**。包内容 → `AppInsets`；隔开东西 → `AppSpacing`。

## 6.不做什么（避免过度接轨）

|不做 |原因 |
|---|---|
| **不统一为「全居中」或「全左对齐」的新规范** |主程序已经是全左对齐，社区跟随即可；重新定义对齐规则没有收益 |
| **不动 `Colors.white/black`** |社区82处里绝大多数是**图片上的浮层文字**（封面标题、图上角标），这类必须用固定黑/白保证对比度，走主题色反而会看不清 |
| **不动社区独立运行时的 `ThemeData`** |社区有独立入口（`island_app/main.dart`），那里没有主程序的设置，本来就需要自己的主题 |
| **不追求「零裸值」** |主程序自己也有64处 `BorderRadius.circular(裸值)`、70处 `EdgeInsets.all(裸值)`。目标是**社区不超过主程序的密度**，不是绝对为零 |

## 7.验收方式（每批都要跑）

1. **静态**：`flutter analyze`零问题；`flutter test`全绿（尤其 `font_spec_test` / `font_scale_test` / `settings_design_test`）。
2. **统计**：重新生成本文第1节的表，对比改动前后 —— **数字必须朝正确方向动**（令牌采用数↑、裸写数↓）。
3. **目视**：社区在**同一窗口宽度**下截两张（手机390 /桌面1600），与主程序同尺寸对比：
 AppBar标题位置、卡片圆角、空态外观、按钮高度应一致。

## 8.一句话总结

接轨 = **换零件**，不是**重画设计**：
把社区的裸值换成主程序令牌、把两套空态合成一套、把17个居中标题改成左对齐，
再用静态测试把这条约束钉住。**颜色早就通了，不通的是零件**。
