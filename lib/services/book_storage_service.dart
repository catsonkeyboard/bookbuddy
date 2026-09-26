import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';

class BookStorageService {
  static const _legacyBooksKey = 'bookbuddy_saved_books';
  static const _migratedKey = 'bookbuddy_books_migrated_to_files';
  static final Map<String, Future<void>> _pendingSaves = {};

  final Directory? _booksDirectory;

  BookStorageService({Directory? booksDirectory})
    : _booksDirectory = booksDirectory;

  Future<Directory> _getBooksDirectory() async {
    final appDir = _booksDirectory ?? await getApplicationDocumentsDirectory();
    final dir = _booksDirectory ?? Directory('${appDir.path}/bookbuddy_books');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Keep legacy data until every entry has been safely written to a file.
  Future<void> _migrateLegacyDataIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey) ?? false) return;

    final rawList = prefs.getStringList(_legacyBooksKey);
    if (rawList != null && rawList.isNotEmpty) {
      final dir = await _getBooksDirectory();
      var allMigrated = true;
      for (final raw in rawList) {
        try {
          final book = PictureBook.fromJson(jsonDecode(raw));
          if (book.id.isEmpty) throw const FormatException('Missing book id');
          final file = File('${dir.path}/${book.id}.json');
          final backup = File('${file.path}.bak');
          // A newer file may already exist after a partially completed migration.
          final current = await _readBook(file, book.id);
          final previous = await _readBook(backup, book.id);
          if (current == null && previous == null) {
            await saveBook(book);
          }
        } catch (_) {
          allMigrated = false;
        }
      }
      if (!allMigrated) return;
      if (!await prefs.remove(_legacyBooksKey)) return;
    }
    await prefs.setBool(_migratedKey, true);
  }

  Future<PictureBook?> _readBook(File file, String expectedId) async {
    try {
      final book = PictureBook.fromJson(jsonDecode(await file.readAsString()));
      return book.id == expectedId ? book : null;
    } catch (_) {
      return null;
    }
  }

  /// Load the last known-good copy if a save was interrupted or corrupt.
  Future<List<PictureBook>> loadBooks() async {
    try {
      await _migrateLegacyDataIfNeeded();
    } catch (_) {
      // Existing files are still readable; legacy preferences remain untouched.
    }
    final dir = await _getBooksDirectory();
    final entities = await dir.list().toList();
    final ids = <String>{};
    for (final file in entities.whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name.endsWith('.json')) {
        ids.add(name.substring(0, name.length - '.json'.length));
      } else if (name.endsWith('.json.bak')) {
        ids.add(name.substring(0, name.length - '.json.bak'.length));
      }
    }

    final results = await Future.wait(
      ids.map((id) async {
        final file = File('${dir.path}/$id.json');
        return await _readBook(file, id) ??
            await _readBook(File('${file.path}.bak'), id);
      }),
    );
    final books = results.whereType<PictureBook>().toList();
    books.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return books;
  }

  /// Write a complete replacement, preserving the previous valid book.
  Future<void> saveBook(PictureBook book) async {
    if (book.id.isEmpty) throw ArgumentError('Book id must not be empty');
    final previous = _pendingSaves[book.id];
    final save = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // A failed earlier save must not block later attempts.
        }
      }
      await _saveBookUnlocked(book);
    }();
    _pendingSaves[book.id] = save;
    try {
      await save;
    } finally {
      if (identical(_pendingSaves[book.id], save)) {
        _pendingSaves.remove(book.id);
      }
    }
  }

  Future<void> _saveBookUnlocked(PictureBook book) async {
    final dir = await _getBooksDirectory();
    final file = File('${dir.path}/${book.id}.json');
    final backup = File('${file.path}.bak');
    final temp = File('${file.path}.tmp');
    final content = jsonEncode(book.toJson());
    await temp.writeAsString(content, flush: true);

    var movedOriginal = false;
    try {
      if (await file.exists()) {
        if (await _readBook(file, book.id) != null) {
          if (await backup.exists()) await backup.delete();
          await file.rename(backup.path);
          movedOriginal = true;
        } else {
          // Retain a damaged file for manual recovery and keep any valid backup.
          final damaged =
              '${file.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}';
          await file.rename(damaged);
        }
      }
      await temp.rename(file.path);
    } catch (_) {
      if (movedOriginal && !await file.exists() && await backup.exists()) {
        await backup.copy(file.path);
      }
      rethrow;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// 删除指定绘本及其配套文件
  Future<void> deleteBook(String id) async {
    final pending = _pendingSaves[id];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    final dir = await _getBooksDirectory();
    for (final suffix in ['.json', '.json.bak', '.json.tmp']) {
      final file = File('${dir.path}/$id$suffix');
      if (await file.exists()) await file.delete();
    }

    // 联动清理对应的音频目录，彻底回收手机存储
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${appDir.path}/bookbuddy_audio/$id');
      if (await audioDir.exists()) {
        await audioDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
