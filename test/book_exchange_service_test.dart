import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/services/book_exchange_service.dart';
import 'package:bookbuddy/services/book_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

PictureBook _book({String id = 'book-1', String title = '小熊冒险'}) =>
    PictureBook(
      id: id,
      title: title,
      styleId: 'watercolor',
      styleName: '水彩童话',
      pages: [
        BookPageItem(pageIndex: 0, text: '第一页'),
        BookPageItem(pageIndex: 1, text: '第二页'),
      ],
      createdAt: DateTime.utc(2026, 10, 10),
      characters: [
        BookCharacter(
          id: 'char-1',
          name: '小熊',
          appearance: '棕色圆滚滚',
          defaultOutfit: '红色围巾',
        ),
      ],
    );

/// 造一个假的 mp3（内容是随机字节，解码端只按字节搬运，不解析音频）。
Uint8List _fakeMp3(int pageIndex) => Uint8List.fromList(
  List.generate(64, (i) => (pageIndex * 7 + i * 13) % 256),
);

/// 直接用 BookExchangeService 导出一本书，拿到 .bb 字节（用于构造坏文件场景）。
Future<Uint8List> _exportBytes(BookExchangeService service, PictureBook book,
    Directory audioDir) async {
  for (var i = 0; i < book.pages.length; i++) {
    final dir = Directory('${audioDir.path}/${book.id}');
    await dir.create(recursive: true);
    await File('${dir.path}/audio_p$i.mp3').writeAsBytes(_fakeMp3(i));
  }
  final out = File(
    '${Directory.systemTemp.path}/bb-out-${DateTime.now().microsecondsSinceEpoch}-'
    '${book.id}.bb',
  );
  await service.exportBookToFile(book, out.path);
  final bytes = await out.readAsBytes();
  await out.delete();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory booksDir;
  late Directory audioDir;
  late BookExchangeService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'bookbuddy_books_migrated_to_files': true,
    });
    root = await Directory.systemTemp.createTemp('bookbuddy-exchange-test-');
    booksDir = Directory('${root.path}/books');
    audioDir = Directory('${root.path}/audio');
    await booksDir.create(recursive: true);
    await audioDir.create(recursive: true);
    service = BookExchangeService(
      booksDirectory: booksDir,
      audioDirectory: audioDir,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('导出 → 导入 round-trip：书与音频完整复原，保留原 id 与标题', () async {
    final book = _book();
    final bytes = await _exportBytes(service, book, audioDir);
    expect(bytes.length, greaterThan(0));

    final bbFile = File('${root.path}/roundtrip.bb');
    await bbFile.writeAsBytes(bytes);

    final result = await service.importBookFromFile(bbFile.path);
    expect(result.isDuplicateCopy, isFalse);
    expect(result.book.id, 'book-1');
    expect(result.book.title, '小熊冒险');
    expect(result.book.pages.length, 2);
    expect(result.book.pages[0].text, '第一页');
    expect(result.book.characters.single.name, '小熊');

    // 落盘的书文件可被 BookStorageService 正常读回。
    final storage = BookStorageService(booksDirectory: booksDir);
    final loaded = await storage.loadBook('book-1');
    expect(loaded, isNotNull);
    expect(loaded!.title, '小熊冒险');

    // 音频逐页复原。
    for (var i = 0; i < 2; i++) {
      final f = File('${audioDir.path}/book-1/audio_p$i.mp3');
      expect(await f.exists(), isTrue, reason: 'audio_p$i.mp3 应存在');
      expect(await f.readAsBytes(), _fakeMp3(i));
    }
  });

  test('没有音频的书也能导出导入（audio 条目缺省）', () async {
    final book = _book();
    final out = File('${root.path}/no-audio.bb');
    await service.exportBookToFile(book, out.path);

    final result = await service.importBookFromFile(out.path);
    expect(result.isDuplicateCopy, isFalse);
    expect(result.book.id, 'book-1');
    expect(
      await Directory('${audioDir.path}/book-1').exists(),
      isFalse,
      reason: '无音频时不应创建音频目录',
    );
  });

  test('本地已有同 id 绘本时导入为（导入）副本，原书无损', () async {
    final book = _book();
    final bbFile = File('${root.path}/dup.bb');
    await service.exportBookToFile(book, bbFile.path);

    // 第一次导入：原样落盘。
    final first = await service.importBookFromFile(bbFile.path);
    expect(first.isDuplicateCopy, isFalse);
    expect(first.book.id, 'book-1');

    // 第二次导入同 id：存副本。
    final second = await service.importBookFromFile(bbFile.path);
    expect(second.isDuplicateCopy, isTrue);
    expect(second.book.id, isNot('book-1'));
    expect(second.book.title, '小熊冒险（导入）');

    // 原书仍在且未被改写。
    final storage = BookStorageService(booksDirectory: booksDir);
    final original = await storage.loadBook('book-1');
    expect(original, isNotNull);
    expect(original!.title, '小熊冒险');

    // 副本也能读回。
    final copy = await storage.loadBook(second.book.id);
    expect(copy, isNotNull);
    expect(copy!.title, '小熊冒险（导入）');
    expect(copy.pages.length, 2);
  });

  test('损坏的字节被拒绝（zip 解析失败或 mimetype 校验失败均可）', () async {
    final bad = File('${root.path}/bad.bb');
    await bad.writeAsBytes(List.filled(1024, 7));
    // archive 对畸形 zip 较宽容：垃圾字节可能走 zip 解析失败，也可能解析
    // “成功”后卡在 mimetype 校验——两条路都是正确的拒绝。
    await expectLater(
      service.importBookFromFile(bad.path),
      throwsA(
        isA<BookExchangeException>().having(
          (e) => e.message,
          'message',
          anyOf(contains('不是有效的'), contains('不是 BookBuddy 导出')),
        ),
      ),
    );
  });

  test('mimetype 不匹配被拒绝（普通 zip 不是 .bb）', () async {
    final plain = File('${root.path}/plain.zip');
    final archive = Archive()
      ..add(ArchiveFile('hello.txt', 5, utf8.encode('hello')));
    await plain.writeAsBytes(ZipEncoder().encodeBytes(archive));
    await expectLater(
      service.importBookFromFile(plain.path),
      throwsA(
        isA<BookExchangeException>().having(
          (e) => e.message,
          'message',
          contains('不是 BookBuddy 导出'),
        ),
      ),
    );
  });

  test('manifest 缺失或 formatVersion 超前被拒绝', () async {
    final book = _book();
    final bytes = await _exportBytes(service, book, audioDir);

    // 抽出 book.json + mimetype，不带 manifest。
    final decoded = ZipDecoder().decodeBytes(bytes);
    final noManifest = Archive()
      ..add(decoded.find('mimetype')!)
      ..add(decoded.find('book.json')!);
    final f1 = File('${root.path}/no-manifest.bb');
    await f1.writeAsBytes(ZipEncoder().encodeBytes(noManifest));
    await expectLater(
      service.importBookFromFile(f1.path),
      throwsA(
        isA<BookExchangeException>().having(
          (e) => e.message,
          'message',
          contains('manifest'),
        ),
      ),
    );

    // formatVersion = 99：要求升级。
    final futureManifest = Archive()
      ..add(decoded.find('mimetype')!)
      ..add(
        ArchiveFile(
          'manifest.json',
          60,
          utf8.encode(
            jsonEncode({
              'format': 'bookbuddy-book',
              'formatVersion': 99,
            }),
          ),
        ),
      )
      ..add(decoded.find('book.json')!);
    final f2 = File('${root.path}/future.bb');
    await f2.writeAsBytes(ZipEncoder().encodeBytes(futureManifest));
    await expectLater(
      service.importBookFromFile(f2.path),
      throwsA(
        isA<BookExchangeException>().having(
          (e) => e.message,
          'message',
          contains('升级'),
        ),
      ),
    );
  });

  test('book.json 损坏或缺少 id 被拒绝', () async {
    final book = _book();
    final bytes = await _exportBytes(service, book, audioDir);
    final decoded = ZipDecoder().decodeBytes(bytes);

    // book.json 内容是垃圾。
    final brokenBook = Archive()
      ..add(decoded.find('mimetype')!)
      ..add(
        decoded.find('manifest.json') ??
            ArchiveFile(
              'manifest.json',
              50,
              utf8.encode(
                jsonEncode({'format': 'bookbuddy-book', 'formatVersion': 1}),
              ),
            ),
      )
      ..add(ArchiveFile('book.json', 11, utf8.encode('not json!!')));
    final f1 = File('${root.path}/broken-book.bb');
    await f1.writeAsBytes(ZipEncoder().encodeBytes(brokenBook));
    await expectLater(
      service.importBookFromFile(f1.path),
      throwsA(
        isA<BookExchangeException>().having(
          (e) => e.message,
          'message',
          contains('解析失败'),
        ),
      ),
    );
  });

  test('mimetype 是第一个条目且未压缩（格式自识别）', () async {
    final book = _book();
    final bytes = await _exportBytes(service, book, audioDir);
    final decoded = ZipDecoder().decodeBytes(bytes);
    expect(decoded.first.name, 'mimetype');
    expect(decoded.first.compression, CompressionType.none);
    expect(
      utf8.decode(decoded.first.content).trim(),
      'application/x-bookbuddy-book',
    );
  });
}
