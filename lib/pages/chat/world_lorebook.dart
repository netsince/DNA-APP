import '../../models/world.dart';

/// Lorebook（世界信息动态激活）：
/// 把世界里的词条当作"知识条目"，根据当前对话文本中是否出现词条名来决定
/// 是否把该词条的描述注入提示词。这样世界背景从"一次性静态背景"变成
/// "按剧情动态召回的活知识库"。
class WorldLorebook {
  /// 从 [world] 中召回命中的词条。
  ///
  /// 匹配规则（来自 SillyTavern 世界书的高级特性）：
  /// - 每个词条可带 [WorldEntry.keys] 附加关键词，任意命中其一即触发；
  /// - [WorldEntry.keyRegex] 正则键，命中即触发；
  /// - [WorldEntry.caseSensitive] 大小写敏感、[WorldEntry.matchWholeWords] 全词匹配；
  /// - [WorldEntry.recursive] 递归扫描：命中词条的描述会作为新文本继续匹配；
  /// - [WorldEntry.cooldownRounds] 冷却、[WorldEntry.delayRounds] 延迟；
  /// - [WorldEntry.decorator] 装饰符：'activate' 强制激活、'dont_activate' 禁止激活。
  ///
  /// [state] 携带跨轮的 sticky / 冷却 / 延迟状态；[stickyRounds] 为激活后持续保留轮数。
  /// 返回按世界内顺序排列的命中列表（去重）。
  static List<WorldEntry> match(
    World? world,
    String text, {
    LorebookState? state,
    int stickyRounds = 3,
  }) {
    final LorebookState s = state ?? LorebookState();
    if (world == null || world.entries.isEmpty || text.trim().isEmpty) {
      return <WorldEntry>[];
    }

    final Map<String, WorldEntry> byId = <String, WorldEntry>{
      for (final WorldEntry e in world.entries)
        if (e.id.isNotEmpty) e.id: e,
    };

    // 1. 递归匹配：从 base 文本出发，逐级扫描。
    final Set<String> keyMatched = _recursiveKeyMatch(world, text);

    // 2. 结合延迟 / 冷却 / 装饰符，确定本轮真正激活的词条。
    final Set<String> activated = <String>{};
    for (final String id in keyMatched) {
      final WorldEntry? e = byId[id];
      if (e == null) {
        continue;
      }
      if (e.decorator == 'dont_activate') {
        continue; // 装饰符：禁止激活
      }
      final bool inCooldown = (s.cooldown[id] ?? 0) > 0;
      if (inCooldown && e.decorator != 'activate') {
        continue; // 冷却期内不重复触发（除非强制激活）
      }
      // 延迟：首次命中且配置了延迟，则进入等待，本轮不激活。
      if (e.delayRounds > 0 && (s.delay[id] ?? 0) == 0) {
        s.delay[id] = e.delayRounds;
        continue;
      }
      activated.add(id);
    }
    // 延迟倒计时归零的词条，本轮起激活。
    final Set<String> newlyDelayed = <String>{};
    s.delay.forEach((String id, int remaining) {
      if (remaining <= 1 && byId.containsKey(id) && keyMatched.contains(id)) {
        newlyDelayed.add(id);
      }
    });
    activated.addAll(newlyDelayed);

    // 3. sticky：本轮激活的词条进入 sticky，在若干轮内持续保留。
    if (stickyRounds > 0) {
      for (final String id in activated) {
        s.sticky[id] = stickyRounds;
      }
    } else {
      s.sticky.clear();
    }

    // 4. 组装结果 = 本轮激活 + 仍在 sticky 期内的其它词条（去重）。
    final List<WorldEntry> combined = <WorldEntry>[];
    final Set<String> seen = <String>{};
    for (final String id in activated) {
      final WorldEntry? e = byId[id];
      if (e != null) {
        combined.add(e);
        seen.add(id);
      }
    }
    for (final String id in s.sticky.keys.toList()) {
      final int rounds = s.sticky[id] ?? 0;
      if (rounds > 0 && !seen.contains(id) && byId.containsKey(id)) {
        combined.add(byId[id]!);
        seen.add(id);
      }
    }

    // 5. 冷却登记（本论激活的词条进入冷却）。
    for (final String id in activated) {
      final WorldEntry? e = byId[id];
      if (e != null && e.cooldownRounds > 0) {
        s.cooldown[id] = e.cooldownRounds;
      }
    }

    // 6. 轮末衰减：sticky / 冷却 / 延迟 全部 -1，归零移除。
    _tickDown(s.sticky);
    _tickDown(s.cooldown);
    _tickDown(s.delay);

    return combined;
  }

