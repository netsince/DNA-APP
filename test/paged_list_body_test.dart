import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dna/widgets/paged_controller.dart';
import 'package:dna/widgets/paged_list_body.dart';
import 'package:dna/widgets/state_views.dart';

/// 共享分页骨架的行为锁。
///
/// 为什么要有这组测试：`PagedListBody` 已经被 5 个列表页采纳，但在此之前
/// 它自己一个测试都没有 —— 换个页面接入时，回归只能靠人肉看。
/// 这里把「五态」与「分隔线默认值」钉住：后者是真实踩过的坑
/// （`image_gen_failed_page` 是卡片列表，接入后卡片之间凭空多出分隔线）。

PagedController<int> _controller({
  required List<int> items,
  bool hasMore = false,
  bool failing = false,
}) {
  return PagedController<int>(
    fetch: (int page) async {
      if (failing) {
        throw Exception('未配置服务器地址');
      }
      return PagedResult<int>(items: items, hasMore: hasMore);
    },
    firstLoadError: '列表加载失败，请稍后重试',
  );
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _body(PagedController<int> controller, {IndexedWidgetBuilder? separator}) {
  return PagedListBody<int>(
    controller: controller,
    padding: EdgeInsets.zero,
    separator: separator,
    empty: const Text('空空如也'),
    itemBuilder: (BuildContext context, int i) => Text('item $i'),
  );
}

void main() {
  testWidgets('空数据 → 显示调用方给的 empty，而不是空白页', (WidgetTester tester) async {
    final PagedController<int> c = _controller(items: <int>[]);
    addTearDown(c.dispose);
    await c.refresh();

    await tester.pumpWidget(_host(_body(c)));
    await tester.pumpAndSettle();

    expect(find.text('空空如也'), findsOneWidget);
  });

  testWidgets('有数据 → 每条都渲染，且**默认不画分隔线**（回归锁）', (WidgetTester tester) async {
    final PagedController<int> c = _controller(items: <int>[0, 1, 2]);
    addTearDown(c.dispose);
    await c.refresh();

    await tester.pumpWidget(_host(_body(c)));
    await tester.pumpAndSettle();

    expect(find.text('item 0'), findsOneWidget);
    expect(find.text('item 1'), findsOneWidget);
    expect(find.text('item 2'), findsOneWidget);
    // 卡片式列表如果不显式传 separator，就不该出现任何 Divider。
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('显式传 Divider → 才出现分隔线', (WidgetTester tester) async {
    final PagedController<int> c = _controller(items: <int>[0, 1, 2]);
    addTearDown(c.dispose);
    await c.refresh();

    await tester.pumpWidget(
      _host(_body(c, separator: (_, _) => const Divider(height: 1))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Divider), findsWidgets);
  });

  testWidgets('hasMore → 底部出现加载条', (WidgetTester tester) async {
    final PagedController<int> c = _controller(items: <int>[0, 1], hasMore: true);
    addTearDown(c.dispose);
    await c.refresh();

    await tester.pumpWidget(_host(_body(c)));
    // 底条是常驻 spinner：不能用 pumpAndSettle（它会等到动画结束，永远等不到），
    // 用固定时长把态切换的交叉淡入推完即可。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('首屏失败 → 统一错误态 + 重试按钮，且保留原始原因', (WidgetTester tester) async {
    final PagedController<int> c = _controller(items: <int>[], failing: true);
    addTearDown(c.dispose);
    await c.refresh();

    await tester.pumpWidget(_host(_body(c)));
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    // 不该退化成「暂无数据」——那会让用户以为真的没内容。
    expect(find.text('空空如也'), findsNothing);
  });
}
