import 'package:dna/models/user_identity.dart';
import 'package:dna/services/hive_service.dart';

/// 身份这一域的**状态与写操作**（拆出 `AppController` 的第三块）。
///
/// 身份是「我在对话里的立场」：只有列表 / 查 by id / 增删改 / 落盘。
/// 会话里的 `identityId` 指向它，但删除身份**不动会话**（历史记录还在，
/// 与「删角色不动对话」一致）。
///
/// 通知不在这里发：构造时传 `onChanged`，由 `AppController` 接到
/// `AppChange.data` 分组。
class IdentityStore {
  IdentityStore({
    required HiveService hive,
    required void Function() onChanged,
  }) : _hive = hive,
       _onChanged = onChanged;

  final HiveService _hive;
  final void Function() _onChanged;

  List<UserIdentity> _items = <UserIdentity>[];

  List<UserIdentity> get items => List<UserIdentity>.unmodifiable(_items);

  UserIdentity? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final UserIdentity identity in _items) {
      if (identity.id == id) return identity;
    }
    return null;
  }

  void replaceAll(Iterable<UserIdentity> identities) {
    _items = List<UserIdentity>.from(identities);
  }

  Future<void> upsert(UserIdentity identity) async {
    final int index = _items.indexWhere((UserIdentity item) => item.id == identity.id);
    if (index == -1) {
      _items = <UserIdentity>[..._items, identity];
    } else {
      final List<UserIdentity> updated = <UserIdentity>[..._items];
      updated[index] = identity;
      _items = updated;
    }
    await _hive.upsertIdentity(identity);
    _onChanged();
  }

  Future<void> delete(String id) async {
    _items = _items.where((UserIdentity i) => i.id != id).toList();
    await _hive.deleteIdentity(id);
    _onChanged();
  }

  Future<void> persist() => _hive.saveIdentities(_items);
}
