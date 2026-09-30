import 'dart:io';

import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/character_library_screen.dart';
import 'package:bookbuddy/services/book_storage_service.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在真实事件循环里执行会产生文件 IO / 网络的操作，随后交替「让出真实时间片」与
/// 「冲刷一次 FakeAsync 微任务队列」，直到 [until] 成立或达到 [maxRounds]。
///
/// 为什么必须交替而不能把两步嵌套在同一个 `runAsync` 里：`CharacterStorageService`
/// 的读改写链路有好几跳真实文件 IO（读 cards.json → 改 → 写临时文件 → 改名备份 →
/// 改名正式文件 → 通知监听者重新加载）。`pumpAndSettle()` 只按 UI 帧是否稳定来判断
/// "是否结束"，并不知道背后还有未完成的磁盘 IO；每一跳完成后的延续都是在 widget 树
/// 所在的 FakeAsync 测试时钟上排队的微任务，必须靠测试驱动在"让出真实时间片"
/// （`runAsync` 里的 `Future.delayed`）与"冲刷一次 FakeAsync 微任务队列"
/// （`pump()`）之间来回切换才能被逐跳取出执行；嵌套在同一个 `runAsync` 里时，这次
/// 冲刷根本不会发生，链路会卡在第一跳。[until] 用于在调用方关心的状态已经出现时
/// 提前退出，避免每次调用都不加区分地付出最坏情况下的完整轮数开销。
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

void main() {
  late Directory dir;
  late Directory bookDir;
  late CharacterStorageService storage;
  late BookStorageService bookStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'bookbuddy_books_migrated_to_files': true,
    });
    dir = Directory.systemTemp.createTempSync('bookbuddy-library-test-');
    bookDir = Directory.systemTemp.createTempSync('bookbuddy-library-books-');
    storage = CharacterStorageService(directory: dir);
    bookStorage = BookStorageService(booksDirectory: bookDir);
  });

  tearDown(() {
    for (final d in [dir, bookDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<void> pumpLibrary(WidgetTester tester) => runIo(
        tester,
        () => tester.pumpWidget(
          MaterialApp(
            home: CharacterLibraryScreen(
              storage: storage,
              bookStorage: bookStorage,
            ),
          ),
        ),
        // 加载完成后 loading 指示器会消失（无论最终是空状态、列表还是错误态）。
        // 卡片先渲染、出演次数随后才到：等到列表带上「出演」字样（或空状态）才算加载完成。
        until: () =>
            (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
                find.textContaining('出演').evaluate().isNotEmpty) ||
            find.text('还没有角色').evaluate().isNotEmpty,
      );

  testWidgets('没有卡片时显示空状态', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('还没有角色'), findsOneWidget);
    expect(find.text('拍一张玩具照片或手动描述，都能创建角色'), findsOneWidget);
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
    expect(find.text('动物 · 定妆图 1 张 · 出演 0 本'), findsOneWidget);
    expect(find.text('小满'), findsOneWidget);
    expect(find.text('物件 · 定妆图 0 张 · 出演 0 本'), findsOneWidget);
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

    await runIo(
      tester,
      () => tester.tap(find.text('删除')),
      // 删除完成、列表刷新后会重新显示空状态文案。
      until: () => find.text('还没有角色').evaluate().isNotEmpty,
    );
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

  testWidgets('出演次数按绘本的 characterCardIds 统计', (tester) async {
    await tester.runAsync(() async {
      await storage.saveCard(
        CharacterCard(id: 'card_a', name: '豆豆', appearance: '绿色'),
      );
      for (final id in ['book-1', 'book-2']) {
        await bookStorage.saveBook(
          PictureBook(
            id: id,
            title: '书 $id',
            styleId: 'watercolor',
            styleName: '水彩童话',
            pages: [BookPageItem(pageIndex: 0, text: '豆豆出发。')],
            createdAt: DateTime.utc(2026, 9, 30),
            characterCardIds: ['card_a'],
          ),
        );
      }
      // 同一本书里重复的 id 只算一次。
      await bookStorage.saveBook(
        PictureBook(
          id: 'book-3',
          title: '书 book-3',
          styleId: 'watercolor',
          styleName: '水彩童话',
          pages: [BookPageItem(pageIndex: 0, text: '豆豆出发。')],
          createdAt: DateTime.utc(2026, 9, 30),
          characterCardIds: ['card_a', 'card_a'],
        ),
      );
    });
    await pumpLibrary(tester);
    expect(find.text('动物 · 定妆图 0 张 · 出演 3 本'), findsOneWidget);
  });
}
