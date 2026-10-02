import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';

/// 书架目录里出现过的绘本 id：正式文件和备份文件都算。
Set<String> _bookIdsIn(Iterable<FileSystemEntity> entities) {
  final ids = <String>{};
  for (final file in entities.whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.endsWith('.json')) {
      ids.add(name.substring(0, name.length - '.json'.length));
    } else if (name.endsWith('.json.bak')) {
      ids.add(name.substring(0, name.length - '.json.bak'.length));
    }
  }
  return ids;
}

/// 在后台 isolate 里运行：同步逐本读取，读完一本就丢弃，内存里同时只有一本书。
Map<String, int> _countCharacterCardUsage(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return {};
  final counts = <String, int>{};
  for (final id in _bookIdsIn(dir.listSync())) {
    final cardIds =
        _readCharacterCardIds(File('$dirPath/$id.json'), id) ??
        _readCharacterCardIds(File('$dirPath/$id.json.bak'), id);
    for (final cardId in cardIds ?? const <String>{}) {
      counts[cardId] = (counts[cardId] ?? 0) + 1;
    }
  }
  return counts;
}

/// 读不出来、不是这本书的文件返回 null，由调用方退回备份。
Set<String>? _readCharacterCardIds(File file, String expectedId) {
  try {
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map || json['id'] != expectedId) return null;
    return {
      for (final id in json['characterCardIds'] as List? ?? const [])
        id.toString(),
    };
  } catch (_) {
    return null;
  }
}

/// 在后台 isolate 里运行：逐本读出书架目录里的绘本，主文件读不出来就退回备份。
///
/// 惰性产出：调用方用完一本再取下一本，内存里同时只有一本书。
Iterable<PictureBook> _readBooksIn(String dirPath) sync* {
  for (final id in _bookIdsIn(Directory(dirPath).listSync())) {
    final book = _readBookOrBackup((dirPath, id));
    if (book != null) yield book;
  }
}

/// 在后台 isolate 里运行。
PictureBook? _readBookOrBackup((String, String) dirPathAndId) {
  final (dirPath, id) = dirPathAndId;
  return _readBookSync(File('$dirPath/$id.json'), id) ??
      _readBookSync(File('$dirPath/$id.json.bak'), id);
}

PictureBook? _readBookSync(File file, String expectedId) {
  try {
    final book = PictureBook.fromJson(jsonDecode(file.readAsStringSync()));
    return book.id == expectedId ? book : null;
  } catch (_) {
    return null;
  }
}

/// 在后台 isolate 里运行。
List<PictureBook> _readAllBooks(String dirPath) =>
    _readBooksIn(dirPath).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

/// 在后台 isolate 里运行：每本书读完只留下摘要。
List<BookSummary> _readBookSummaries(String dirPath) =>
    _readBooksIn(dirPath).map(BookSummary.of).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

class BookStorageService {
  static const _legacyBooksKey = 'bookbuddy_saved_books';
  static const _migratedKey = 'bookbuddy_books_migrated_to_files';
  static final Map<String, Future<void>> _pendingSaves = {};

  /// 全局绘本数据变更通知（新建保存、修改保存或删除时触发），用于通知书架列表即时刷新
  static final ValueNotifier<int> booksChangedNotifier = ValueNotifier<int>(0);

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

  Future<Directory> _getMigratedBooksDirectory() async {
    try {
      await _migrateLegacyDataIfNeeded();
    } catch (_) {
      // Existing files are still readable; legacy preferences remain untouched.
    }
    return _getBooksDirectory();
  }

  /// 书架列表用：每本绘本的摘要，按创建时间从新到旧。
  ///
  /// 一本书的 JSON 带着每页插画的 base64，十几 MB。读取和解析都放在后台 isolate 里
  /// 逐本进行，只把摘要带回来；主文件损坏或缺失时用上一次保存的备份。
  Future<List<BookSummary>> loadBookSummaries() async {
    final dir = await _getMigratedBooksDirectory();
    return compute(_readBookSummaries, dir.path);
  }

  /// 打开某一本时加载整本（含插画），同样在后台 isolate 里读取解析。
  /// 主文件和备份都读不出来时返回 null。
  Future<PictureBook?> loadBook(String id) async {
    final dir = await _getBooksDirectory();
    return compute(_readBookOrBackup, (dir.path, id));
  }

  /// Load the last known-good copy if a save was interrupted or corrupt.
  ///
  /// 所有绘本整本留在内存里，书越多越重；只展示列表请用 [loadBookSummaries]。
  Future<List<PictureBook>> loadBooks() async {
    final dir = await _getMigratedBooksDirectory();
    return compute(_readAllBooks, dir.path);
  }

  /// 每张角色卡出演了几本绘本（同一本里重复的卡只算一次）。
  ///
  /// 只需要每本书的 characterCardIds，但书的 JSON 里带着每页插画的 base64，一本十几 MB。
  /// 在主线程读取并解析全部绘本会让界面卡住，所以放到后台 isolate 里逐本处理，
  /// 只把计数带回来。
  Future<Map<String, int>> loadCharacterCardUsage() async {
    final dir = await _getBooksDirectory();
    return compute(_countCharacterCardUsage, dir.path);
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
      booksChangedNotifier.value++;
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

    booksChangedNotifier.value++;
  }
}
