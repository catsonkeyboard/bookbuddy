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
///
/// 全量解析是有意保留的：书 id 校验与 characterCardIds 提取都依赖完整 JSON，
/// 只读前 N 字节的做法对本项目「characterCardIds 排在 pages（base64）之后」
/// 的键序无效，按字节切片提取又会在手写/旧版文件上漏判。整本解析已在后台
/// isolate 逐本进行，不阻塞界面；书目规模下代价可接受。
Set<String>? _readCharacterCardIds(File file, String expectedId) {
  try {
    // 与 _readBookSync 一致：直接从 UTF-8 字节解析，不先拼出整个字符串。
    // 注意：不能用局部变量名 json——它会遮蔽 dart:convert 的顶层常量 json（JsonCodec）。
    final decoded =
        utf8.decoder.fuse(json.decoder).convert(file.readAsBytesSync());
    if (decoded is! Map || decoded['id'] != expectedId) return null;
    return {
      for (final id in decoded['characterCardIds'] as List? ?? const [])
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
    // 直接从 UTF-8 字节解析，不先转成整个字符串：十几 MB 的文件快三倍左右。
    final book = PictureBook.fromJson(
      utf8.decoder.fuse(json.decoder).convert(file.readAsBytesSync())
          as Map<String, dynamic>,
    );
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

/// Windows 上文件被占用时 renameSync 会直接抛错，降级为复制 + 删除。
void _safeRenameSync(File file, String newPath) {
  try {
    file.renameSync(newPath);
  } catch (_) {
    file.copySync(newPath);
    file.deleteSync();
  }
}

/// 在后台 isolate 里运行：清理某本书的历史损坏重命名产物
/// （`<id>.json.corrupt.<时间戳>`），避免长期滞留。目录列举与删除都不阻塞主线程。
/// 在后台 isolate 里运行：删除这本书的全部落盘文件与历史残留。
///
/// 主文件与备份删除失败会向上抛（调用方据此回滚删除墓碑）；其余残留
/// （`.json.tmp`、导入用的 `.json.<uuid>.tmp`、`.json.corrupt.<timestamp>`）
/// 只尽力清理。
void _deleteBookFilesSync((String, String) dirPathAndId) {
  final (dirPath, id) = dirPathAndId;
  final jsonName = '$id.json';
  for (final name in [jsonName, '$jsonName.bak']) {
    final file = File('$dirPath/$name');
    if (file.existsSync()) file.deleteSync();
  }
  try {
    for (final entity in Directory(dirPath).listSync()) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        // 前缀带完整的 '$id.json.'，不会误伤 'x$id.json' 或 '$id.jsonx'。
        if (name.startsWith('$jsonName.')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    }
  } catch (_) {}
}

/// 在后台 isolate 里运行：把整本书编码写盘，上一份有效文件留作备份。
///
/// 编码和对旧文件的校验都要过一遍十几 MB 的插画 base64，所以整段不在主线程做。
/// 直接编码成 UTF-8 字节：先拼出整个 JSON 字符串会多占几十 MB，回收它时主线程也跟着停顿。
void _writeBookFile((String, PictureBook) dirPathAndBook) {
  final (dirPath, book) = dirPathAndBook;
  final file = File('$dirPath/${book.id}.json');
  final backup = File('${file.path}.bak');
  final temp = File('${file.path}.tmp');
  temp.writeAsBytesSync(JsonUtf8Encoder().convert(book.toJson()), flush: true);

  var movedOriginal = false;
  try {
    if (file.existsSync()) {
      if (_readBookSync(file, book.id) != null) {
        if (backup.existsSync()) backup.deleteSync();
        _safeRenameSync(file, backup.path);
        movedOriginal = true;
      } else {
        // Retain a damaged file for manual recovery and keep any valid backup.
        final damaged =
            '${file.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}';
        _safeRenameSync(file, damaged);
      }
    }
    _safeRenameSync(temp, file.path);
  } catch (_) {
    if (movedOriginal && !file.existsSync() && backup.existsSync()) {
      backup.copySync(file.path);
    }
    rethrow;
  } finally {
    // finally 里的清理自身不能再抛：Windows 上 temp 被占用时 deleteSync
    // 会顶替真正的失败原因向上传播。
    try {
      if (temp.existsSync()) temp.deleteSync();
    } catch (_) {}
  }
}

class BookStorageService {
  static const _legacyBooksKey = 'bookbuddy_saved_books';
  static const _migratedKey = 'bookbuddy_books_migrated_to_files';
  static final Map<String, Future<void>> _pendingSaves = {};

  /// 已删除绘本 id 的墓碑：删除后迟到的保存（在途保存、自动保存）直接作废，
  /// 防止「删完又写回」。进程生命周期内有效；导入通道落盘成功后会通过
  /// [clearTombstone] 撤销墓碑，否则「删除 → 重新导入同 id」的书在本进程内
  /// 再也保存不上。
  static final Set<String> _deletedBookIds = {};

  /// 撤销 [id] 的删除墓碑：导入通道以此恢复该 id 的保存资格。
  static void clearTombstone(String id) => _deletedBookIds.remove(id);

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
    final rawList = prefs.getStringList(_legacyBooksKey);
    // 已迁移过且没有残留 legacy 数据才可跳过。降级旧版 → 在旧版里写书 → 再升级
    // 时标记仍为 true 但 StringList 非空，必须继续迁移，否则这批书会丢。
    if ((prefs.getBool(_migratedKey) ?? false) &&
        (rawList == null || rawList.isEmpty)) {
      return;
    }

    if (rawList != null && rawList.isNotEmpty) {
      var allMigrated = true;
      for (final raw in rawList) {
        try {
          final book = PictureBook.fromJson(jsonDecode(raw));
          if (book.id.isEmpty) throw const FormatException('Missing book id');
          // A newer file may already exist after a partially completed migration.
          // 这里必须走不触发迁移的直读，否则 loadBook → 迁移 → loadBook 无限递归。
          final dir = await _getBooksDirectory();
          if (await _readBookFrom(dir, book.id) == null) await saveBook(book);
        } catch (_) {
          allMigrated = false;
        }
      }
      if (!allMigrated) return;
      if (!await prefs.remove(_legacyBooksKey)) return;
    }
    await prefs.setBool(_migratedKey, true);
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
    final dir = await _getMigratedBooksDirectory();
    return _readBookFrom(dir, id);
  }

  /// 从指定目录直读一本（不触发迁移），供迁移流程自身使用。
  Future<PictureBook?> _readBookFrom(Directory dir, String id) =>
      compute(_readBookOrBackup, (dir.path, id));

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
    final dir = await _getMigratedBooksDirectory();
    return compute(_countCharacterCardUsage, dir.path);
  }

  /// Write a complete replacement, preserving the previous valid book.
  Future<void> saveBook(PictureBook book) async {
    // 删除后到达的迟到的保存直接作废，不落盘、不通知。
    if (_deletedBookIds.contains(book.id)) return;
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
      final dir = await _getBooksDirectory();
      await compute(_writeBookFile, (dir.path, book));
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

  /// 删除指定绘本及其配套文件
  Future<void> deleteBook(String id) async {
    // 入队前登记墓碑：删除执行期间/之后到达的迟到保存全部作废。
    _deletedBookIds.add(id);
    // 与 saveBook 相同的链式互斥：删除也占位到 _pendingSaves，
    // 避免和并发 saveBook 产生「删完又写回」或「写完被误删」的竞态。
    final previous = _pendingSaves[id];
    final deletion = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      final dir = await _getBooksDirectory();
      // 一并清理这本书的全部落盘产物与历史残留（.bak、.tmp、uuid 临时文件、
      // .corrupt.<timestamp>），列举与删除放在后台 isolate，书目多时也不卡界面。
      await compute(_deleteBookFilesSync, (dir.path, id));

      // 联动清理对应的音频目录，彻底回收手机存储
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final audioDir = Directory('${appDir.path}/bookbuddy_audio/$id');
        if (await audioDir.exists()) {
          await audioDir.delete(recursive: true);
        }
      } catch (_) {}
    }();
    _pendingSaves[id] = deletion;
    try {
      await deletion;
      booksChangedNotifier.value++;
    } on Exception {
      // 删除链中途失败（文件被占用等）：书可能还留在书架上，此时必须撤销
      // 墓碑，否则这本书在本进程内的所有后续保存都会被静默作废。
      clearTombstone(id);
      rethrow;
    } finally {
      if (identical(_pendingSaves[id], deletion)) {
        _pendingSaves.remove(id);
      }
    }
  }
}
