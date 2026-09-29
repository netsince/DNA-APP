import 'package:dna/models/conversation.dart';
import 'package:dna/pages/chat/chat_models.dart';
import 'package:dna/pages/chat/ui/widgets/chat_message_list.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 气泡文字**自动反色**的回归测试。
///
/// 背景(用户报的问题):气泡底色来自角色卡莫奈取色,可能被取成近白;
/// 而正文颜色原来写死 `colorScheme.onSurface` —— 深色模式下就是
/// 「白底白字」,气泡几乎看不清。对称地,浅色模式 + 深色取色会变成
/// 「黑底黑字」。这里锁定:文字颜色必须跟着气泡明暗走。
void main() {
  group('FitText.inkFor:按背景明暗给墨色', () {
    test('亮底给深墨、暗底给浅墨', () {
      expect(FitText.inkFor(Colors.white), AppColors.inkOnLight);
      expect(FitText.inkFor(const Color(0xFFF2F2F2)), AppColors.inkOnLight);
      expect(FitText.inkFor(Colors.black), AppColors.inkOnDark);
      expect(FitText.inkFor(const Color(0xFF202124)), AppColors.inkOnDark);
    });

    test('半透明底色先与页面底色合成再判断', () {
      // 20% 白叠在纯黑上 ≈ 深灰 ⇒ 应该用浅墨。
      final Color overBlack = FitText.inkFor(
        Colors.white.withValues(alpha: 0.2),
        Colors.black,
      );
      // 同样的 20% 白叠在纯白上仍是亮色 ⇒ 应该用深墨。
      final Color overWhite = FitText.inkFor(
        Colors.white.withValues(alpha: 0.2),
        Colors.white,
      );
      expect(overBlack, AppColors.inkOnDark);
      expect(overWhite, AppColors.inkOnLight);
    });

    test('两个方向的墨色对比度都足够(WCAG 正文 ≥ 4.5)', () {
      for (final Color ink in <Color>[
        AppColors.inkOnLight,
        AppColors.inkOnDark,
      ]) {
        final Color bg = ink == AppColors.inkOnLight
            ? Colors.white
            : Colors.black;
        expect(
          _contrastRatio(ink, bg),
          greaterThanOrEqualTo(4.5),
          reason: '墨色 $ink 落在 $bg 上对比度不足',
        );
      }
    });
  });

  group('聊天气泡:亮色气泡必须反成深色字', () {
    testWidgets('深色主题 + 近白气泡 ⇒ 正文用深墨(不再白底白字)', (WidgetTester tester) async {
      // 模拟莫奈取色取到近白:50% 透明度的白。
      final Color whiteBubble = Colors.white.withValues(alpha: 0.5);
      await _pumpList(
        tester,
        brightness: Brightness.dark,
        userBubble: whiteBubble,
      );

      final List<Color> colors = _bubbleTextColors(tester, whiteBubble);
      expect(colors, isNotEmpty, reason: '没有找到气泡正文的颜色');
      for (final Color c in colors) {
        expect(
          c.computeLuminance(),
          lessThan(0.35),
          reason: '近白气泡上的文字应为深墨,实际拿到 $c(会看不清)',
        );
      }
    });

    testWidgets('浅色主题 + 深色气泡 ⇒ 正文用浅墨(对称的另一半)', (WidgetTester tester) async {
      // 95% 黑:叠在浅色页面上仍是深色底(75% 时会变成中灰,
      // 那种情况下按对比度取优本来就应该给深墨)。
      final Color darkBubble = Colors.black.withValues(alpha: 0.95);
      await _pumpList(
        tester,
        brightness: Brightness.light,
        userBubble: darkBubble,
      );

      final List<Color> colors = _bubbleTextColors(tester, darkBubble);
      expect(colors, isNotEmpty);
      for (final Color c in colors) {
        expect(
          c.computeLuminance(),
          greaterThan(0.6),
          reason: '深色气泡上的文字应为浅墨,实际拿到 $c(会看不清)',
        );
      }
    });
  });
}

/// 组装一个只有一条用户消息的聊天列表。
Future<void> _pumpList(
  WidgetTester tester, {
  required Brightness brightness,
  required Color userBubble,
}) async {
  final Conversation conversation = Conversation(
    id: 'c1',
    taId: 'ta1',
    worldId: null,
    note: '',
    messages: <ConversationMessage>[
      const ConversationMessage(
        id: 'm1',
        role: 'user',
        text: '“你好呀”',
        timestamp: 0,
      ),
    ],
    backgroundMode: 'color',
    summaries: <ConversationSummary>[],
    archived: false,
    isGroup: false,
    groupName: '',
    groupPrompt: '',
    memberTaIds: <String>[],
    activeTaId: 'ta1',
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: ChatMessageList(
            conversation: conversation,
            scrollController: ScrollController(),
            messageKeys: <String, GlobalKey>{},
            userBubble: userBubble,
            assistantBubble: Colors.grey,
            showTokenCounts: false,
            searchQuery: '',
            thoughtsByMessageId: <String, ThoughtEntry>{},
            tokenCountForMessage: (String id, String text) => 0,
            summaryById: (String? id) => null,
            onStartSummary: (ConversationMessage m) async {},
            onDismissSummary: (String id) async {},
            onShowMessageMenu:
                ({
                  required Offset position,
                  required ConversationMessage message,
                  required int index,
                }) {},
            summaryInProgress: false,
            showSpeakerLabels: false,
            taNameForId: (String? id) => null,
            visibleThoughtMessageIds: <String>{},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 收集**气泡内**正文的颜色。
///
/// 注意范围:直接 find.byType(RichText) 会把 Text 内部生成的 RichText
/// 一并收进来(深色主题下那些是浅色主题文字),断言会被无关文字带偏。
/// 这里只取"底色等于气泡色"的容器内的文字。
List<Color> _bubbleTextColors(WidgetTester tester, Color bubbleColor) {
  final Finder bubble = find.byWidgetPredicate(
    (Widget w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).color == bubbleColor,
  );
  final List<Color> colors = <Color>[];
  for (final RichText rich in tester.widgetList<RichText>(
    find.descendant(of: bubble, matching: find.byType(RichText)),
  )) {
    _collect(rich.text, colors);
  }
  return colors;
}

void _collect(InlineSpan span, List<Color> out) {
  final Color? color = span.style?.color;
  if (color != null) {
    out.add(color);
  }
  // 注意:不能用 span.visitChildren —— TextSpan 的实现会先访问自身,
  // 在这里会造成无限递归。手动遍历 children。
  if (span is TextSpan && span.children != null) {
    for (final InlineSpan child in span.children!) {
      _collect(child, out);
    }
  }
}

/// WCAG 相对对比度。
double _contrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
