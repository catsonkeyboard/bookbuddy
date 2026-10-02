import 'dart:convert';
import 'dart:io';

import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/services/book_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

PictureBook _book(String title) => PictureBook(
  id: 'book-1',
  title: title,
  styleId: 'watercolor',
  styleName: 'Watercolor',
  pages: [BookPageItem(pageIndex: 0, text: 'Once upon a time')],
  createdAt: DateTime.utc(2026, 9, 26),
);

/// 记录 toJson 有没有在「当前 isolate」里被调用。静态变量每个 isolate 各有一份，
/// 编码发生在后台 isolate 时，测试所在的 isolate 看到的仍是 false。
class _EncodeSpyBook extends PictureBook {
  static bool encodedOnThisIsolate = false;

  _EncodeSpyBook(String title)
    : super(
        id: 'book-1',
        title: title,
        styleId: 'watercolor',
        styleName: 'Watercolor',
        pages: [BookPageItem(pageIndex: 0, text: 'Once upon a time')],
        createdAt: DateTime.utc(2026, 9, 26),
      );

  @override
  Map<String, dynamic> toJson() {
    encodedOnThisIsolate = true;
    return super.toJson();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late BookStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'bookbuddy_books_migrated_to_files': true,
    });
    dir = await Directory.systemTemp.createTemp('bookbuddy-storage-test-');
    storage = BookStorageService(booksDirectory: dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test(
    'recovers the previous book after a damaged or missing main file',
    () async {
      await storage.saveBook(_book('Original'));
      await storage.saveBook(_book('Updated'));

      final main = File('${dir.path}/book-1.json');
      final backup = File('${main.path}.bak');
      expect((await storage.loadBooks()).single.title, 'Updated');
      expect(
        PictureBook.fromJson(jsonDecode(await backup.readAsString())).title,
        'Original',
      );

      await main.writeAsString('{incomplete', flush: true);
      expect((await storage.loadBooks()).single.title, 'Original');

      await main.delete();
      expect((await storage.loadBooks()).single.title, 'Original');
      await storage.saveBook(_book('Recovered'));
      expect((await storage.loadBooks()).single.title, 'Recovered');
      expect(await backup.exists(), isTrue);
    },
  );

  test('keeps legacy data if any book cannot be migrated', () async {
    SharedPreferences.setMockInitialValues({
      'bookbuddy_saved_books': [
        jsonEncode(_book('Legacy').toJson()),
        '{broken',
      ],
    });
    expect((await storage.loadBooks()).single.title, 'Legacy');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('bookbuddy_saved_books'), hasLength(2));
    expect(prefs.getBool('bookbuddy_books_migrated_to_files'), isNot(true));
  });

  test('does not replace newer files with old migration data', () async {
    await storage.saveBook(_book('Newer'));
    SharedPreferences.setMockInitialValues({
      'bookbuddy_saved_books': [jsonEncode(_book('Older').toJson())],
    });
    expect((await storage.loadBooks()).single.title, 'Newer');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('bookbuddy_saved_books'), isNull);
    expect(prefs.getBool('bookbuddy_books_migrated_to_files'), isTrue);
  });

  test('serializes concurrent saves for the same book', () async {
    await Future.wait([
      storage.saveBook(_book('First')),
      storage.saveBook(_book('Second')),
    ]);
    expect((await storage.loadBooks()).single.title, 'Second');
    expect(await File('${dir.path}/book-1.json.bak').exists(), isTrue);
  });

  test('notifies booksChangedNotifier on saveBook and deleteBook', () async {
    final initialValue = BookStorageService.booksChangedNotifier.value;
    await storage.saveBook(_book('Notify Test'));
    expect(BookStorageService.booksChangedNotifier.value, initialValue + 1);

    await storage.deleteBook('book-1');
    expect(BookStorageService.booksChangedNotifier.value, initialValue + 2);
    expect(await storage.loadBooks(), isEmpty);
  });

  group('saveBook', () {
    test('encodes the book off the calling isolate', () async {
      _EncodeSpyBook.encodedOnThisIsolate = false;

      await storage.saveBook(_EncodeSpyBook('Spy'));

      expect(_EncodeSpyBook.encodedOnThisIsolate, isFalse);
      expect((await storage.loadBooks()).single.title, 'Spy');
    });

    test('keeps the file format, non-ASCII text included', () async {
      // 中文、代理对 emoji、落单的代理项、引号、反斜杠和控制字符。
      const tricky = '小恐龙 🦕 \uD83E said "hi" \\ \n\t\u0001 end';
      final book = PictureBook(
        id: 'book-1',
        title: tricky,
        styleId: 'watercolor',
        styleName: '水彩童话',
        createdAt: DateTime.utc(2026, 9, 26),
        pages: [BookPageItem(pageIndex: 0, text: tricky)],
      );

      await storage.saveBook(book);

      final file = File('${dir.path}/book-1.json');
      expect(await file.readAsBytes(), utf8.encode(jsonEncode(book.toJson())));
      final loaded = await storage.loadBook('book-1');
      expect(loaded!.title, tricky);
      expect(loaded.pages.single.text, tricky);
    });

    test('sets a damaged main file aside and keeps the backup', () async {
      await storage.saveBook(_book('Original'));
      await storage.saveBook(_book('Updated'));
      final main = File('${dir.path}/book-1.json');
      await main.writeAsString('{incomplete', flush: true);

      await storage.saveBook(_book('Recovered'));

      expect((await storage.loadBooks()).single.title, 'Recovered');
      final names = dir.listSync().map((f) => f.uri.pathSegments.last).toList();
      final corrupt = names.where((n) => n.startsWith('book-1.json.corrupt.'));
      expect(corrupt, hasLength(1));
      expect(
        await File('${dir.path}/${corrupt.single}').readAsString(),
        '{incomplete',
      );
      expect(
        PictureBook.fromJson(
          jsonDecode(await File('${main.path}.bak').readAsString()),
        ).title,
        'Original',
      );
      expect(names, isNot(contains('book-1.json.tmp')));
    });

    test('a failed save reports the error and does not block the next one', () async {
      // 临时文件的位置被一个目录占住，写入必然失败。
      final blocker = Directory('${dir.path}/book-1.json.tmp');
      await blocker.create();
      final ticks = BookStorageService.booksChangedNotifier.value;

      await expectLater(
        storage.saveBook(_book('Blocked')),
        throwsA(isA<FileSystemException>()),
      );
      expect(BookStorageService.booksChangedNotifier.value, ticks);
      expect(await storage.loadBooks(), isEmpty);

      await blocker.delete();
      await storage.saveBook(_book('Later'));
      expect((await storage.loadBooks()).single.title, 'Later');
    });
  });

  group('loadCharacterCardUsage', () {
    PictureBook bookWithCards(String id, List<String> cardIds) => PictureBook(
      id: id,
      title: id,
      styleId: 'watercolor',
      styleName: 'Watercolor',
      pages: [BookPageItem(pageIndex: 0, text: 'Once upon a time')],
      createdAt: DateTime.utc(2026, 9, 26),
      characterCardIds: cardIds,
    );

    test('counts each card once per book', () async {
      await storage.saveBook(bookWithCards('book-1', ['card_a', 'card_b']));
      await storage.saveBook(bookWithCards('book-2', ['card_a', 'card_a']));
      await storage.saveBook(bookWithCards('book-3', []));

      expect(await storage.loadCharacterCardUsage(), {'card_a': 2, 'card_b': 1});
    });

    test('is empty when there are no books', () async {
      expect(await storage.loadCharacterCardUsage(), isEmpty);
    });

    test('falls back to the backup and skips unreadable books', () async {
      await storage.saveBook(bookWithCards('book-1', ['card_a']));
      await storage.saveBook(bookWithCards('book-1', ['card_b']));
      // 主文件损坏：用备份（上一次保存的 card_a）。
      await File('${dir.path}/book-1.json').writeAsString('{broken');
      // 没有备份的损坏文件、id 对不上的文件都不计入。
      await File('${dir.path}/book-2.json').writeAsString('not json');
      await File('${dir.path}/book-3.json').writeAsString(
        jsonEncode(bookWithCards('someone-else', ['card_c']).toJson()),
      );

      expect(await storage.loadCharacterCardUsage(), {'card_a': 1});
    });
  });

  group('loadBookSummaries', () {
    test('lists what the shelf shows, newest first', () async {
      await storage.saveBook(
        PictureBook(
          id: 'older',
          title: 'Older',
          styleId: 'watercolor',
          styleName: 'Watercolor',
          createdAt: DateTime.utc(2026, 9, 1),
          pages: [BookPageItem(pageIndex: 0, text: 'a', imageBase64: 'aW1n')],
        ),
      );
      await storage.saveBook(
        PictureBook(
          id: 'newer',
          title: 'Newer',
          styleId: 'pixar',
          styleName: 'Pixar',
          createdAt: DateTime.utc(2026, 9, 2),
          characterCardIds: ['card_a'],
          pages: [
            BookPageItem(pageIndex: 0, text: 'a', imageBase64: 'aW1n'),
            BookPageItem(pageIndex: 1, text: 'b'),
            BookPageItem(pageIndex: 2, text: 'c', needIllustration: false),
          ],
        ),
      );

      final summaries = await storage.loadBookSummaries();

      expect(summaries.map((s) => s.id), ['newer', 'older']);
      final newer = summaries.first;
      expect(newer.title, 'Newer');
      expect(newer.styleName, 'Pixar');
      expect(newer.createdAt, DateTime.utc(2026, 9, 2));
      expect(newer.pageCount, 3);
      expect(newer.usesCharacterCards, isTrue);
      expect(newer.completedIllustrationCount, 1);
      expect(newer.targetIllustrationCount, 2);
      expect(newer.hasUnfinishedIllustrations, isTrue);
      final older = summaries.last;
      expect(older.pageCount, 1);
      expect(older.usesCharacterCards, isFalse);
      expect(older.hasUnfinishedIllustrations, isFalse);
    });

    test('falls back to the backup and skips unreadable books', () async {
      await storage.saveBook(_book('Original'));
      await storage.saveBook(_book('Updated'));
      await File('${dir.path}/book-1.json').writeAsString('{broken');
      await File('${dir.path}/book-2.json').writeAsString('not json');
      await File('${dir.path}/book-3.json').writeAsString(
        jsonEncode(_book('Someone else').toJson()),
      );

      final summaries = await storage.loadBookSummaries();

      expect(summaries.map((s) => s.title), ['Original']);
    });

    test('migrates legacy data before listing', () async {
      SharedPreferences.setMockInitialValues({
        'bookbuddy_saved_books': [jsonEncode(_book('Legacy').toJson())],
      });

      expect((await storage.loadBookSummaries()).single.title, 'Legacy');
      expect(await File('${dir.path}/book-1.json').exists(), isTrue);
    });
  });

  group('loadBook', () {
    test('returns the whole book, illustrations included', () async {
      await storage.saveBook(
        PictureBook(
          id: 'book-1',
          title: 'Full',
          styleId: 'watercolor',
          styleName: 'Watercolor',
          createdAt: DateTime.utc(2026, 9, 26),
          protagonistRefImage: 'cmVm',
          pages: [
            BookPageItem(pageIndex: 0, text: 'a', imageBase64: 'aW1n'),
            BookPageItem(pageIndex: 1, text: 'b'),
          ],
        ),
      );

      final book = await storage.loadBook('book-1');

      expect(book!.title, 'Full');
      expect(book.protagonistRefImage, 'cmVm');
      expect(book.pages.map((p) => p.text), ['a', 'b']);
      expect(book.pages.first.imageBase64, 'aW1n');
    });

    test('falls back to the backup when the main file is damaged', () async {
      await storage.saveBook(_book('Original'));
      await storage.saveBook(_book('Updated'));
      await File('${dir.path}/book-1.json').writeAsString('{broken');

      expect((await storage.loadBook('book-1'))!.title, 'Original');
    });

    test('returns null when no readable copy exists', () async {
      await File('${dir.path}/book-2.json').writeAsString('not json');

      expect(await storage.loadBook('missing'), isNull);
      expect(await storage.loadBook('book-2'), isNull);
    });
  });
}
