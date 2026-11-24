# 测试约定（dna-client）

这份文档记的是**实际踩过的坑**，不是通用建议。每一条都对应一次真实返工。

---

## 1. 断言按组件类型，不要按文案数量

`FitText extends Text`，但它 `build` 里又包了一层 `Text`。所以：

```dart
expect(find.text('已复制提示词'), findsOneWidget);  // ❌ 会数到 2（外层 FitText + 内层 Text）
```

凡是文案走了 `FitText`（`showSnack`、`AppEmptyState`、`AppErrorState`、`LoadingState` 全都走），
按文案计数就会翻倍。**改断言，不要改实现**：

```dart
expect(find.byType(AppErrorState), findsOneWidget);
expect(find.byType(OutlinedButton), findsOneWidget);
```

实在要断言文案时用 `findsWidgets`，并在就地写一行注释说明为什么不是 `findsOneWidget`。

历史记录：把 `showSnack` 推到社区端（PR #15）时，4 条测试因为这条挂了；
`state_views_single_source_test.dart` 的注释里也记了同一条。

---

## 2. 有常驻 spinner 时不要用 `pumpAndSettle`

`pumpAndSettle` 会一直 pump 到没有任何动画。列表底部的加载条是 `CircularProgressIndicator`，
它的旋转动画**永不结束**，于是：

```dart
await tester.pumpAndSettle();  // ❌ 超时：pumpAndSettle timed out
```

用固定时长把态切换的交叉淡入推完即可：

```dart
await tester.pump();
await tester.pump(const Duration(milliseconds: 400));
```

历史记录：`test/paged_list_body_test.dart` 的「hasMore → 底部出现加载条」就是这么挂的。

---

## 3. 共享骨架用 `AnimatedSwitcher` 做态切换：断言前要收敛动画

`LoadMoreListView` / `PagedGridBody` 的五态之间是 `AnimatedSwitcher` 交叉淡入，
过渡期间**新旧两棵子树同时在树上**。这会让「按文案计数」的断言多算一遍，
也会让 `find.byType(X)` 在过渡帧上找不到。

要么 `pumpAndSettle()`（前提：没有常驻 spinner），要么固定 `pump(Duration)` 推过过渡。

---

## 4. 单源守卫测试：用源码断言钉住「只有一处」

当某个实现被刻意收敛到一处、但**行为测试覆盖不到**时，用源码断言比硬造集成测试便宜得多。
本项目已有的先例：

| 测试 | 钉住的东西 |
|---|---|
| `state_views_single_source_test.dart` | 三态组件只在 `lib/widgets/state_views.dart` 定义；社区只能 typedef/export |
| `import_skeleton_single_source_test.dart` | 对话导入的「先备份再替换」「按 id 去重」各只有一处；两个入口都走同一个收尾 |
| `free_image_crop_test.dart` 的静态守护段 | 所有图片编辑器都读同一个裁剪开关；原生端不再写死比例 |
| `text_scaling_guard_test.dart` | 不允许出现裸 `RichText`；`TextPainter` 只许在 `fit_text.dart` |

写法要点：

- 用 `File('lib/...').readAsStringSync()` + 出现次数断言，**不要**用正则拼 `\s`/`\b`
  （字符串里转义极易被吃掉，正则静默失配，测试就成永远通过的空壳）；
- 断言的是「一处」而不是「长什么样」，这样实现重构不会误伤。

---

## 5. 移动文件后，记得同步静态守护测试里的硬编码路径

源码断言类的测试会写死路径。搬文件时 `dart analyze` 抓不到这类失效
（测试文件本身仍能编译），只有跑测试才会红。

历史记录：把 `card_crop_page.dart` 从 `lib/island_app/widgets/` 搬到 `lib/widgets/`（PR #22）
时，`free_image_crop_test.dart` 里有 5 处旧路径。

---

## 6. 页面级测试的前置：得先有注入点

现状：`ApiClient.instance` 是私有构造的单例，`fetch` 闭包在构造时绑死，
项目里也没有 HTTP 假实现。所以**社区端页面（`tickets_page`、`me_page`、`search_page` 等）
目前无法在测试里驱动到「有数据 / 空 / 底条」三种状态**，只能测错误态（未配置服务器地址时必失败）。

要补这类测试，先二选一：

1. 给 `ApiClient` 一个 `@visibleForTesting` 的传输层注入点；
2. 给页面一个 `@visibleForTesting` 的 `PagedController` 注入位。

在此之前，改动这些页面时请至少跑一遍共享骨架的测试（`paged_list_body_test.dart`），
并手工过一遍空/有数据/加载中三种状态。

---

## 7. 跑法

- 全量：`flutter test -j 2`（这台 16GB 机器默认并行度下 `attachment_gc_test` 会假超时，与代码无关）；
- 定向：改哪个模块就跑那几个文件，别每步都全量；
- 全量只在提交前跑一次。

**基线已知红**：`live_update_smoke_test` 的两条会真实请求 GitHub API，
在无网/限流环境下必然失败，与本仓库代码无关。
