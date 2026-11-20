import 'package:flutter/foundation.dart';

import 'message_attachment.dart';

/// 一条消息最多带几个附件（产品硬限制，收发两端都用它）。
const int kMaxAttachmentsPerMessage = 3;

/// 输入区「待发送附件」草稿。
///
/// 单独抽成 ChangeNotifier 而不是塞进输入栏的 State，是因为还有第二处要写它：
/// **回溯**。回溯会把被丢弃区间里那条用户消息重新填回输入框，附件也要一起
/// 回来，否则用户手上一份文件白传了。
class AttachmentDraft extends ChangeNotifier {
  AttachmentDraft();

  final List<MessageAttachment> _items = <MessageAttachment>[];

  List<MessageAttachment> get items =>
      List<MessageAttachment>.unmodifiable(_items);
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  /// 还能再加几个。
  int get remainingSlots =>
      (kMaxAttachmentsPerMessage - _items.length)
          .clamp(0, kMaxAttachmentsPerMessage);

  /// 加入一个附件。已存在同一份内容（同 ref）时返回 false 且不重复加。
  bool add(MessageAttachment attachment) {
    if (_items.length >= kMaxAttachmentsPerMessage) return false;
    if (_items.any((MessageAttachment a) => a.ref == attachment.ref)) {
      return false;
    }
    _items.add(attachment);
    notifyListeners();
    return true;
  }

  void removeAt(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    notifyListeners();
  }

  void removeRef(String ref) {
    final int before = _items.length;
    _items.removeWhere((MessageAttachment a) => a.ref == ref);
    if (_items.length != before) notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  /// 整体替换（回溯回填用；超出上限时只取前几个）。
  void replaceAll(Iterable<MessageAttachment> next) {
    _items
      ..clear()
      ..addAll(next.take(kMaxAttachmentsPerMessage));
    notifyListeners();
  }

  /// 发出去之后清空草稿，返回当时的内容（调用方据此把附件写进消息）。
  List<MessageAttachment> takeAll() {
    final List<MessageAttachment> out = List<MessageAttachment>.of(_items);
    _items.clear();
    notifyListeners();
    return out;
  }
}
