/// 空态 / 错误态 / 加载态 —— 已下沉到共享层 `lib/widgets/state_views.dart`。
///
/// 社区的 17 个文件、40 处调用都在 `import 'widgets/state_views.dart'`，
/// 这里保留同名入口，**调用点一行都不用改**。
///
/// 短名用 `typedef` 而不是 `export ... show`：共享件里本来就没有 `EmptyState`
/// 这些名字，`typedef` 既能保留旧名又不会产生第二份实现。
///
/// 实现只有一份，主程序与社区共用；**不要再在本文件里新增组件**
/// （`test/state_views_single_source_test.dart` 会拦住）。
library;

import 'package:dna/widgets/state_views.dart';

export 'package:dna/widgets/state_views.dart';

/// 社区沿用的短名 → 共享实现。
typedef EmptyState = AppEmptyState;
typedef ErrorState = AppErrorState;
typedef LoadingState = AppLoadingState;