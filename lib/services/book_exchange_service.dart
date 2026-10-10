import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/book.dart';
import 'book_storage_service.dart';

/// `.bb` 是本项目绘本的专用导出格式：一个 ZIP 容器（思路同 .epub/.docx），
/// 内含 mimetype 自标识、manifest 元数据、完整的 book.json 与每页朗读音频。
///
/// ```
/// mimetype              "application/x-bookbuddy-book"（STORED，永远第一个条目）
/// manifest.json         格式标识、formatVersion、导出时间与 App 版本
/// book.json             PictureBook.toJson() 原样（插画 base64 都在内）
/// audio/audio_p{i}.mp3  每页朗读音频（STORED：mp3 已压缩，再 deflate 白费 CPU）
/// ```
abstract final class BbFormat {
  static const String mimeType = 'application/x-bookbuddy-book';
  static const String mimetypeEntry = 'mimetype';
  static const String manifestEntry = 'manifest.json';
  static const String bookEntry = 'book.json';
  static const String audioDirPrefix = 'audio/';
  static const int formatVersion = 1;

  /// 单个 .bb 文件（压缩前）的大小上限，防 zip 炸弹。
  static const int maxFileBytes = 100 * 1024 * 1024;

  /// 条目声明解压后尺寸的总和上限：一本书十几 MB 是常态，乘个安全系数。
  static const int maxTotalUncompressedBytes = 400 * 1024 * 1024;
}

/// 导入结果：最终落盘的绘本（id/标题可能已因冲突改写）与是否为副本。
class BookImportResult {
  const BookImportResult({required this.book, required this.isDuplicateCopy});

  final PictureBook book;
  final bool isDuplicateCopy;
}

/// .bb 导入导出过程中所有可预期的失败，message 可直接展示给用户。
class BookExchangeException implements Exception {
  const BookExchangeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ExportPayload {
  const _ExportPayload(this.book, this.audioFiles, this.appVersion);

  final PictureBook book;
  final Map<int, Uint8List> audioFiles;
  final String appVersion;
}

/// 在后台 isolate 里运行：把一本书打包成 .bb 字节。
Uint8List _encodeBbBytes(_ExportPayload payload) {
  final archive = Archive();
  // mimetype 永远是第一个条目且不压缩（OCF/epub 惯例，便于格式自识别）。
  archive.add(
    ArchiveFile(
      BbFormat.mimetypeEntry,
      BbFormat.mimeType.length,
      utf8.encode(BbFormat.mimeType),
    )..compression = CompressionType.none,
  );

  final manifest = jsonEncode({
    'format': 'bookbuddy-book',
    'formatVersion': BbFormat.formatVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'appVersion': payload.appVersion,
  });
  archive.add(
    ArchiveFile(
      BbFormat.manifestEntry,
      manifest.length,
      utf8.encode(manifest),
    ),
  );

  final bookJson = JsonUtf8Encoder().convert(payload.book.toJson());
  archive.add(ArchiveFile(BbFormat.bookEntry, bookJson.length, bookJson));

  payload.audioFiles.forEach((pageIndex, bytes) {
    final name = '${BbFormat.audioDirPrefix}audio_p$pageIndex.mp3';
    archive.add(
      ArchiveFile(name, bytes.length, bytes)..compression =
          CompressionType.none,
    );
  });

  return ZipEncoder().encodeBytes(archive);
}

/// 在后台 isolate 里运行：解析 .bb 字节为书 + 音频（只解析，不落盘）。
(PictureBook, Map<int, Uint8List>) _decodeBbBytes((String, Uint8List) args) {
  final (path, bytes) = args;
  if (bytes.length > BbFormat.maxFileBytes) {
    throw const BookExchangeException('文件超过 100MB 上限，不是有效的绘本文件');
  }

  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw BookExchangeException('「${_baseName(path)}」不是有效的 .bb 绘本文件');
  }

  // 先查中央目录里的声明尺寸（此阶段懒解压，零成本），拦截 zip 炸弹。
  var declaredTotal = 0;
  for (final entry in archive) {
    declaredTotal += entry.size;
    if (declaredTotal > BbFormat.maxTotalUncompressedBytes) {
      throw const BookExchangeException('文件内容超出大小上限，已拒绝导入');
    }
  }

