import 'dart:io';

import 'package:dna/models/conversation.dart';
import 'package:dna/models/message_attachment.dart';
import 'package:dna/pages/chat/chat_models.dart';
import 'package:dna/pages/chat/ui/widgets/chat_message_list.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFonts() async {
  final FontLoader loader = FontLoader('SourceHanSans');
  for (final String path in <String>[
    'assets/fonts/SourceHanSansSC-Regular.otf',
    'assets/fonts/SourceHanSansSC-Medium.otf',
  ]) {
    final File file = File(path);
    if (file.existsSync()) {
      loader.addFont(Future<ByteData>.value(
        ByteData.view(file.readAsBytesSync().buffer),
      ));
    }
  }
  await loader.load();
  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final File iconFont = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (iconFont.existsSync()) {
      final FontLoader icons = FontLoader('MaterialIcons');
      icons.addFont(Future<ByteData>.value(
        ByteData.view(iconFont.readAsBytesSync().buffer),
      ));
      await icons.load();
    }
  }
}

MessageAttachment _att(String name, String ref, {int size = 4096, String kind = 'text'}) =>
    MessageAttachment(
      ref: ref,
      name: name,
      mime: 'text/plain',
      size: size,
      kind: kind,
    );

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('气泡上方的附件列表', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Conversation conversation = Conversation(
      id: 'c',
      taId: 'ta',
      worldId: '',
      note: '',
      messages: <ConversationMessage>[
        ConversationMessage(
          id: 'm1',
          role: 'user',
          text: '帮我看看这两份设定有没有冲突',
          timestamp: 1,
          attachments: <MessageAttachment>[
            _att('设定文档.md', 'a' * 64 + '.md'),
            _att('角色表.csv', 'b' * 64 + '.csv', size: 15360),
          ],
        ),
        ConversationMessage(
          id: 'm2',
          role: 'assistant',
          text: '第二份里的年龄和第一份对不上，我列一下。',
          timestamp: 2,
        ),
      ],
      backgroundMode: 'color',
      summaries: const <ConversationSummary>[],
      archived: false,
      isGroup: false,
      groupName: '',
      groupPrompt: '',
      memberTaIds: const <String>[],
      activeTaId: '',
    );
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'SourceHanSans',
        colorSchemeSeed: const Color(0xFF6750A4),
      ),
      home: Scaffold(
        body: ChatMessageList(
          conversation: conversation,
          scrollController: ScrollController(),
          messageKeys: <String, GlobalKey>{
            for (final ConversationMessage m in conversation.messages)
              m.id: GlobalKey(),
          },
          userBubble: const Color(0xFFE8DEF8),
          assistantBubble: const Color(0xFFF3EDF7),
          showTokenCounts: false,
          searchQuery: '',
          thoughtsByMessageId: const <String, ThoughtEntry>{},
          tokenCountForMessage: (String id, String text) => 0,
          summaryById: (String? id) => null,
          onStartSummary: (ConversationMessage m) async {},
          onDismissSummary: (String id) async {},
          onShowMessageMenu: (
              {required Offset position,
              required ConversationMessage message,
              required int index}) {},
          summaryInProgress: false,
          showSpeakerLabels: false,
          taNameForId: (String? id) => '林夏',
          visibleThoughtMessageIds: const <String>{},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/bubble_attachments.png'),
    );
  });
}
