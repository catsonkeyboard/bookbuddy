import 'dart:io';

import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/character_library_screen.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在真实事件循环里执行会产生文件 IO / 网络的操作，随后回到测试时钟刷新界面。
///
/// `CharacterStorageService` 的读改写链路有好几跳真实文件 IO（读 cards.json →
/// 改 → 写临时文件 → 改名备份 → 改名正式文件 → 通知监听者重新加载）。`pumpAndSettle()`
/// 只按 UI 帧是否稳定来判断"是否结束"，并不知道背后还有未完成的磁盘 IO；而单次
/// `runAsync` 内部的 `Future.delayed` 也只能让链路往前挪一跳——每一跳完成后的延续
/// 是在 widget 树所在的 FakeAsync 测试时钟上排队的微任务，必须靠测试驱动在"让出
/// 真实时间片"与"冲刷一次 FakeAsync 微任务队列"之间来回切换才能被逐跳取出执行。
/// 所以这里把这两步拆成同级、反复交替的独立调用（各自一次 `runAsync`/`pump`），
/// 而不是嵌套在同一个 `runAsync` 里，直到整条链路（含通知刷新）彻底跑完。
Future<void> runIo(WidgetTester tester, Future<void> Function() body) async {
  await tester.runAsync(body);
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;
  late CharacterStorageService storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bookbuddy-library-test-');
    storage = CharacterStorageService(directory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpLibrary(WidgetTester tester) => runIo(
        tester,
        () => tester.pumpWidget(
          MaterialApp(home: CharacterLibraryScreen(storage: storage)),
        ),
      );

  testWidgets('没有卡片时显示空状态', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('还没有角色'), findsOneWidget);
    expect(find.text('创建第一个角色'), findsOneWidget);
  });

  testWidgets('显示已保存的卡片、类型与定妆图数量', (tester) async {
    await tester.runAsync(() async {
      await storage.saveCard(
        CharacterCard(
          id: 'card_a',
          name: '豆豆',
          kind: CharacterKind.animal,
          appearance: '绿色毛绒恐龙',
          anchorImagePaths: {'watercolor': 'card_a/anchor_watercolor.png'},
        ),
      );
      await storage.saveCard(
        CharacterCard(
          id: 'card_b',
          name: '小满',
          kind: CharacterKind.object,
          appearance: '灰色鹅卵石',
        ),
      );
    });
    await pumpLibrary(tester);
    expect(find.text('豆豆'), findsOneWidget);
    expect(find.text('动物 · 定妆图 1 张'), findsOneWidget);
    expect(find.text('小满'), findsOneWidget);
    expect(find.text('物件 · 定妆图 0 张'), findsOneWidget);
    expect(find.text('还没有角色'), findsNothing);
  });

  testWidgets('删除需要确认，确认后卡片消失', (tester) async {
    await tester.runAsync(
      () => storage.saveCard(
        CharacterCard(id: 'card_a', name: '豆豆', appearance: '绿色'),
      ),
    );
    await pumpLibrary(tester);

    await tester.tap(find.byTooltip('删除角色'));
    await tester.pumpAndSettle();
    expect(find.text('删除角色「豆豆」'), findsOneWidget);
    expect(find.text('角色卡和它的定妆图将被删除。已生成的绘本不受影响。'), findsOneWidget);

    await runIo(tester, () => tester.tap(find.text('删除')));
    expect(find.text('豆豆'), findsNothing);
    expect(find.text('还没有角色'), findsOneWidget);
    expect(File('${dir.path}/cards.json').readAsStringSync(), '[]');
  });

  testWidgets('取消删除不改变数据', (tester) async {
    await tester.runAsync(
      () => storage.saveCard(
        CharacterCard(id: 'card_a', name: '豆豆', appearance: '绿色'),
      ),
    );
    await pumpLibrary(tester);
    await tester.tap(find.byTooltip('删除角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('豆豆'), findsOneWidget);
  });
}
