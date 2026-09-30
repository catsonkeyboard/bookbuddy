import 'package:bookbuddy/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 测试环境没有 path_provider / shared_preferences 的平台实现。不给这两个方法通道
// 注册处理器时，缺失插件的异常只会在真实事件循环里才被判定，需要靠
// `tester.runAsync` 让出真实时间片才能让 Future 落地；但 `runAsync` 会污染
// 同一个测试体（甚至同一个测试文件里后面的测试）里 `Navigator.push` 的转场，
// 导致页面切换测试即使 tap 成功也看不到新页面。改为直接 mock 这两个方法通道，
// 让「插件不可用」的异常走纯 Dart 的 FakeAsync 微任务队列同步落地，
// 全程只用 `tester.pump()`，不必也不能用 `runAsync`。
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _sharedPrefsChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

Future<dynamic> _unavailable(MethodCall call) async {
  throw PlatformException(
    code: 'unavailable',
    message: '测试环境未提供该插件实现: ${call.method}',
  );
}

/// 等首页 / 角色库页的加载指示器消失（无论最终落进列表、空状态还是错误提示分支）。
///
/// 先做一次零耗时 `pump()` 再做一次 300ms 的 `pump()`：零耗时那次让刚触发的
/// 状态变化（例如 tap 之后的 `Navigator.push`）先被处理并建好新的 widget 树，
/// 300ms 那次再把 `MaterialPageRoute` 的标准转场动画推进到完成；两步顺序不能
/// 对调或合并，否则转场还没开始计时就被推进，新页面不会出现在树里。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  for (var i = 0; i < 10; i++) {
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    await tester.pump();
  }
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, _unavailable);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPrefsChannel, _unavailable);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPrefsChannel, null);
  });

  testWidgets('App load smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BookBuddyApp());
    expect(find.text('📖 BookBuddy 绘本工坊'), findsOneWidget);
    await _settle(tester);
  });

  testWidgets('首页显示角色引导卡与「我的角色」入口', (tester) async {
    await tester.pumpWidget(const BookBuddyApp());
    await _settle(tester);
    expect(find.byTooltip('我的角色'), findsOneWidget);
    expect(find.text('拍一张玩具，做一个专属主角'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '我的角色'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '新建角色'), findsOneWidget);
  });

  testWidgets('点击「我的角色」进入角色库页', (tester) async {
    await tester.pumpWidget(const BookBuddyApp());
    await _settle(tester);
    await tester.tap(find.byTooltip('我的角色'));
    await _settle(tester);
    expect(find.text('👥 我的角色'), findsOneWidget);
  });
}
