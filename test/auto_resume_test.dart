import 'dart:io';

import 'package:dna/models/app_settings.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/services/resume_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TA _ta(String id) => TA(
      id: id,
      name: '角色 $id',
      gender: 'other',
      persona: '',
      intro: '',
      opening: '',
      tags: const <String>[],
      images: const <String, String>{},
      dialogueStyle: const [],
    );

Conversation _conversation(
  String id, {
  required String taId,
  bool isGroup = false,
  List<String>? members,
}) =>
    Conversation(
      id: id,
      taId: taId,
      worldId: null,
      note: '',
      messages: const [],
      backgroundMode: 'none',
      summaries: const [],
      archived: false,
      isGroup: isGroup,
      groupName: isGroup ? '群聊' : '',
      groupPrompt: '',
      memberTaIds: members ?? <String>[taId],
      activeTaId: taId,
    );

void main() {
  group('设置项 autoOpenLastChat', () {
    test('默认关闭（不打断"开应用去干别的"）', () {
      expect(AppSettings.empty().autoOpenLastChat, isFalse);
    });

    test('copyWith 可开启', () {
      expect(
        AppSettings.empty().copyWith(autoOpenLastChat: true).autoOpenLastChat,
        isTrue,
      );
    });

    test('toJson / fromJson 往返一致', () {
      final AppSettings settings =
          AppSettings.empty().copyWith(autoOpenLastChat: true);
      expect(AppSettings.fromJson(settings.toJson()).autoOpenLastChat, isTrue);
    });

    test('缺失字段回退默认 false（旧备份恢复不报错）', () {
      final Map<String, dynamic> json = AppSettings.empty().toJson();
      json.remove('autoOpenLastChat');
      expect(AppSettings.fromJson(json).autoOpenLastChat, isFalse);
    });
  });

  group('启动闸门 shouldAutoResume', () {
    bool gate({
      bool enabled = true,
      bool splashDone = true,
      bool oobeCompleted = true,
      bool authRequired = false,
      bool authPassed = false,
      bool alreadyAttempted = false,
    }) =>
        shouldAutoResume(
          enabled: enabled,
          splashDone: splashDone,
          oobeCompleted: oobeCompleted,
          authRequired: authRequired,
          authPassed: authPassed,
          alreadyAttempted: alreadyAttempted,
        );

    test('六项全满足才放行', () {
      expect(gate(), isTrue);
    });

    test('开关关着不放行', () {
      expect(gate(enabled: false), isFalse);
    });

    test('开屏动画没结束不放行', () {
      expect(gate(splashDone: false), isFalse);
    });

    test('没完成 OOBE 不放行', () {
      expect(gate(oobeCompleted: false), isFalse);
    });

    test('开了应用锁但没过验证不放行（否则锁形同虚设）', () {
      expect(gate(authRequired: true, authPassed: false), isFalse);
      expect(gate(authRequired: true, authPassed: true), isTrue);
    });

    test('本次启动已尝试过就不再尝试（返回/切后台不重入）', () {
      expect(gate(alreadyAttempted: true), isFalse);
    });
  });

  group('指针解析 resolveResumeTarget', () {
    test('会话与角色都在：返回目标', () {
      final ResumeTarget? target = resolveResumeTarget(
        conversationId: 'c1',
        conversations: <Conversation>[_conversation('c1', taId: 'ta-1')],
        tas: <TA>[_ta('ta-1')],
      );
      expect(target, isNotNull);
      expect(target!.conversationId, 'c1');
      expect(target.isGroup, isFalse);
    });

    test('没有指针：不打开', () {
      expect(
        resolveResumeTarget(
          conversationId: null,
          conversations: <Conversation>[_conversation('c1', taId: 'ta-1')],
          tas: <TA>[_ta('ta-1')],
        ),
        isNull,
      );
    });

    test('会话已删：不打开', () {
      expect(
        resolveResumeTarget(
          conversationId: 'c-missing',
          conversations: <Conversation>[_conversation('c1', taId: 'ta-1')],
          tas: <TA>[_ta('ta-1')],
        ),
        isNull,
      );
    });

    test('角色已删：不打开', () {
      expect(
        resolveResumeTarget(
          conversationId: 'c1',
          conversations: <Conversation>[_conversation('c1', taId: 'ta-gone')],
          tas: <TA>[_ta('ta-1')],
        ),
        isNull,
      );
    });

    test('群聊：还有成员在就能进', () {
      final ResumeTarget? target = resolveResumeTarget(
        conversationId: 'g1',
        conversations: <Conversation>[
          _conversation('g1', taId: 'ta-1', isGroup: true, members: <String>['ta-1', 'ta-2']),
        ],
        tas: <TA>[_ta('ta-2')],
      );
      expect(target, isNotNull);
      expect(target!.isGroup, isTrue);
    });

    test('群聊：成员全没了就不进', () {
      expect(
        resolveResumeTarget(
          conversationId: 'g1',
          conversations: <Conversation>[
            _conversation('g1', taId: 'ta-1', isGroup: true, members: <String>['ta-1', 'ta-2']),
          ],
          tas: <TA>[_ta('ta-9')],
        ),
        isNull,
      );
    });

    test('归档会话照常可续（归档只影响列表）', () {
      final Conversation archived =
          _conversation('c1', taId: 'ta-1');
      final ResumeTarget? target = resolveResumeTarget(
        conversationId: 'c1',
        conversations: <Conversation>[archived],
        tas: <TA>[_ta('ta-1')],
      );
      expect(target?.conversationId, 'c1');
    });
  });

  group('指针存储 ResumeService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('记录后能读回；clearLast 清空', () async {
      final ResumeService resume = ResumeService.instance;
      await resume.rememberOpened('c1');
      expect(await resume.lastConversationId(), 'c1');
      await resume.clearLast();
      expect(await resume.lastConversationId(), isNull);
    });

    test('空 id 不写入（防脏指针）', () async {
      final ResumeService resume = ResumeService.instance;
      await resume.rememberOpened('');
      expect(await resume.lastConversationId(), isNull);
    });

    test('先记一次失败，再成功一次就清零', () async {
      final ResumeService resume = ResumeService.instance;
      // 第一次：旗子没被确认 → 计一次失败。
      await resume.beginAttempt('c1');
      expect(await resume.consumeStaleAttempt(), 1);
      expect(await resume.failureCount(), 1);
      // 第二次：走完整成功路径 → 旗子清掉、失败清零。
      await resume.beginAttempt('c2');
      await resume.confirmAttempt();
      expect(await resume.failureCount(), 0);
      expect(await resume.consumeStaleAttempt(), 0);
    });

    test('未确认的尝试累计为失败，连续两次达到阈值', () async {
      final ResumeService resume = ResumeService.instance;
      await resume.beginAttempt('c1');
      expect(await resume.consumeStaleAttempt(), 1);
      await resume.beginAttempt('c1');
      expect(await resume.consumeStaleAttempt(), 2);
      expect(await resume.failureCount(), ResumeService.maxStartupFailures);
    });

    test('阈值是 2（一次误杀太多，三次太宽容）', () {
      expect(ResumeService.maxStartupFailures, 2);
    });

    test('clearAll 清掉全部键', () async {
      final ResumeService resume = ResumeService.instance;
      await resume.rememberOpened('c1');
      await resume.beginAttempt('c1');
      await resume.consumeStaleAttempt();
      await resume.clearAll();
      expect(await resume.lastConversationId(), isNull);
      expect(await resume.failureCount(), 0);
      expect(await resume.consumeStaleAttempt(), 0);
    });
  });

  group('结构约束', () {
    test('rememberOpened 只有一个调用点（聊天页）', () {
      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity
          in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final String path = entity.path.replaceAll('\\', '/');
        if (path.endsWith('services/resume_service.dart')) continue;
        if (entity.readAsStringSync().contains('rememberOpened(')) {
          offenders.add(path);
        }
      }
      expect(
        offenders,
        <String>['lib/pages/chat_page.dart'],
        reason: '「上次聊天」指针必须只有一个写入入口，新增旁路会让状态收敛不了',
      );
    });
  });
}
