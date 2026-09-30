import 'package:flutter_test/flutter_test.dart';

/// 在真实事件循环里执行会产生文件 / 网络 / isolate Future 的操作，然后交替「让出真实时间片」与
/// 「冲刷一次 FakeAsync 微任务队列」，直到 [until] 成立或达到 [maxRounds]。
/// 必须交替两个独立调用而不能嵌套在同一个 runAsync 里：每一跳完成后的延续
/// 排在测试时钟的微任务队列上，只有 pump 一次才会被取出执行。
Future<void> runIo(
  WidgetTester tester,
  Future<void> Function() body, {
  bool Function()? until,
  int maxRounds = 60,
}) async {
  await tester.runAsync(body);
  for (var i = 0; i < maxRounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    if (until != null && until()) break;
  }
  await tester.pumpAndSettle();
}
