import 'package:dna/models/world.dart';

/// 社区 → 主应用的窄接口：把一个从社区下载来的世界存进本地。
///
/// 社区对主应用是**零状态依赖**（只 import 两个 widget），这个边界值得守：
/// 为了一个「导入世界」的功能，不该把 AppController 整个传进社区。所以这里
/// 只注入一个方法，实现方（主应用）负责重新生成 id 并落盘。
///
/// 为什么必须重新生成 id：本地世界的 id 是客户端自己生成的，社区世界的 id 是
/// 后端分配的 UUID —— 两套 id 直接混用会撞。
abstract interface class WorldImportSink {
  /// 保存一个世界到本地，返回本地世界的新 id。失败抛异常。
  Future<String> importWorld(World world);
}

/// 社区 → 主应用的窄接口：取本地世界列表（发布用）。
///
/// 与 [WorldImportSink] 分开是有意的：一个写、一个读，各自只做一件事。
/// 同样**不传 AppController**。
abstract interface class WorldPublishSource {
  /// 本地世界的快照（只读）。发布页拿它渲染可选列表。
  List<World> localWorlds();
}
