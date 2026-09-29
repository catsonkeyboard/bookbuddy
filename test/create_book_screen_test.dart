import 'dart:io';

import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/create_book_screen.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在真实事件循环里执行会产生文件 IO 的操作，然后交替「让出真实时间片」与
/// 「冲刷一次 FakeAsync 微任务队列」，直到 [until] 成立或达到 [maxRounds]。
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

CharacterCard card(String id, String name, {Map<String, String>? anchors}) =>
    CharacterCard(
      id: id,
      name: name,
      appearance: '外貌 $name',
      catchphrase: '$name 来啦',
      anchorImagePaths: anchors,
    );

void main() {
  late Directory dir;
  late CharacterStorageService storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bookbuddy-create-test-');
    storage = CharacterStorageService(directory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpCreate(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await runIo(
      tester,
      () => tester.pumpWidget(
        MaterialApp(home: CreateBookScreen(characterStorage: storage)),
      ),
      until: () => find.text('👥 选择角色卡（可选，最多 3 张）').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
  }

  testWidgets('角色库为空时显示去创建角色入口', (tester) async {
    await pumpCreate(tester);
    expect(find.text('去创建角色'), findsOneWidget);
  });

  testWidgets('最多选择三张角色卡，第四张被拒绝并提示', (tester) async {
    await tester.runAsync(() async {
      for (final c in [
        card('card_a', '豆豆', anchors: {'watercolor': 'card_a/anchor_watercolor.png'}),
        card('card_b', '小满'),
        card('card_c', '阿福'),
        card('card_d', '毛毛'),
      ]) {
        await storage.saveCard(c);
      }
    });
    await pumpCreate(tester);

    for (final name in ['豆豆', '小满', '阿福']) {
      await tester.tap(find.widgetWithText(FilterChip, name));
      await tester.pumpAndSettle();
    }
    expect(find.text('豆豆 · 豆豆 来啦'), findsOneWidget);
    expect(find.text('在故事里直接用名字称呼他们'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '毛毛'));
    await tester.pumpAndSettle();
    expect(find.text('每本绘本最多选择 3 张角色卡'), findsOneWidget);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '毛毛')).selected, isFalse);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '豆豆')).selected, isTrue);

    // 小满、阿福没有水彩定妆图，豆豆有。
    expect(find.text('进入审核后会先为 小满、阿福 绘制该画风的定妆照'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '豆豆'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '豆豆')).selected, isFalse);
    expect(find.text('豆豆 · 豆豆 来啦'), findsNothing);
  });
}
