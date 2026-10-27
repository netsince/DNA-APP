import '../models/conversation.dart';
import '../models/search_result.dart';
import '../models/ta.dart';
import '../models/world.dart';

/// 一次检索里进过精排的候选：结果 + 分数 + 原始顺序（用于稳定排序）。
class _Scored {
  const _Scored(this.result, this.score, this.order);

  final SearchResult result;
  final double score;
  final int order;
}

// ---- 打分参数 -------------------------------------------------------------
//
// 字段权重直接沿用社区服务器那套结论（dnaisland/app/services/search_service.py，
// 是在 417 张真实中文卡片上调出来的）：卡名 ≫ 标签 > 简介 / 人设。
// 搜「辞安」时，卡名叫《辞安》的必须排在「人设第三段提了一句辞安」的前面 ——
// 没有理由在本地重新发明一组权重。
const double _wName = 6;
const double _wTag = 3;
const double _wIntro = 2;
const double _wPersona = 1;
const double _wOpening = 1;

/// 头部命中窗口：字段开头这么多字之内命中，权重再乘 1.5。
///
/// 理由：名字/标题开头就命中的，通常正是用户要找的那一个；命中埋在 3000 字
/// 人设深处的，往往只是「提了一句」。
const int _headWindow = 12;

/// 整名精确命中的额外加分：压过一切片段命中。
const double _exactNameBonus = 10;

/// 单个会话最多返回多少条消息命中（沿用既有口径）。
const int _maxMessageHitsPerConversation = 5;

