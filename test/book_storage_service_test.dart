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
}
