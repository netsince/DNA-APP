import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/root_shell.dart';
import 'package:dna/island_app/widgets/plus_hub.dart';

/// 底栏中间的「＋」动作枢纽。
///
/// 设计：**整屏一起高斯模糊**（连底栏一起），底部原来 ＋ 的位置换成一个关闭按钮。
/// 网页版是靠 z-index 让底栏压在浮层之上（于是 ＋ 一直能点），副作用是底栏那一带
/// 不经过蒙层、点它会切栏目却收不掉浮层。这里改成出口只有一个，行为没有例外。
void main() {
  group('＋ 枢纽浮层', () {
    Future<void> pumpOverlay(
      WidgetTester tester, {
      required ValueNotifier<bool> open,
      ValueChanged<PlusHubChoice>? onSelect,
      VoidCallback? onClose,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                const Center(child: Text('内容')),
                ValueListenableBuilder<bool>(
                  valueListenable: open,
                  builder: (BuildContext context, bool value, _) =>
                      PlusHubOverlay(
                    open: value,
                    bottomBarHeight: 56,
                    onClose: onClose ?? () {},
                    onSelect: onSelect ?? (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder closeButton() => find.descendant(
          of: find.byType(PlusHubOverlay),
          matching: find.byIcon(Icons.close),
        );

    testWidgets('收起时什么都不画', (WidgetTester tester) async {
      final ValueNotifier<bool> open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      await pumpOverlay(tester, open: open);

      expect(find.text('发布角色卡'), findsNothing);
      expect(find.byType(PlusHubButton), findsNothing);
    });

    testWidgets('展开后两个入口都在，且各带一句说明', (WidgetTester tester) async {
      final ValueNotifier<bool> open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      await pumpOverlay(tester, open: open);

      open.value = true;
      await tester.pumpAndSettle();

      expect(find.text('发布角色卡'), findsOneWidget);
      expect(find.text('AI生图'), findsOneWidget);
      expect(find.text('创建与共享全新 AI 属性卡'), findsOneWidget);
      expect(find.text('灵感画廊与在线绘图生成'), findsOneWidget);
    });

    testWidgets('选「发布角色卡」回调 publishCard', (WidgetTester tester) async {
      final ValueNotifier<bool> open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      PlusHubChoice? picked;
      await pumpOverlay(
        tester,
        open: open,
        onSelect: (PlusHubChoice c) => picked = c,
      );
      open.value = true;
      await tester.pumpAndSettle();

      await tester.tap(find.text('发布角色卡'));
      await tester.pumpAndSettle();
      expect(picked, PlusHubChoice.publishCard);
    });

    testWidgets('选「AI生图」回调 imageGen', (WidgetTester tester) async {
      final ValueNotifier<bool> open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      PlusHubChoice? picked;
      await pumpOverlay(
        tester,
        open: open,
        onSelect: (PlusHubChoice c) => picked = c,
      );
      open.value = true;
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI生图'));
      await tester.pumpAndSettle();
      expect(picked, PlusHubChoice.imageGen);
    });

    testWidgets('点蒙层空白处触发关闭', (WidgetTester tester) async {
      final ValueNotifier<bool> open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      int closes = 0;
      await pumpOverlay(tester, open: open, onClose: () => closes++);
      open.value = true;
      await tester.pumpAndSettle();

      // 左上角一定在弹层之外。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(closes, 1);
    });

    testWidgets('底部的关闭按钮也能关', (WidgetTester tester) async {
      final ValueNotifier<bool> open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      int closes = 0;
      await pumpOverlay(tester, open: open, onClose: () => closes++);
      open.value = true;
      await tester.pumpAndSettle();

      expect(closeButton(), findsOneWidget);
      await tester.tap(closeButton());
      await tester.pumpAndSettle();
      expect(closes, 1);
    });
  });

  group('社区底栏', () {
    /// 推进若干帧。
    ///
    /// **不能用 pumpAndSettle**：各栏目一挂载就开始加载，转圈是无限动画，
    /// pumpAndSettle 会一直等下去（报错完全不指向动画）。所以手动推帧。
    Future<void> settleManually(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> pumpShell(
      WidgetTester tester, {
      VoidCallback? onExit,
      bool showExit = true,
    }) async {
      // 底栏只在竖屏出现（横屏走常驻侧栏），而测试默认窗口 800x600 是横屏。
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // 传 onExitToMainApp：生产环境社区总是嵌进主应用，顶栏左上角会出现
      // 「返回主应用」。底栏是 推荐 / 茶馆 / ＋ / 世界 / 我 五格。
      await tester.pumpWidget(
        MaterialApp(
          home: RootShell(
            // showExit=false 模拟「设置里关掉了返回主应用」：
            // 接线方式就是传 null，顶栏按钮与侧边栏底部条目都跟着消失。
            onExitToMainApp: showExit ? (onExit ?? () {}) : null,
          ),
        ),
      );
      await settleManually(tester);
    }

    Future<void> openHub(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.add));
      await settleManually(tester);
      expect(find.text('发布角色卡'), findsOneWidget);
    }

    /// 按系统返回键。
    Future<void> pressBack(WidgetTester tester) async {
      final ByteData message = const JSONMethodCodec().encodeMethodCall(
        const MethodCall('popRoute'),
      );
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        message,
        (ByteData? _) {},
      );
      await tester.pump();
    }

    /// 底栏里的某一项（把侧边栏里的同名图标排除掉）。
    Finder bottomItem(IconData icon) => find.descendant(
          of: find.byKey(kCommunityBottomBarKey),
          matching: find.byIcon(icon),
        );

    Finder closeButton() => find.descendant(
          of: find.byType(PlusHubOverlay),
          matching: find.byIcon(Icons.close),
        );

    testWidgets('展开后整屏糊（含顶栏与底栏），关闭按钮落在底栏那一带的正中',
        (WidgetTester tester) async {
      await pumpShell(tester);
      await openHub(tester);

      // 取**蒙层**（BackdropFilter）的矩形：PlusHubOverlay 自己用 StackFit.expand
      // 铺满整屏，蒙层才是那个真正画出来的层。
      final Rect scrim = tester.getRect(
        find.descendant(
          of: find.byType(PlusHubOverlay),
          matching: find.byType(BackdropFilter),
        ),
      );
      // 整屏一起糊：顶栏与底栏都被盖住。
      expect(scrim.overlaps(tester.getRect(find.byType(AppBar))), isTrue,
          reason: 'AppBar 应该跟着一起糊');
      expect(
        scrim.overlaps(tester.getRect(find.byKey(kCommunityBottomBarKey))),
        isTrue,
        reason: '底栏也该一起糊',
      );

      // 关闭按钮落在底栏那一带的正中（也就是原来 ＋ 的位置附近），手指不用挪。
      expect(closeButton(), findsOneWidget);
      final Rect bar = tester.getRect(find.byKey(kCommunityBottomBarKey));
      final Offset closeCenter = tester.getCenter(closeButton());
      expect(closeCenter.dx, closeTo(bar.center.dx, 1));
      expect(closeCenter.dy, closeTo(bar.center.dy, 1));

      await tester.tap(closeButton());
      await settleManually(tester);
      expect(find.text('发布角色卡'), findsNothing);
    });

    testWidgets('顶栏右上角：搜索 | 通知 | 返回，一次点击就回',
        (WidgetTester tester) async {
      int exits = 0;
      // 通知按钮未登录时不渲染，要看到「通知」得先有登录态。
      AuthSession.instance.debugSetSession(
        token: 't',
        user: <String, dynamic>{'username': 'alice'},
      );
      addTearDown(() => AuthSession.instance.debugSetSession());
      await pumpShell(tester, onExit: () => exits++);

      Finder inAppBar(IconData icon) => find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(icon),
          );
      final Finder search = inAppBar(Icons.search);
      final Finder bell = inAppBar(Icons.notifications_outlined);
      final Finder exitBtn = inAppBar(Icons.arrow_back);
      final Finder menu = inAppBar(Icons.menu);
      expect(search, findsOneWidget);
      expect(bell, findsOneWidget);
      expect(exitBtn, findsOneWidget);
      expect(menu, findsOneWidget);

      // 左半区：侧边栏 | 返回。右半区：通知 | 搜索。
      final double width = tester.getSize(find.byType(RootShell)).width;
      final double xMenu = tester.getCenter(menu).dx;
      final double xExit = tester.getCenter(exitBtn).dx;
      final double xBell = tester.getCenter(bell).dx;
      final double xSearch = tester.getCenter(search).dx;
      expect(xMenu, lessThan(xExit), reason: '侧边栏应在返回左边');
      expect(xBell, lessThan(xSearch), reason: '通知应在搜索左边');
      expect(xExit, lessThan(width * 0.5), reason: '返回应在左半区');
      expect(xBell, greaterThan(width * 0.5), reason: '通知应在右半区');

      await tester.tap(exitBtn);
      await settleManually(tester);
      expect(exits, 1);
    });

    testWidgets('底栏顺序：推荐 / 茶馆 / ＋ / 世界 / 我', (WidgetTester tester) async {
      await pumpShell(tester);
      final Finder bar = find.byKey(kCommunityBottomBarKey);
      double xOf(IconData icon) => tester
          .getCenter(find.descendant(of: bar, matching: find.byIcon(icon)))
          .dx;

      final List<double> xs = <double>[
        xOf(Icons.home_outlined),
        xOf(Icons.local_cafe_outlined),
        xOf(Icons.add),
        xOf(Icons.public_outlined),
        xOf(Icons.person_outline),
      ];
      for (int i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]),
            reason: '第 ${i + 1} 格应排在第 $i 格右边');
      }
    });

    testWidgets('设置里关掉「返回主应用」后，顶栏不再出现该按钮',
        (WidgetTester tester) async {
      // 接线方式是「关掉就把 onExitToMainApp 传 null」——顶栏按钮与侧边栏底部
      // 条目都只在 onExitToMainApp != null 时渲染，所以一处开关管两处。
      await pumpShell(tester, showExit: false);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.arrow_back),
        ),
        findsNothing,
      );
      // 其余动作照常。
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.search),
        ),
        findsOneWidget,
      );
    });

    testWidgets('系统返回：社区内部退无可退时交回主应用',
        (WidgetTester tester) async {
      int exits = 0;
      await pumpShell(tester, onExit: () => exits++);

      await pressBack(tester);
      await settleManually(tester);
      expect(exits, 1, reason: '社区根页按返回应回主应用，而不是退出整个应用');
    });

    testWidgets('系统返回：社区内部还有一层时先在内部退，不交回',
        (WidgetTester tester) async {
      int exits = 0;
      await pumpShell(tester, onExit: () => exits++);

      // 切到茶馆，再按返回：应该回「推荐」，而不是回主应用。
      await tester.tap(bottomItem(Icons.local_cafe_outlined));
      await settleManually(tester);

      await pressBack(tester);
      await settleManually(tester);
      expect(exits, 0, reason: '应该先在社区内部退一层');
    });

    testWidgets('枢纽开着时点底栏那一带：只收浮层，不切栏目',
        (WidgetTester tester) async {
      await pumpShell(tester);
      await openHub(tester);

      // 底栏已经被蒙层盖住，所以点那一带只会被蒙层接走 —— 不该顺手切栏目。
      await tester.tapAt(tester.getRect(bottomItem(Icons.local_cafe_outlined)).center);
      await settleManually(tester);

      expect(find.text('发布角色卡'), findsNothing, reason: '枢纽必须收起来');
      expect(
        find.descendant(
          of: find.byKey(kCommunityBottomBarKey),
          matching: find.text('茶馆'),
        ),
        findsNothing,
        reason: '底栏已被盖住，点那一带不该切栏目',
      );
    });

    testWidgets('枢纽开着时按返回：只收枢纽，不退出', (WidgetTester tester) async {
      await pumpShell(tester);
      await openHub(tester);

      await pressBack(tester);
      await settleManually(tester);

      expect(find.text('发布角色卡'), findsNothing, reason: '返回键应先收枢纽');
      expect(find.byKey(kCommunityBottomBarKey), findsOneWidget, reason: '还留在社区里');
    });
  });
}
