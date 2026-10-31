/// 空状态占位组件 —— 已下沉到 `widgets/state_views.dart`。
///
/// 保留本文件与 `AppEmptyState` 这个名字，是为了不动主程序既有的调用点；
/// 实现只有一份（`state_views.dart`），这里只做转发。
///
/// 需要错误态 / 加载态时，直接 `import 'widgets/state_views.dart';`
/// 用 `AppErrorState` / `AppLoadingState`。
library;

export 'state_views.dart' show AppEmptyState;