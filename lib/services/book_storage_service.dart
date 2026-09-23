import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';

class BookStorageService {
  static const _booksKey = 'bookbuddy_saved_books';

  Future<List<PictureBook>> loadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_booksKey) ?? [];
    return rawList.map((str) {
      try {
        return PictureBook.fromJson(jsonDecode(str));
      } catch (_) {
        return null;
      }
    }).whereType<PictureBook>().toList();
  }

  Future<void> saveBook(PictureBook book) async {
    final prefs = await SharedPreferences.getInstance();
    final books = await loadBooks();
    final idx = books.indexWhere((b) => b.id == book.id);
    if (idx != -1) {
      books[idx] = book;
    } else {
      books.insert(0, book);
    }
    final rawList = books.map((b) => jsonEncode(b.toJson())).toList();
    await prefs.setStringList(_booksKey, rawList);
  }

  Future<void> deleteBook(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final books = await loadBooks();
    books.removeWhere((b) => b.id == id);
    final rawList = books.map((b) => jsonEncode(b.toJson())).toList();
    await prefs.setStringList(_booksKey, rawList);
  }
}
