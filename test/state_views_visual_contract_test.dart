import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 三态组件的**视觉契约**。
///
/// ## 为什么不是像素 golden
///
/// 项目里没有 golden 先例，而且中文渲染依赖 8MB 的思源黑体 ——
/// 在 `flutter test` 的无头引擎里 `FontLoader.load()` 会长时间挂起（实测）。
/// 用像素截图等于每次测试跑都要加载 8MB 字体，且换机器/换字体版本就会全红。
///
/// 所以这里锁的是**尺寸与层级**（golden 真正能抓的那类回归），
/// 用 `getSize` / `Icon.size` / `padding` 直接量，比像素比对稳、也更容易读：
///
/// * 空态图标必须是 48（曾经社区是 44）
/// * 紧凑态必须是 32
/// * 内距必须是 `AppInsets.page`（曾经社区是 all(24)）
/// * 空态按钮是 `FilledButton`、错误态是 `OutlinedButton`（层级不能混）
/// * 错误态图标与空态同级（都是 48，错误不该看着比空更轻）
void main() {
  Future<void> pumpState(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: child)),
    );
    await tester.pumpAndSettle();
  }

  group('空态 AppEmptyState', () {
    testWidgets('整页空态：图标用 AppSize.iconEmpty（48）', (WidgetTester tester) async {
      await pumpState(
        tester,
        const AppEmptyState(icon: Icons.inbox_outlined, title: '暂无内容'),
      );
      final Icon icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.size, AppSize.iconEmpty);
      expect(icon.size, 48);
      // 实际渲染尺寸也要是 48，防止外层被压缩。
      expect(tester.getSize(find.byIcon(Icons.inbox_outlined)).width, 48);
    });

    testWidgets('紧凑空态：图标用 AppSize.iconEmptyCompact（32）', (WidgetTester tester) async {
      await pumpState(
        tester,
        const AppEmptyState(
          icon: Icons.inbox_outlined,
          title: '暂无内容',
          compact: true,
        ),
      );
      final Icon icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.size, AppSize.iconEmptyCompact);
      expect(icon.size, 32);
    });

    testWidgets('图标颜色走 outline（弱化，不抢标题）', (WidgetTester tester) async {
      await pumpState(
        tester,
        const AppEmptyState(icon: Icons.inbox_outlined, title: '暂无内容'),
      );
      final BuildContext ctx = tester.element(
        find.byType(AppEmptyState),
      );
      final Icon icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.color, Theme.of(ctx).colorScheme.outline);
    });

    testWidgets('整页空态内距用 AppInsets.page', (WidgetTester tester) async {
      await pumpState(
        tester,
        const AppEmptyState(icon: Icons.inbox_outlined, title: '暂无内容'),
      );
      // 找到包住内容的 Padding，取它的 padding。
      final Finder pad = find
          .descendant(
            of: find.byType(AppEmptyState),
            matching: find.byType(Padding),
          )
          .first;
      final Padding p = tester.widget<Padding>(pad);
      expect(p.padding, AppInsets.page);
    });

    testWidgets('有 actionLabel 时用 FilledButton（主操作）', (WidgetTester tester) async {
      await pumpState(
        tester,
        AppEmptyState(
          icon: Icons.inbox_outlined,
          title: '还没有内容',
          actionLabel: '去创建',
          onAction: () {},
        ),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('没有 onAction 时不渲染按钮', (WidgetTester tester) async {
      await pumpState(
        tester,
        const AppEmptyState(
          icon: Icons.inbox_outlined,
          title: '还没有内容',
          actionLabel: '去创建',
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('description 与 message 等价（社区旧名兼容）', (WidgetTester tester) async {
      await pumpState(
        tester,
        const AppEmptyState(
          icon: Icons.inbox_outlined,
          title: '标题',
          description: '用新名',
        ),
      );
      expect(find.text('用新名'), findsWidgets);

      await pumpState(
        tester,
        const AppEmptyState(
          icon: Icons.inbox_outlined,
          title: '标题',
          message: '用旧名',
        ),
      );
      expect(find.text('用旧名'), findsWidgets);
    });
  });

  group('错误态 AppErrorState', () {
    testWidgets('图标与空态同级（48，不能比空态轻）', (WidgetTester tester) async {
      await pumpState(tester, const AppErrorState());
      final Icon icon = tester.widget<Icon>(
        find.byIcon(Icons.cloud_off_outlined),
      );
      expect(icon.size, AppSize.iconEmpty);
      expect(icon.size, 48);
    });

    testWidgets('紧凑错误态 32', (WidgetTester tester) async {
      await pumpState(tester, const AppErrorState(compact: true));
      final Icon icon = tester.widget<Icon>(
        find.byIcon(Icons.cloud_off_outlined),
      );
      expect(icon.size, AppSize.iconEmptyCompact);
    });

    testWidgets('默认文案是「加载失败」', (WidgetTester tester) async {
      await pumpState(tester, const AppErrorState());
      expect(find.text('加载失败'), findsWidgets);
    });

    testWidgets('有 onRetry 时用 OutlinedButton（次操作，与空态区分）', (WidgetTester tester) async {
      await pumpState(tester, AppErrorState(onRetry: () {}));
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('重试'), findsWidgets);
    });

    testWidgets('没有 onRetry 时不渲染重试按钮', (WidgetTester tester) async {
      await pumpState(tester, const AppErrorState());
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  /// 加载态**不能**用 pumpAndSettle：
  /// CircularProgressIndicator 是无限循环动画，永远等不到静止，会直接超时。
  Future<void> pumpSpinner(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  group('加载态 AppLoadingState', () {
    testWidgets('渲染一个转圈；无 message 时不显示文字', (WidgetTester tester) async {
      await pumpSpinner(tester, const AppLoadingState());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('有 message 时显示在转圈下方', (WidgetTester tester) async {
      await pumpSpinner(tester, const AppLoadingState(message: '正在加载'));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('正在加载'), findsWidgets);
      final double spinnerY = tester
          .getCenter(find.byType(CircularProgressIndicator))
          .dy;
      final double textY = tester.getCenter(find.text('正在加载').first).dy;
      expect(textY, greaterThan(spinnerY), reason: '文字应在转圈下方');
    });
  });
}
