import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/server_config.dart';

/// 请求层在「服务端 / 链路卡死」时的行为。
///
/// 这一组守的是一个真实故障：应用在电脑上「疯狂地无法连接」，而同一网络下
/// 浏览器和手机都正常。根因**不是网络不通**（实测 DNS 1–28ms、TCP 2–40ms、
/// TLS 132–1142ms 都快，15 次连续请求中位 877ms），而是**请求自己把连接池
/// 占满了**：
///
/// * 每次尝试 15 秒超时，每个请求重试 4 次；
/// * .timeout() 只让 Future 报错，**底层连接继续挂着**；
/// * maxConnectionsPerHost = 4 是硬上限。
///
/// 于是几个超时请求就能让后续所有请求排队等死。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('超时不重试，且超时后主动中止请求（连接会被释放）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // TestWidgetsFlutterBinding 会装一层 HttpOverrides，把所有 HTTP 变成
    // 直接返回 400 的假请求（根本不出网）。这条测试要打真的本地服务器，
    // 所以先把它摘掉。
    final HttpOverrides? saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);

    // 一个收到请求就挂着、什么都不回的**裸 socket** 服务端 —— 模拟链路卡死。
    //
    // 用裸 socket 而不是 HttpServer：只有裸 socket 才能在客户端断开时拿到
    // onDone，用它来验证「超时后连接真的被释放了」（HttpServer 从不写响应时
    // 感知不到对端断开）。
    final ServerSocket server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    int connections = 0;
    final Completer<void> clientClosed = Completer<void>();
    server.listen((Socket socket) {
      connections++;
      socket.listen(
        (List<int> _) {},
        onDone: () {
          if (!clientClosed.isCompleted) clientClosed.complete();
        },
        onError: (Object _) {
          if (!clientClosed.isCompleted) clientClosed.complete();
        },
        cancelOnError: true,
      );
    });
    addTearDown(() => server.close());

    await ServerConfig.setBaseUrl('http://127.0.0.1:${server.port}');

    final Stopwatch sw = Stopwatch()..start();
    await expectLater(
      ApiClient.instance.getFeaturedCards(),
      throwsA(anything),
    );
    final int ms = sw.elapsedMilliseconds;

    expect(
      connections,
      1,
      reason: '超时不该重试：无法判断服务端是否已处理，重试 POST 会重复提交；'
          '而且每个请求 4×15 秒地占着连接，正是把连接池拖死的放大器',
    );
    expect(
      ms,
      lessThan(25000),
      reason: '一次尝试就该失败（15 秒档），不该是 4 次尝试叠起来',
    );

    // 关键：超时后连接必须被还回去，否则它会一直挂到服务端或系统超时为止。
    await clientClosed.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail(
        '超时后没有中止请求：连接一直占着，maxConnectionsPerHost=4 '
        '几条泄漏就能让后续所有请求排队等死',
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 90)));
}
