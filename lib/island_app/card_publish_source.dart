import 'dart:typed_data';

import 'package:dna/models/ta.dart';

/// 社区 → 主应用的窄接口：取本地角色卡（发布用）。
///
/// 与 [WorldPublishSource] 同一个思路：社区对主应用是零状态依赖，只注入需要的
/// 那几个方法，不传 AppController。
abstract interface class CardPublishSource {
  /// 本地角色卡快照（只读，排除归档）。
  List<TA> localCards();

  /// 读某张卡的图片字节。
  ///
  /// 发布要的是 base64，社区拿不到本地文件，只能请主应用代读。
  Future<Uint8List?> imageBytes(String ref);
}
