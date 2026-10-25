import 'dart:async';

import 'package:bookbuddy/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 所有读取都抛异常的 store：让 loadSettings 真正走上失败分支。
/// 以内存 store 为基类，满足 PlatformInterface 的实例校验。
class _FailingSharedPreferencesStore extends InMemorySharedPreferencesStore {
  _FailingSharedPreferencesStore() : super.empty();

  @override
  Future<Map<String, Object>> getAll() async =>
      throw PlatformException(code: 'unavailable', message: '存储不可用');

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) async =>
      throw PlatformException(code: 'unavailable', message: '存储不可用');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const prefsChannel = MethodChannel('plugins.flutter.io/shared_preferences');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(prefsChannel, null);
  });

  // 回归防护：8a81b85 之前 7 个 TextEditingController 是 late 字段，
  // _load() 返回前用户秒退页面时 dispose() 会抛 LateInitializationError。
  // 这里让 loadSettings 永远不返回，复现「秒退」时序，确认不再崩。
  testWidgets('设置加载完成前退出页面不抛 LateInitializationError', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      prefsChannel,
      (_) => Completer<Object?>().future,
    );

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    // 加载未完成：页面停在转圈状态。
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 秒退：卸载页面并走 dispose()。
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('设置加载完成后渲染配置主界面', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('⚙️ 模型与接口配置'), findsOneWidget);
    expect(find.textContaining('故事文本模型 (LLM Multi-Provider)'), findsOneWidget);
  });

  testWidgets('设置加载失败时显示错误与重试入口', (tester) async {
    // 不能只 mock 平台通道：前一个用例的 setMockInitialValues 已把 store
    // 平台层整体换成内存实现，通道 mock 永远不会被访问；getInstance 的
    // 静态缓存也必须清掉，否则直接复用上个用例的成功实例。
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = _FailingSharedPreferencesStore();

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('加载配置失败'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);

    // 重试不会崩，失败后仍停在错误状态等用户再试。
    await tester.tap(find.widgetWithText(ElevatedButton, '重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('加载配置失败'), findsOneWidget);
  });
}
