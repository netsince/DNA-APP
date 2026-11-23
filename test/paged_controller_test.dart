import 'package:dna/widgets/paged_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 分页状态机的契约：全项目 16 个列表页共用这一份，行为必须锁死。
void main() {
  /// 造一个可控的 loader：pages 里放每页的条目数，null 表示这一页抛错。
  PagedController<int> build(List<int?> pages, {void Function()? onChanged}) {
    return PagedController<int>(
      fetch: (page) async {
        if (page > pages.length) return const PagedResult<int>(items: <int>[], hasMore: false);
        final int? size = pages[page - 1];
        if (size == null) throw Exception('boom');
        return PagedResult<int>(
          items: List<int>.generate(size, (i) => page * 100 + i),
          hasMore: page < pages.length,
        );
      },
      onChanged: onChanged,
    );
  }

  test('首屏：加载成功后 items/page/hasMore 正确，且不再是加载中', () async {
    final PagedController<int> c = build(<int?>[3, 2]);
    expect(c.isLoading, isFalse);
    await c.refresh();
    expect(c.items.length, 3);
    expect(c.page, 1);
    expect(c.hasMore, isTrue);
    expect(c.loadedOnce, isTrue);
    expect(c.isLoading, isFalse);
    expect(c.error, isNull);
  });

  test('加载更多：页码递增、内容追加，最后一页后 hasMore=false', () async {
    final PagedController<int> c = build(<int?>[3, 2]);
    await c.refresh();
    await c.loadMore();
    expect(c.items.length, 5);
    expect(c.page, 2);
    expect(c.hasMore, isFalse);
  });

  test('hasMore=false 之后再调 loadMore 不会再请求', () async {
    int calls = 0;
    final PagedController<int> c = PagedController<int>(
      fetch: (page) async {
        calls++;
        return const PagedResult<int>(items: <int>[1], hasMore: false);
      },
    );
    await c.refresh();
    await c.loadMore();
    await c.loadMore();
    expect(calls, 1);
  });

  test('空页算「没有更多」（与旧实现 has_next != true 一致）', () async {
    final PagedController<int> c = PagedController<int>(
      fetch: (page) async => const PagedResult<int>(items: <int>[], hasMore: true),
    );
    await c.refresh();
    expect(c.hasMore, isFalse);
    expect(c.isEmpty, isTrue);
  });

  test('刷新：清空旧内容重来，不叠加', () async {
    final PagedController<int> c = build(<int?>[3, 2]);
    await c.refresh();
    await c.loadMore();
    expect(c.items.length, 5);
    await c.refresh();
    expect(c.items.length, 3);
    expect(c.page, 1);
  });

  test('首屏失败：记错误，且 items 保持空', () async {
    final PagedController<int> c = PagedController<int>(
      fetch: (page) async => throw Exception('boom'),
      firstLoadError: '挂了',
    );
    await c.refresh();
    expect(c.error, contains('挂了'));
    expect(c.error, contains('boom'), reason: '异常原文不该被藏起来');
    expect(c.items, isEmpty);
    expect(c.isLoading, isFalse);
  });

  test('异常不藏：首屏错误文案里带原始异常信息，errorObject 保留异常', () async {
    final PagedController<int> c = PagedController<int>(
      fetch: (page) async => throw StateError('服务器地址未配置'),
      firstLoadError: '加载失败',
    );
    await c.refresh();
    expect(c.error, contains('服务器地址未配置'), reason: '原始异常必须露出来，不能只给一句"加载失败"');
    expect(c.error, contains('加载失败'), reason: '同时保留人话前缀');
    expect(c.errorObject, isA<StateError>());
  });

  test('翻页失败：保留已加载内容，不显示首屏错误', () async {
    final PagedController<int> c = build(<int?>[2, null]);
    await c.refresh();
    await c.loadMore();
    expect(c.items.length, 2, reason: '已经拿到的内容不该被清掉');
    expect(c.error, isNull, reason: '翻页失败不该让整页变成错误态');
    expect(c.errorObject, isNotNull, reason: '翻页失败的异常同样要留下来，不能悄悄吞掉');
  });

  test('恢复：失败后再刷新能成功并清掉错误', () async {
    bool fail = true;
    final PagedController<int> c = PagedController<int>(
      fetch: (page) async {
        if (fail) throw Exception('boom');
        return const PagedResult<int>(items: <int>[7], hasMore: false);
      },
    );
    await c.refresh();
    expect(c.error, isNotNull);
    fail = false;
    await c.refresh();
    expect(c.error, isNull);
    expect(c.items, <int>[7]);
  });

  test('并发保护：同一时刻绝不会有 2 个请求在飞（第二次排队）', () async {
    int calls = 0;
    int active = 0;
    int maxActive = 0;
    final PagedController<int> c = PagedController<int>(
      fetch: (page) async {
        calls++;
        active++;
        if (active > maxActive) maxActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return const PagedResult<int>(items: <int>[1], hasMore: true);
      },
    );
    final Future<void> a = c.refresh();
    final Future<void> b = c.refresh();
    await Future.wait(<Future<void>>[a, b]);
    expect(maxActive, 1, reason: '同一时刻只能有一个请求在飞');
    expect(calls, 2, reason: '第二次 refresh 是排队补跑，不是丢弃');
  });

  test('忙时要求刷新：本次结束后自动补一次（用户操作不被丢掉）', () async {
    int calls = 0;
    String keyword = 'A';
    final List<String> seen = <String>[];
    final PagedController<int> c = PagedController<int>(
      fetch: (page) async {
        calls++;
        seen.add(keyword);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return const PagedResult<int>(items: <int>[1], hasMore: true);
      },
    );
    final Future<void> first = c.refresh();
    keyword = 'B';
    final Future<void> second = c.refresh(); // 在飞时改条件再刷新
    await Future.wait(<Future<void>>[first, second]);
    expect(calls, 2, reason: '应该补一次，而不是把第二次刷新丢掉');
    expect(seen, <String>['A', 'B'], reason: '第二次请求必须用新条件');
  });

  test('dispose 之后不再触发回调，也不改状态', () async {
    int notified = 0;
    final PagedController<int> c = build(<int?>[2], onChanged: () => notified++);
    c.dispose();
    await c.refresh();
    expect(notified, 0);
    expect(c.items, isEmpty);
  });

  test('firstPage 可配（有的接口从 0 开始）', () async {
    final List<int> asked = <int>[];
    final PagedController<int> c = PagedController<int>(
      firstPage: 0,
      fetch: (page) async {
        asked.add(page);
        return const PagedResult<int>(items: <int>[1], hasMore: false);
      },
    );
    await c.refresh();
    expect(asked, <int>[0]);
    expect(c.page, 0);
  });
}
