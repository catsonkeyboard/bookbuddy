import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';

class BookStorageService {
  static const _legacyBooksKey = 'bookbuddy_saved_books';
  static const _migratedKey = 'bookbuddy_books_migrated_to_files';

  Future<Directory> _getBooksDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/bookbuddy_books');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 自动迁移 SharedPreferences 中的老旧大包数据到独立文件系统，释放 SharedPreferences 内存压力
  Future<void> _migrateLegacyDataIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasMigrated = prefs.getBool(_migratedKey) ?? false;
      if (hasMigrated) return;

      final rawList = prefs.getStringList(_legacyBooksKey);
      if (rawList != null && rawList.isNotEmpty) {
        final booksDir = await _getBooksDirectory();
        for (final str in rawList) {
          try {
            final map = jsonDecode(str);
            final book = PictureBook.fromJson(map);
            if (book.id.isNotEmpty) {
              final file = File('${booksDir.path}/${book.id}.json');
              await file.writeAsString(str);
            }
          } catch (_) {}
        }
        // 迁移完成后清空 SharedPreferences 中的巨型数组，彻底释放系统 XML 内存
        await prefs.remove(_legacyBooksKey);
      }
      await prefs.setBool(_migratedKey, true);
    } catch (_) {}
  }

  /// 加载所有保存的绘本列表（按创建时间倒序）
  Future<List<PictureBook>> loadBooks() async {
    await _migrateLegacyDataIfNeeded();
    final dir = await _getBooksDirectory();
    final entities = await dir.list().toList();
    final jsonFiles = entities.whereType<File>().where((f) => f.path.endsWith('.json')).toList();

    final bookFutures = jsonFiles.map((file) async {
      try {
        final content = await file.readAsString();
        return PictureBook.fromJson(jsonDecode(content));
      } catch (_) {
        return null;
      }
    });

    final results = await Future.wait(bookFutures);
    final books = results.whereType<PictureBook>().toList();
    books.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return books;
  }

  /// 保存单个绘本（原子化单文件存储，避免全量重新序列化）
  Future<void> saveBook(PictureBook book) async {
    final dir = await _getBooksDirectory();
    final file = File('${dir.path}/${book.id}.json');
    await file.writeAsString(jsonEncode(book.toJson()));
  }

  /// 删除指定绘本及其配套文件
  Future<void> deleteBook(String id) async {
    final dir = await _getBooksDirectory();
    final file = File('${dir.path}/$id.json');
    if (await file.exists()) {
      await file.delete();
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
