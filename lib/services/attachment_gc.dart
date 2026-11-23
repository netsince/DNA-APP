import 'package:flutter/foundation.dart';

import 'attachment_storage.dart';

/// 一次回收的结果。
class AttachmentGcResult {
  const AttachmentGcResult({
    required this.deleted,
    required this.bytesFreed,
    required this.partialsRemoved,
    required this.failures,
  });

  /// 删掉的孤儿附件个数。
  final int deleted;

  /// 腾出的字节数。
  final int bytesFreed;

  /// 顺手清掉的 `.part` 残片个数。
  final int partialsRemoved;

  /// 删失败的引用（留给用户看，不静默吞）。
  final List<String> failures;

  bool get hasAnything => deleted > 0 || partialsRemoved > 0;
}

/// 孤儿附件回收。
///
/// **什么叫孤儿**：附件是内容寻址的，被消息引用就活着；一旦引用它的消息
/// 全被删掉（删会话、回溯），文件没人再引用，就成了白占盘的孤儿。
///
/// 判据只有一个：**当前所有消息引用的 ref 集合**。不猜、不按时间清、
/// 不动「看起来很小」的东西 —— 只删确定没人引用的。
class AttachmentGc {
  AttachmentGc._();

  /// 纯函数版判据：给定「磁盘上有什么」与「谁被引用」，算出孤儿。
  ///
  /// 单独拆出来是为了能直接测 —— 判定规则是这块最容易出人命的地方
  /// （删错一个就是用户文件没了），不该只靠集成测试覆盖。
  static List<String> orphansOf({
    required List<String> allRefs,
    required Set<String> liveRefs,
  }) {
    return allRefs.where((String ref) => !liveRefs.contains(ref)).toList();
  }

  /// 找出当前的孤儿（只统计，不删）。
  static Future<List<String>> findOrphans({
    required Set<String> liveRefs,
  }) async {
    final List<String> refs = await AttachmentStore.instance.listRefs();
    return orphansOf(allRefs: refs, liveRefs: liveRefs);
  }

  /// 统计孤儿占用（不删）。读不到的引用按 0 计，不阻断。
  static Future<int> orphanBytes(List<String> orphans) async {
    int total = 0;
    for (final String ref in orphans) {
      final Uint8List? data = await AttachmentStore.instance.read(ref);
      total += data?.length ?? 0;
    }
    return total;
  }

  /// 回收：删掉所有不在 [liveRefs] 里的附件，并清掉临时残片。
  static Future<AttachmentGcResult> collect({
    required Set<String> liveRefs,
  }) async {
    final List<String> orphans = await findOrphans(liveRefs: liveRefs);
    int deleted = 0;
    int bytes = 0;
    final List<String> failures = <String>[];
    for (final String ref in orphans) {
      try {
        final Uint8List? data = await AttachmentStore.instance.read(ref);
        await AttachmentStore.instance.delete(ref);
        deleted++;
        bytes += data?.length ?? 0;
      } catch (e) {
        failures.add(ref);
        debugPrint('[attachment-gc] 删除失败 $ref: $e');
      }
    }
    final int partials = await AttachmentStore.instance.cleanPartials();
    return AttachmentGcResult(
      deleted: deleted,
      bytesFreed: bytes,
      partialsRemoved: partials,
      failures: failures,
    );
  }
}