/// 全局检索：跨角色、世界、会话与消息正文匹配。
///
/// ## 四条纪律（改之前先读完）
///
/// 1. **零索引纯函数**：一次调用算完全部结果，不建倒排、不做增量缓存。
///    本地语料只有几十到几百个文档，`contains` 的召回能力本来就够；缓存带来
///    的失效逻辑比它省下的那点时间贵得多。
/// 2. **规则只在这里**：UI 层（搜索页）不许再过滤、再排序。同一条规则两处
///    实现，迟早漂。
/// 3. **归档内容不参与**：与全项目口径一致 —— 归档是「隐藏」，要显式切到
///    归档视图才看得到（控制器用 activeTas / activeWorlds /
///    activeConversations 过滤，且切换受 requireAuthForArchive 保护）。
///    搜索沿用同一口径，**不要**在这里自己加一套「含归档」的判断。
/// 4. **分组顺序不变、组内按相关度排**：返回顺序仍是 角色 → 世界 → 会话 →
///    消息，因为搜索页按类型分组渲染；这里只负责把同一组内部排好。
///
/// [query] 支持**空格分隔的多个关键词**（全部命中才算命中）。
/// [conversations] 应同时包含单聊与群聊。
List<SearchResult> searchGlobal({
  required String query,
  required List<TA> tas,
  required List<World> worlds,
  required List<Conversation> conversations,
}) {
  final List<String> terms = queryTerms(query);
  if (terms.isEmpty) {
    return const <SearchResult>[];
  }

  final Map<String, TA> taById = <String, TA>{for (final TA t in tas) t.id: t};
  final Map<String, World> worldById = <String, World>{
    for (final World w in worlds) w.id: w,
  };

  final List<_Scored> taHits = <_Scored>[];
  final List<_Scored> worldHits = <_Scored>[];
  final List<_Scored> conversationHits = <_Scored>[];
  final List<SearchResult> messageHits = <SearchResult>[];
  int order = 0;

  // ---- 角色：名称、标签、简介、人设、开场白 ----
  for (final TA ta in tas) {
    final String name = normalizeSearchText(ta.name);
    final String tagText = normalizeSearchText(ta.tags.join(' '));
    final String intro = normalizeSearchText(ta.intro);
    final String persona = normalizeSearchText(ta.persona);
    final String opening = normalizeSearchText(ta.opening);
    if (!matchesAllTerms(
      '$name\n$tagText\n$intro\n$persona\n$opening',
      terms,
    )) {
      continue;
    }
    double score = _fieldScore(name, terms, _wName) +
        _fieldScore(tagText, terms, _wTag) +
        _fieldScore(intro, terms, _wIntro) +
        _fieldScore(persona, terms, _wPersona) +
        _fieldScore(opening, terms, _wOpening);
    if (name == terms.join(' ')) {
      score += _exactNameBonus;
    }
    taHits.add(
      _Scored(
        SearchResult(
          kind: SearchResultKind.ta,
          id: ta.id,
          title: ta.name.isEmpty ? '未命名TA' : ta.name,
          subtitle: ta.intro.isEmpty ? '暂无介绍' : ta.intro,
          taId: ta.id,
        ),
        score,
        order++,
      ),
    );
  }

  // ---- 世界：名称、简介、描述、标签，以及词条名 / 词条描述（后两者分权重）----
  for (final World w in worlds) {
    final String name = normalizeSearchText(w.name);
    final String summary = normalizeSearchText(w.summary);
    final String description = normalizeSearchText(w.description);
    final String tagText = normalizeSearchText(w.tags.join(' '));
    final String entryNames = normalizeSearchText(
      w.entries.map((WorldEntry e) => e.name).join(' '),
    );
    final String entryBodies = normalizeSearchText(
      w.entries.map((WorldEntry e) => e.description).join(' '),
    );
    final String hay =
        '$name\n$summary\n$description\n$tagText\n$entryNames\n$entryBodies';
    if (!matchesAllTerms(hay, terms)) {
      continue;
    }
    // 词条名比词条正文重要：用户会按「王都」去找世界书，没人按正文搜。
    final double score = _fieldScore(name, terms, _wName) +
        _fieldScore(tagText, terms, _wTag) +
        _fieldScore(entryNames, terms, _wTag) +
        _fieldScore(summary, terms, _wIntro) +
        _fieldScore(entryBodies, terms, _wPersona) +
        _fieldScore(description, terms, _wPersona);
    worldHits.add(
      _Scored(
        SearchResult(
          kind: SearchResultKind.world,
          id: w.id,
          title: w.name.isEmpty ? '未命名世界' : w.name,
          subtitle: w.summary.isEmpty ? '暂无简介' : w.summary,
          worldId: w.id,
        ),
        score,
        order++,
      ),
    );
  }

  // ---- 会话（标题 / 备注）与消息正文 ----
  for (final Conversation c in conversations) {
    final TA? ta = c.taId.isNotEmpty ? taById[c.taId] : null;
    final World? world = worldById[c.worldId ?? ''];
    final String title = c.note.isNotEmpty
        ? c.note
        : (c.isGroup
            ? (c.groupName.isNotEmpty ? c.groupName : '未命名群聊')
            : (ta?.name.isNotEmpty == true ? ta!.name : '未命名会话'));
    final String taName = ta?.name.isNotEmpty == true ? ta!.name : '未命名TA';
    final String sub = world == null
        ? 'TA：$taName'
        : 'TA：$taName · 世界：${world.name}';

    final String titleText = normalizeSearchText(title);
    final String noteText = normalizeSearchText(c.note);
    if (matchesAllTerms('$titleText\n$noteText', terms)) {
      conversationHits.add(
        _Scored(
          SearchResult(
            kind: SearchResultKind.conversation,
            id: c.id,
            title: title,
            subtitle: sub,
            conversationId: c.id,
          ),
          _fieldScore(titleText, terms, _wName) +
              _fieldScore(noteText, terms, _wName),
          order++,
        ),
      );
    }

    // 消息正文：**从最新往回找**。
    // 这是曾经的 bug：正序 take(5) 会把长会话里最早的 5 条命中抛给用户，
    // 搜一个常用词永远看不到最近那次。
    final List<ConversationMessage> hits = <ConversationMessage>[];
    for (int i = c.messages.length - 1;
        i >= 0 && hits.length < _maxMessageHitsPerConversation;
        i--) {
      final ConversationMessage m = c.messages[i];
      if (matchesAllTerms(normalizeSearchText(m.text), terms)) {
        hits.add(m);
      }
    }
    for (final ConversationMessage m in hits) {
      messageHits.add(
        SearchResult(
          kind: SearchResultKind.message,
          id: '${c.id}#${m.id}',
          title: title,
          subtitle: sub,
          snippet: snippetAround(m.text, terms),
          conversationId: c.id,
        ),
      );
    }
  }

  return <SearchResult>[
    ..._ranked(taHits),
    ..._ranked(worldHits),
    ..._ranked(conversationHits),
    ...messageHits,
  ];
}