  /// 递归扫描关键词命中的词条 id 集合。
  /// 命中且 [WorldEntry.recursive] 为真的词条，其描述会作为新文本继续匹配，
  /// 最多递归 [maxRecursionSteps] 层，避免无限循环。
  static Set<String> _recursiveKeyMatch(World world, String baseText,
      {int maxRecursionSteps = 3}) {
    final Set<String> matched = <String>{};
    String scan = baseText;
    for (int step = 0; step < maxRecursionSteps; step++) {
      bool foundNew = false;
      final StringBuffer extra = StringBuffer();
      for (final WorldEntry e in world.entries) {
        if (e.id.isEmpty || matched.contains(e.id)) {
          continue;
        }
        if (e.decorator == 'dont_activate') {
          continue;
        }
        if (_entryMatches(e, scan)) {
          matched.add(e.id);
          foundNew = true;
          if (e.recursive && e.description.trim().isNotEmpty) {
            extra.write(e.description.trim());
            extra.write(' ');
          }
        }
      }
      if (!foundNew || extra.isEmpty) {
        break;
      }
      scan = '$scan ${extra.toString().trim()}';
    }
    return matched;
  }

  /// 判断单个词条是否命中当前扫描文本。
  static bool _entryMatches(WorldEntry e, String text) {
    // 正则键优先。
    final String? regex = e.keyRegex;
    if (regex != null && regex.trim().isNotEmpty) {
      try {
        if (RegExp(regex).hasMatch(text)) {
          return true;
        }
      } catch (_) {
        // 正则非法则忽略，仅按字面量匹配。
      }
    }
    // 字面量键：name + keys。
    final List<String> keys = <String>[
      if (e.name.trim().isNotEmpty) e.name.trim(),
      ...e.keys,
    ];
    final String searchText = e.caseSensitive ? text : text.toLowerCase();
    for (final String key in keys) {
      if (key.isEmpty) {
        continue;
      }
      final String candidate = e.caseSensitive ? key : key.toLowerCase();
      if (e.matchWholeWords) {
        if (RegExp(RegExp.escape(candidate), caseSensitive: e.caseSensitive)
            .hasMatch(searchText)) {
          return true;
        }
      } else {
        if (searchText.contains(candidate)) {
          return true;
        }
      }
    }
    return false;
  }

  static void _tickDown(Map<String, int> map) {
    final Map<String, int> next = <String, int>{};
    map.forEach((String id, int value) {
      final int v = value - 1;
      if (v > 0) {
        next[id] = v;
      }
    });
    map
      ..clear()
      ..addAll(next);
  }

  /// 把命中的词条格式化为注入提示词的文本。无有效描述时返回空串。
  /// 额外透出人物的性别/年龄/状态（如已故）以及与其它词条的关系。
  static String format({required World? world, required List<WorldEntry> entries}) {
    final List<WorldEntry> withContent = entries
        .where((WorldEntry e) => e.description.trim().isNotEmpty)
        .toList();
    if (withContent.isEmpty) {
      return '';
    }
    // 词条 id -> 名字，用于把关系里的 targetId 解析成可读名字。
    final Map<String, String> nameById = <String, String>{
      for (final WorldEntry e in (world?.entries ?? <WorldEntry>[]))
        if (e.name.trim().isNotEmpty) e.id: e.name.trim(),
    };
    final StringBuffer sb = StringBuffer('当前激活的世界知识（与当前对话场景相关，供参考，请勿复述）：');
    for (final WorldEntry e in withContent) {
      // 人物属性透出（性别 / 年龄 / 状态）。
      final List<String> attrs = <String>[];
      if (e.type == WorldEntryType.person) {
        switch (e.gender) {
          case WorldPersonGender.male:
            attrs.add('男');
          case WorldPersonGender.female:
            attrs.add('女');
          case WorldPersonGender.other:
            attrs.add('其他');
          case null:
            break;
        }
        final String ageText = e.age ?? '';
        if (ageText.trim().isNotEmpty) {
          attrs.add('${ageText.trim()}岁');
        }
        if (e.status == WorldPersonStatus.dead) {
          attrs.add('已故');
        }
      }
      final String attrStr = attrs.isEmpty ? '' : '（${attrs.join('，')}）';
      // 关系透出：解析 targetId 为词条名。
      String relationText = '';
      final WorldEntryRelation? relation = e.relation;
      if (relation != null && relation.content.trim().isNotEmpty) {
        final String targetName = relation.targetId.isNotEmpty
            ? (nameById[relation.targetId] ?? '')
            : '';
        relationText = targetName.isNotEmpty
            ? '。与$targetName的关系：${relation.content.trim()}'
            : '。关系：${relation.content.trim()}';
      }
      sb.write('\n- ${e.name}$attrStr：${e.description.trim()}$relationText');
    }
    return sb.toString();
  }
}

/// Lorebook 跨轮状态：记录词条 id 对应的剩余轮数。
/// - [sticky]：激活后持续保留的轮数；
/// - [cooldown]：激活后进入冷却的剩余轮数（冷却期内同名键不再触发）；
/// - [delay]：关键词出现后等待延迟激活的剩余轮数。
class LorebookState {
  final Map<String, int> sticky = <String, int>{};
  final Map<String, int> cooldown = <String, int>{};
  final Map<String, int> delay = <String, int>{};
}