  final mimetypeEntry = archive.find(BbFormat.mimetypeEntry);
  final mimetype =
      mimetypeEntry == null
          ? ''
          : utf8.decode(mimetypeEntry.content, allowMalformed: true).trim();
  if (mimetype != BbFormat.mimeType) {
    throw const BookExchangeException(
      '文件格式不匹配：这不是 BookBuddy 导出的 .bb 绘本文件',
    );
  }

  final manifestEntry = archive.find(BbFormat.manifestEntry);
  if (manifestEntry == null) {
    throw const BookExchangeException('文件缺少 manifest.json，可能已损坏');
  }
  Map<String, dynamic> manifest;
  try {
    manifest = jsonDecode(utf8.decode(manifestEntry.content))
        as Map<String, dynamic>;
  } catch (_) {
    throw const BookExchangeException('manifest.json 解析失败，文件可能已损坏');
  }
  if (manifest['format'] != 'bookbuddy-book') {
    throw const BookExchangeException('文件格式标识不正确，不是 .bb 绘本文件');
  }
  final formatVersion = manifest['formatVersion'];
  if (formatVersion is! int || formatVersion < 1) {
    throw const BookExchangeException('文件格式版本异常，无法导入');
  }
  if (formatVersion > BbFormat.formatVersion) {
    throw const BookExchangeException(
      '该文件由更新版本的 BookBuddy 导出，请先升级 App 后再导入',
    );
  }

  final bookEntry = archive.find(BbFormat.bookEntry);
  if (bookEntry == null) {
    throw const BookExchangeException('文件缺少 book.json，可能已损坏');
  }
  final PictureBook book;
  try {
    book = PictureBook.fromJson(
      jsonDecode(utf8.decode(bookEntry.content)) as Map<String, dynamic>,
    );
  } catch (_) {
    throw const BookExchangeException('绘本数据解析失败，文件可能已损坏');
  }
  if (book.id.isEmpty) {
    throw const BookExchangeException('绘本数据缺少 id，无法导入');
  }

  final audioFiles = <int, Uint8List>{};
  for (final entry in archive) {
    if (!entry.isFile || entry.isDirectory) continue;
    final name = entry.name;
    if (!name.startsWith(BbFormat.audioDirPrefix) ||
        !name.endsWith('.mp3')) {
      continue;
    }
    final indexPart = name.substring(
      BbFormat.audioDirPrefix.length,
      name.length - '.mp3'.length,
    );
    if (!indexPart.startsWith('audio_p')) continue;
    final pageIndex = int.tryParse(indexPart.substring('audio_p'.length));
    if (pageIndex != null && entry.size > 0) {
      audioFiles[pageIndex] = entry.content;
    }
  }

  return (book, audioFiles);
}

class _PersistPayload {
  const _PersistPayload(this.booksDirPath, this.audioDirPath, this.book,
      this.audioFiles);

  final String booksDirPath;
  final String audioDirPath;
  final PictureBook book;
  final Map<int, Uint8List> audioFiles;
}

/// 在后台 isolate 里运行：把导入的书和音频落盘。
///
/// 书沿用 BookStorageService 的保存协议（.tmp → 旧文件换名为 .bak → 换名），
/// 音频按页写入 audioDir/{bookId}/。所有解析校验在此之前已通过。
void _persistImport(_PersistPayload payload) {
  final file = File('${payload.booksDirPath}/${payload.book.id}.json');
  final temp = File('${file.path}.tmp');
  temp.writeAsBytesSync(
    JsonUtf8Encoder().convert(payload.book.toJson()),
    flush: true,
  );

  var movedOriginal = false;
  final backup = File('${file.path}.bak');
  try {
    if (file.existsSync()) {
      if (backup.existsSync()) backup.deleteSync();
      file.renameSync(backup.path);
      movedOriginal = true;
    }
    temp.renameSync(file.path);
  } catch (_) {
    if (movedOriginal && !file.existsSync() && backup.existsSync()) {
      backup.copySync(file.path);
    }
    rethrow;
  } finally {
    if (temp.existsSync()) temp.deleteSync();
  }

  if (payload.audioFiles.isNotEmpty) {
    final audioDir = Directory(
      '${payload.audioDirPath}/${payload.book.id}',
    );
    audioDir.createSync(recursive: true);
    payload.audioFiles.forEach((pageIndex, bytes) {
      final target = File('${audioDir.path}/audio_p$pageIndex.mp3');
      final tmp = File('${target.path}.tmp');
      tmp.writeAsBytesSync(bytes, flush: true);
      tmp.renameSync(target.path);
    });
  }
}

