import 'dart:convert';
import 'dart:io';

import 'package:bookbuddy/main.dart';
import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/services/book_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/run_io.dart';

final String _pagePng = base64Encode(
  img.encodePng(img.Image(width: 8, height: 8)),
);

PictureBook _book(String id, String title, {int day = 1}) => PictureBook(
  id: id,
  title: title,
  styleId: 'watercolor',
  styleName: '水彩童话',
  createdAt: DateTime.utc(2026, 9, day),
  pages: [
    BookPageItem(pageIndex: 0, text: '$title 的第一页', imageBase64: _pagePng),
    BookPageItem(pageIndex: 1, text: '$title 的第二页'),
  ],
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory bookDir;
  late BookStorageService bookStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'bookbuddy_books_migrated_to_files': true,
    });
    bookDir = Directory.systemTemp.createTempSync('bookbuddy-shelf-test-');
    bookStorage = BookStorageService(booksDirectory: bookDir);
    // 阅读器内部直接创建 AudioPlayer；测试环境没有平台实现，对它的通道统一应答空结果。
    binding.defaultBinaryMessenger.allMessagesHandler =
        (channel, handler, message) async {
          if (channel.startsWith('xyz.luan/audioplayers')) {
            return const StandardMethodCodec().encodeSuccessEnvelope(null);
          }
          return handler?.call(message);
        };
  });

  tearDown(() {
    binding.defaultBinaryMessenger.allMessagesHandler = null;
    if (bookDir.existsSync()) bookDir.deleteSync(recursive: true);
  });

  bool shows(String text) => find.textContaining(text).evaluate().isNotEmpty;

  /// 先存好 [books]，再打开首页并等书架列出 [books] 的数量。
  Future<void> pumpShelf(WidgetTester tester, List<PictureBook> books) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final book in books) {
        await bookStorage.saveBook(book);
      }
    });
    await runIo(
      tester,
      () => tester.pumpWidget(
        MaterialApp(home: MainHomeScreen(bookStorage: bookStorage)),
      ),
      until: () =>
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          shows('共 ${books.length} 本'),
    );
  }

  /// 卸载页面并走完播放器释放、SnackBar 等遗留的计时器。
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 40));
  }

  testWidgets('书架按创建时间从新到旧列出绘本的摘要信息', (tester) async {
    await pumpShelf(tester, [
      _book('book-old', '旧书', day: 1),
      _book('book-new', '新书', day: 2),
    ]);

    expect(find.text('共 2 本'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('新书')).dy,
      lessThan(tester.getTopLeft(find.text('旧书')).dy),
    );
    expect(find.textContaining('2 页 · 画风: 水彩童话'), findsNWidgets(2));
    expect(find.text('待补画 (1/2)'), findsNWidgets(2));
    await close(tester);
  });

  testWidgets('点开一本绘本时加载整本并进入阅读器', (tester) async {
    await pumpShelf(tester, [_book('book-1', '豆豆的雨天')]);

    await runIo(
      tester,
      () => tester.tap(find.text('豆豆的雨天')),
      until: () => shows('豆豆的雨天 的第一页'),
    );

    expect(find.text('豆豆的雨天 的第一页'), findsOneWidget);
    await close(tester);
  });

  testWidgets('绘本文件读不出来时提示并刷新书架', (tester) async {
    await pumpShelf(tester, [_book('book-1', '豆豆的雨天')]);
    for (final file in bookDir.listSync()) {
      file.deleteSync();
    }

    await runIo(
      tester,
      () => tester.tap(find.text('豆豆的雨天')),
      until: () => shows('打不开') && shows('共 0 本'),
    );

    expect(find.textContaining('打不开绘本《豆豆的雨天》'), findsOneWidget);
    expect(find.text('共 0 本'), findsOneWidget);
    expect(find.text('豆豆的雨天 的第一页'), findsNothing);
    await close(tester);
  });

  testWidgets('连续保存两本后书架两本都列出来', (tester) async {
    await pumpShelf(tester, [_book('book-1', '第一本')]);

    // 第二次保存的通知到达时，第一次通知触发的加载多半还没结束。
    await runIo(tester, () async {
      await bookStorage.saveBook(_book('book-2', '第二本', day: 2));
      await bookStorage.saveBook(_book('book-3', '第三本', day: 3));
    }, until: () => shows('共 3 本'));

    expect(find.text('共 3 本'), findsOneWidget);
    expect(find.text('第三本'), findsOneWidget);
    await close(tester);
  });
}
