import 'package:dna/models/ta.dart';

/// 社区 → 主应用的窄接口：把一张从社区复制来的角色卡存进本地。
///
/// 与 [WorldImportSink] 同一个套路：社区对主应用是零状态依赖，
/// 只注入一个方法，不传 AppController。
///
/// 为什么必须重新生成 id：本地角色卡的 id 由客户端生成，社区卡的 id 是
/// 后端 UUID —— 直接混用会互相覆盖。实现方负责换 id 落库。
abstract interface class TaImportSink {
  /// 保存一张角色卡到本地，返回本地新 id。失败抛异常。
  Future<String> importTa(TA ta);
}