/// 组内按分数降序；同分保持原有先后（用 `order` 兜底，保证结果稳定）。
List<SearchResult> _ranked(List<_Scored> hits) {
  final List<_Scored> sorted = List<_Scored>.from(hits)
    ..sort((_Scored a, _Scored b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.order.compareTo(b.order);
    });
  return <SearchResult>[for (final _Scored s in sorted) s.result];
}

/// 一个字段的命中得分。
double _fieldScore(String field, List<String> terms, double weight) {
  if (field.isEmpty) return 0;
  double score = 0;
  for (final String term in terms) {
    final int at = field.indexOf(term);
    if (at < 0) continue;
    score += weight * (at <= _headWindow ? 1.5 : 1.0);
  }
  return score;
}

/// 检索归一：**全角 → 半角 + 小写**。
///
/// 服务器侧用的是 Unicode NFKC；Dart 核心库没有 NFKC，为一次搜索引一个
/// unicode 归一化包不划算，所以这里实现 NFKC 的**实用子集**：
/// 全角 ASCII（U+FF01–U+FF5E）与全角空格（U+3000）。中文在 NFKC 下不变，
/// 因此中日文的检索行为与服务器一致。
///
/// 归一化必须**查询侧与语料侧同时做**，只做一边等于没做。
String normalizeSearchText(String text) {
  if (text.isEmpty) return '';
  final StringBuffer out = StringBuffer();
  for (final int code in text.runes) {
    if (code >= 0xFF01 && code <= 0xFF5E) {
      out.writeCharCode(code - 0xFEE0); // 全角 ASCII → 半角
    } else if (code == 0x3000) {
      out.writeCharCode(0x20); // 全角空格 → 半角空格
    } else {
      out.writeCharCode(code);
    }
  }
  return out.toString().toLowerCase();
}

/// 查询词 → 关键词列表（按空白切分，全部命中才算命中）。
///
/// 以前整串 `contains` 有个硬伤：搜「辞安 古风」时把含空格的整串拿去匹配，
/// 必然 0 命中。
List<String> queryTerms(String query) => normalizeSearchText(query)
    .split(RegExp(r'\s+'))
    .where((String t) => t.isNotEmpty)
    .toList();

/// 是否**全部**关键词都出现（AND 语义）。
bool matchesAllTerms(String haystack, List<String> terms) =>
    terms.every(haystack.contains);

/// 生成命中片段：以最早命中的关键词为中心截取，前后各约 20 字，超出加省略号。
String snippetAround(String text, List<String> terms) {
  final String lower = text.toLowerCase();
  int best = -1;
  for (final String term in terms) {
    if (term.isEmpty) continue;
    final int at = lower.indexOf(term);
    if (at >= 0 && (best < 0 || at < best)) {
      best = at;
    }
  }
  if (best < 0) {
    // 全角折叠后才命中的情况：用归一化文本的位置近似截取（折叠是逐字符 1:1，
    // 位置在绝大多数情况下对得上）。
    final String normalized = normalizeSearchText(text);
    for (final String term in terms) {
      final int at = normalized.indexOf(term);
      if (at >= 0 && (best < 0 || at < best)) {
        best = at;
      }
    }
  }
  if (best < 0) return text;

  final int start = (best - 20).clamp(0, text.length);
  final int end = (best + 40).clamp(0, text.length);
  final String prefix = start > 0 ? '…' : '';
  final String suffix = end < text.length ? '…' : '';
  return '$prefix${text.substring(start, end)}$suffix';
}