/// 导入/导出绘本专用格式 .bb。
class BookExchangeService {
  BookExchangeService({Directory? booksDirectory, Directory? audioDirectory})
    : _booksDirectory = booksDirectory,
      _audioDirectory = audioDirectory;

  final Directory? _booksDirectory;
  final Directory? _audioDirectory;

  Future<Directory> _resolveBooksDirectory() async {
    if (_booksDirectory != null) return _booksDirectory;
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/bookbuddy_books');
  }

  Future<Directory> _resolveAudioDirectory() async {
    if (_audioDirectory != null) return _audioDirectory;
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/bookbuddy_audio');
  }

  Future<String> _audioPathFor(String bookId, int pageIndex) async {
    final dir = await _resolveAudioDirectory();
    return '${dir.path}/$bookId/audio_p$pageIndex.mp3';
  }

  /// 导出一本书为 .bb，写到 [outputPath]，返回写入的字节数。
  ///
  /// [book] 需为整本书（书架只有摘要，调用方需先 loadBook）。现存音频按页
  /// 一起打包；没有音频的页面跳过（导入后可重新合成）。
  Future<int> exportBookToFile(
    PictureBook book,
    String outputPath, {
    String appVersion = '',
  }) async {
    final audioFiles = <int, Uint8List>{};
    for (var i = 0; i < book.pages.length; i++) {
      final file = File(await _audioPathFor(book.id, i));
      if (await file.exists() && await file.length() > 0) {
        audioFiles[i] = await file.readAsBytes();
      }
    }

    final bytes = await compute(
      _encodeBbBytes,
      _ExportPayload(book, audioFiles, appVersion),
    );
    final tmp = File('$outputPath.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await tmp.rename(outputPath);
    } catch (_) {
      // 目标已存在时 rename 可能失败（平台差异），退回直接覆盖写。
      await File(outputPath).writeAsBytes(bytes, flush: true);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
    return bytes.length;
  }

  /// 从 .bb 文件导入一本书。本地已有同 id 绘本时存为「（导入）」副本。
  Future<BookImportResult> importBookFromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final (book, audioFiles) = await compute(_decodeBbBytes, (path, bytes));

    final booksDir = await _resolveBooksDirectory();
    final idExists =
        await File('${booksDir.path}/${book.id}.json').exists() ||
        await File('${booksDir.path}/${book.id}.json.bak').exists();

    var finalBook = book;
    var isDuplicateCopy = false;
    if (idExists) {
      isDuplicateCopy = true;
      finalBook = _asDuplicateCopy(book);
    }

    final audioDir = await _resolveAudioDirectory();
    await compute(
      _persistImport,
      _PersistPayload(booksDir.path, audioDir.path, finalBook, audioFiles),
    );

    BookStorageService.booksChangedNotifier.value++;
    return BookImportResult(book: finalBook, isDuplicateCopy: isDuplicateCopy);
  }

  PictureBook _asDuplicateCopy(PictureBook book) {
    // 书内角色是快照、音频/图片路径阅读器会自愈，直接沿用即可；只换 id 和标题。
    return PictureBook(
      id: const Uuid().v4(),
      title: '${book.title}（导入）',
      styleId: book.styleId,
      styleName: book.styleName,
      pages: book.pages,
      createdAt: book.createdAt,
      characters: book.characters,
      protagonistRefImage: book.protagonistRefImage,
      characterCardIds: book.characterCardIds,
    );
  }
}

String _baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isEmpty ? path : segments.last;
}
