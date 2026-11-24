import 'package:dna/models/world.dart';
import 'package:dna/services/hive_service.dart';

/// 世界卡这一域的**状态与写操作**（从 `AppController` 拆出来的第一块）。
///
/// 拆的依据是「谁能独立活下去」：世界卡只有
/// 「列表 / 查 by id / 增删改 / 归档 / 排序 / 落盘」六件事，除此之外只依赖
/// `HiveService`。原来它和设置、角色卡、会话、聊天运行期挤在同一个 1900 行
/// 的类里，任何一处改动都要在大文件里翻。
///
/// **通知不在这里发**：构造时传入 `onChanged`，由 `AppController` 接到
/// `AppChange.data` 分组上 —— 谁拆出去都不该自己决定通知谁。
class WorldStore {
  WorldStore({required HiveService hive, required void Function() onChanged})
    : _hive = hive,
      _onChanged = onChanged;

  final HiveService _hive;
  final void Function() _onChanged;

  List<World> _items = <World>[];

  /// 只读视图（外部拿到后不可改，改必须走本类的方法）。
  List<World> get items => List<World>.unmodifiable(_items);

  List<World> get activeItems =>
      _items.where((World w) => !w.archived).toList(growable: false);

  World? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final World world in _items) {
      if (world.id == id) return world;
    }
    return null;
  }

  /// 整体替换（启动加载 / 导入 / 清空数据用）。**不落盘**、不通知。
  void replaceAll(Iterable<World> worlds) {
    _items = List<World>.from(worlds);
  }

  Future<void> upsert(World world) async {
    final int index = _items.indexWhere((World item) => item.id == world.id);
    if (index == -1) {
      _items = <World>[..._items, world];
    } else {
      final List<World> updated = <World>[..._items];
      updated[index] = world;
      _items = updated;
    }
    await _hive.upsertWorld(world);
    _onChanged();
  }

  Future<void> delete(String id) async {
    _items = _items.where((World world) => world.id != id).toList();
    await _hive.deleteWorld(id);
    _onChanged();
  }

  Future<void> setArchived({
    required String id,
    required bool archived,
  }) async {
    final int index = _items.indexWhere((World item) => item.id == id);
    if (index == -1) return;
    final World current = _items[index];
    if (current.archived == archived) return;
    final List<World> updated = <World>[..._items];
    updated[index] = current.copyWith(archived: archived);
    _items = updated;
    await _hive.upsertWorld(updated[index]);
    _onChanged();
  }

  /// 排序：下标口径是「移除之后」（与 `reorderTas` 一致）。
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    if (newIndex < 0 || newIndex >= _items.length) return;
    final List<World> updated = List<World>.from(_items);
    final World moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    _items = updated;
    await _hive.saveWorlds(_items);
    _onChanged();
  }

  /// 把当前列表整体落盘（导入流程里改完列表后调用）。
  Future<void> persist() => _hive.saveWorlds(_items);
}
