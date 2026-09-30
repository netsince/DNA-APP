import 'package:dna/models/conversation.dart';
import 'package:dna/models/ta.dart';
import 'package:dna/models/user_identity.dart';
import 'package:dna/models/world.dart';
import 'package:dna/pages/delete_confirm_page.dart';
import 'package:dna/services/hive_service.dart';
import 'package:dna/services/openai_service.dart';
import 'package:dna/services/settings_service.dart';
import 'package:dna/services/ta_service.dart';
import 'package:dna/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「长按 5 秒确认删除」页的抖动回归测试。
///
/// 背景(用户反馈「长按删除时画面抽搐」):按住期间用
/// `jumpTo(进度 × maxScrollExtent)` 让页面自动滚动当进度条,而
/// maxScrollExtent 在长按期间会变(预览图异步加载改变内容高度、键盘
/// 收放改变视口高度)—— 每帧按"当前值"换算,滚动位置就会来回跳。
/// 现在按住那一刻锁定基准,这里锁定该行为。
class _FakeHive extends HiveService {
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
  Future<AppController> boot() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppController c = AppController(
      settingsService: SettingsService(),
      openAiService: OpenAiService(),
      taService: TaService(),
      hiveService: _FakeHive(),
    );
    await c.initialize();
    return c;
  }

  testWidgets('长按确认期间内容变高,滚动进度不跳(基准在按住时锁定)', (
    WidgetTester tester,
  ) async {
    final AppController c = await boot();
    Widget build(double contentHeight) => MaterialApp(
      home: DeleteConfirmPage(
        key: const ValueKey<String>('confirm'),
        controller: c,
        title: '删除对话',
        entityName: 'X',
        validNames: const <String>['X'],
        promptHint: '请输入 X',
        contentBuilder: (BuildContext ctx) => <Widget>[
          const SizedBox(height: 400),
          SizedBox(height: contentHeight),
        ],
        onDelete: () async => null,
        // 走"长按右下角按钮"这条路
        requireName: false,
      ),
    );

    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(build(2000));
    await tester.pump();

    // 按住确认按钮:开始 5 秒确认(页面自动滚动当进度)
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.delete_outline)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // 回顶 + 起飞
    await tester.pump(const Duration(milliseconds: 1000)); // 进度约 1/5

    // 直接读滚动位置(不能用内容里的 marker:滚出屏幕后会被 ListView 卸载)
    double offset() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    final double before = offset();
    expect(before, greaterThan(0), reason: '确认期间页面应已开始自动滚动');

    // 长按期间内容变高(模拟预览图异步加载完成 / 键盘收起)
    await tester.pumpWidget(build(6000));
    await tester.pump(const Duration(milliseconds: 16));
    final double after = offset();

    // 基准锁定时进度按"按住那一刻的高度"算 ⇒ 位置只随进度正常前进,
    // 不会因为内容变高而突然跳走(修之前会跳几百像素)。
    expect(
      (after - before).abs(),
      lessThan(40),
      reason: '内容变高不该让滚动进度跳变 —— 这正是用户看到的"画面抽搐"',
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
