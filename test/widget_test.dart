import 'package:dna/main.dart';
import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 测试用假实现：完全不初始化/打开 Hive 盒子，避免无头测试环境下
/// dart:io 的 Directory.create 硬阻塞 isolate。initialize() 仍走完整流程，
/// 只是底层数据为空。
class FakeHiveService extends HiveService {
  @override
  Future<void> init() async {}
  @override
  Future<List<TA>> getTas() async => <TA>[];
  @override
  Future<List<UserIdentity>> getIdentities() async => <UserIdentity>[];
  @override
  Future<List<World>> getWorlds() async => <World>[];
  @override
  Future<List<Conversation>> getConversations() async => <Conversation>[];
}

void main() {
  testWidgets('shows OOBE when app starts without setup',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController controller = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: FakeHiveService(),
    );
    await controller.initialize();

    await tester.pumpWidget(DnaApp(controller: controller));
    await tester.pumpAndSettle();

    // 标题同时出现在 FitText 内部 Text 与 AppBar 文本中,
    // 用 findsWidgets 断言「至少渲染了一次」而非精确一次。
    expect(find.text('与汝共奏'), findsWidgets);
  });
}
