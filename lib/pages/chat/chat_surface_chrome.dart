/// [ChatSurface] 的外壳形态。
enum ChatSurfaceChrome {
  /// 整页：自己建 `Scaffold` 与顶栏（完整的聊天页）。
  page,

  /// 嵌入：**不建 `Scaffold`、不建顶栏**，只渲染内容，交给宿主页面排版。
  ///
  /// 宿主要自己保证有可用的 `Scaffold`（snackbar / 底部弹层挂到最近的
  /// `Scaffold` 上）；键盘避让由宿主负责。
  embedded,
}
