import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation.dart';
import '../models/ta.dart';

/// 「上次聊天」指针：让「打开应用直接续玩」知道该回到哪一场会话。
///
/// 四条纪律（改动前先读完）：
///
/// 1. **只存会话 id**，不存角色名 / 立绘 / 消息副本 —— 渲染与打开时都 join
///    现有数据，角色改名、换立绘、删会话都会自然反映，不会出现"继续上次
///    [已删除]"这种鬼话。
/// 2. **只有一个写入入口**：聊天页挂载/切换会话时调 [rememberOpened]
///    （见 `_ChatPageState._rememberCurrentConversation`）。不要新增"发消息
///    也写一份""退出也写一份"的旁路 —— 三处各写各的，状态迟早收敛不了。
/// 3. **不进备份**：备份走 `AppSettings.toJson()` 与各实体 toJson，本类用的是
///    独立的 SharedPreferences 键，换设备恢复后不会把旧 id 带过去（那个 id
///    在新设备上指向不存在的会话，最坏是别人的）。
/// 4. **不写进任何排序字段**：`tas` / `conversations` 的数组顺序是用户意图，
///    这里的指针是易变状态，两者混在一起就是"一个顶一个"。
class ResumeService {
  ResumeService._();

  /// 单例：写入方（聊天页）与读取方（启动闸门）必须共用同一份键。
  static final ResumeService instance = ResumeService._();

  /// 上次打开的会话 id。
  static const String _idKey = 'resume_last_conversation_id';

  /// 上次打开的时间戳（毫秒）。目前只记录不参与决策 —— 留给将来
  /// "太久没来了就别硬续"的判断，别在这里偷偷加逻辑。
  static const String _atKey = 'resume_last_opened_at';

  /// 正在进行的自动续玩。写入后必须被 [confirmAttempt] 清掉；
  /// 没被清掉就说明**上一次启动在自动续玩过程中整进程死掉了**。
  static const String _pendingKey = 'resume_pending_conversation_id';

  /// 连续失败次数：连续这么多次"自动续玩时进程死掉"就自动关掉开关，
  /// 避免用户每次开应用都被弹进一个打不开的会话。
  static const String _failCountKey = 'resume_startup_failures';

  /// 连续失败几次后自动关掉「自动继续上次聊天」。
  ///
  /// 取 2 而不是 1：用户"开应用→2 秒内又关掉"两次也会留下未确认的尝试，
  /// 一次就关会把功能误杀。真正的崩溃是每次启动都死，2 次足够识别。
  static const int maxStartupFailures = 2;

  /// 自动续玩后多久算"这次成功了"。见 [beginAttempt]。
  static const Duration confirmDelay = Duration(seconds: 2);

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// 记下"用户正在这场会话里"。**唯一写入入口**，幂等。
  Future<void> rememberOpened(String conversationId) async {
    if (conversationId.isEmpty) return;
    final SharedPreferences prefs = await _prefs;
    await prefs.setString(_idKey, conversationId);
    await prefs.setInt(_atKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// 上次打开的会话 id；没有则 null。
  Future<String?> lastConversationId() async {
    final SharedPreferences prefs = await _prefs;
    final String? id = prefs.getString(_idKey);
    return (id == null || id.isEmpty) ? null : id;
  }

  /// 清掉指针（会话被删、用户清空数据时）。
  Future<void> clearLast() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(_idKey);
    await prefs.remove(_atKey);
  }

  /// 自动续玩开始：先立一个"我马上就要推这一步"的旗子。
  Future<void> beginAttempt(String conversationId) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString(_pendingKey, conversationId);
  }

  /// 自动续玩成功（推送 [confirmDelay] 后进程还活着）：清旗子、把失败计数清零。
  Future<void> confirmAttempt() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(_pendingKey);
    await prefs.remove(_failCountKey);
  }

  /// 启动时检查上一次的旗子有没有被清掉。
  ///
  /// 还在 ⇒ 上次自动续玩中途整个进程没了（原生崩溃 / 被系统杀 / 用户秒关），
  /// 记一次失败并返回**当前累计失败次数**；已清 ⇒ 返回现有计数。
  Future<int> consumeStaleAttempt() async {
    final SharedPreferences prefs = await _prefs;
    final String? pending = prefs.getString(_pendingKey);
    if (pending == null || pending.isEmpty) {
      return prefs.getInt(_failCountKey) ?? 0;
    }
    await prefs.remove(_pendingKey);
    final int failures = (prefs.getInt(_failCountKey) ?? 0) + 1;
    await prefs.setInt(_failCountKey, failures);
    return failures;
  }

  /// 只读当前失败计数（测试与诊断用）。
  Future<int> failureCount() async {
    final SharedPreferences prefs = await _prefs;
    return prefs.getInt(_failCountKey) ?? 0;
  }

  /// 清空本类写入的全部键（"清空数据"流程用）。
  Future<void> clearAll() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(_idKey);
    await prefs.remove(_atKey);
    await prefs.remove(_pendingKey);
    await prefs.remove(_failCountKey);
  }
}

/// 解析出来的自动续玩目标。
class ResumeTarget {
  const ResumeTarget({required this.conversationId, required this.isGroup});

  final String conversationId;
  final bool isGroup;
}

/// 把「上次会话 id」解析成真正可以打开的目标；任何一条不满足就返回 null。
///
/// 这里刻意做成**纯函数**（不碰存储、不碰 UI）：
/// 所有"该不该开、开哪一个"的判断都能在单元测试里穷举，不用起一个应用。
///
/// 失效即静默放弃，不弹窗、不提示 —— 用户要的是"开应用就能玩"，
/// 不是"开应用先跟你解释一堆"。
ResumeTarget? resolveResumeTarget({
  required String? conversationId,
  required List<Conversation> conversations,
  required List<TA> tas,
}) {
  if (conversationId == null || conversationId.isEmpty) return null;

  Conversation? target;
  for (final Conversation conversation in conversations) {
    if (conversation.id == conversationId) {
      target = conversation;
      break;
    }
  }
  // 会话已被删：不打开（也不报错）。
  if (target == null) return null;

  final Set<String> aliveTaIds = <String>{for (final TA ta in tas) ta.id};

  if (target.isGroup) {
    // 群聊：只要还有一位成员在，就还能进（缺的角色由聊天页自己降级）。
    final List<String> members = target.memberTaIds.isEmpty
        ? <String>[target.taId]
        : target.memberTaIds;
    if (!members.any(aliveTaIds.contains)) return null;
  } else if (!aliveTaIds.contains(target.taId)) {
    // 角色已被删：会话通常是连带删掉的，这里再兜一层。
    return null;
  }

  return ResumeTarget(conversationId: target.id, isGroup: target.isGroup);
}

/// 启动闸门：只有下面**全部**满足才允许尝试自动续玩。
///
/// 顺序对应真实启动链：开屏动画 → 应用锁验证 → 主界面。
/// 任何一条不满足都**不消耗**尝试机会（`alreadyAttempted` 不会被置位），
/// 条件后来满足了（开屏结束、解锁通过）还会被再叫一次。
bool shouldAutoResume({
  required bool enabled,
  required bool splashDone,
  required bool oobeCompleted,
  required bool authRequired,
  required bool authPassed,
  required bool alreadyAttempted,
}) {
  if (!enabled) return false;
  if (!splashDone) return false;
  if (!oobeCompleted) return false;
  // 应用锁没通过就跳进聊天 = 等于锁是摆设。
  if (authRequired && !authPassed) return false;
  if (alreadyAttempted) return false;
  return true;
}
