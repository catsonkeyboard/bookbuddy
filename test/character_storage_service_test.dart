import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

CharacterCard _card(
  String id,
  String name, {
  DateTime? createdAt,
  DateTime? lastUsedAt,
}) =>
    CharacterCard(
      id: id,
      name: name,
      appearance: '外貌 $name',
      createdAt: createdAt ?? DateTime.utc(2026, 9, 28),
      lastUsedAt: lastUsedAt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late CharacterStorageService storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bookbuddy-characters-test-');
    storage = CharacterStorageService(directory: dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('保存后可读取，重复保存同 id 视为更新', () async {
    await storage.saveCard(_card('card_a', '豆豆'));
    await storage.saveCard(_card('card_a', '豆豆二号'));
    final cards = await storage.loadCards();
    expect(cards.single.name, '豆豆二号');
  });

  test('空 id 拒绝保存', () async {
    expect(() => storage.saveCard(_card('', '无名')), throwsArgumentError);
  });

  test('按最近使用时间倒序，没有则按创建时间', () async {
    await storage.saveCard(
      _card('card_old', '旧', createdAt: DateTime.utc(2026, 1, 1)),
    );
    await storage.saveCard(
      _card('card_new', '新', createdAt: DateTime.utc(2026, 6, 1)),
    );
    await storage.saveCard(
      _card(
        'card_used',
        '常用',
        createdAt: DateTime.utc(2026, 2, 1),
        lastUsedAt: DateTime.utc(2026, 9, 1),
      ),
    );
    final names = (await storage.loadCards()).map((c) => c.name).toList();
    expect(names, ['常用', '新', '旧']);
  });

  test('主文件损坏时从备份恢复，之后写入不丢数据', () async {
    await storage.saveCard(_card('card_a', '第一版'));
    await storage.saveCard(_card('card_a', '第二版'));
    final main = File('${dir.path}/cards.json');
    final backup = File('${main.path}.bak');
    expect(await backup.exists(), isTrue);
    expect(
      (jsonDecode(await backup.readAsString()) as List).single['name'],
      '第一版',
    );

    await main.writeAsString('{broken', flush: true);
    expect((await storage.loadCards()).single.name, '第一版');

    await storage.saveCard(_card('card_b', '新卡'));
    final names = (await storage.loadCards()).map((c) => c.name).toSet();
    expect(names, {'第一版', '新卡'});
    expect(
      dir.listSync().any((e) => e.path.contains('cards.json.corrupt.')),
      isTrue,
    );
  });

  test('主文件与备份都不存在时返回空列表', () async {
    expect(await storage.loadCards(), isEmpty);
  });

  test('并发保存串行化，两张卡都保留', () async {
    await Future.wait([
      storage.saveCard(_card('card_a', 'A')),
      storage.saveCard(_card('card_b', 'B')),
    ]);
    expect(
      (await storage.loadCards()).map((c) => c.id).toSet(),
      {'card_a', 'card_b'},
    );
  });

  test('保存与删除触发 cardsChangedNotifier', () async {
    final before = CharacterStorageService.cardsChangedNotifier.value;
    await storage.saveCard(_card('card_a', '豆豆'));
    expect(CharacterStorageService.cardsChangedNotifier.value, before + 1);
    await storage.deleteCard('card_a');
    expect(CharacterStorageService.cardsChangedNotifier.value, before + 2);
    expect(await storage.loadCards(), isEmpty);
  });

  test('写入图片返回相对路径并可读回 base64', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final relative = await storage.writeImage('card_a', 'photo.jpg', bytes);
    expect(relative, 'card_a/photo.jpg');
    expect(await File('${dir.path}/card_a/photo.jpg').exists(), isTrue);
    expect(await storage.readImageBase64(relative), base64Encode(bytes));
    expect(await storage.readImageBase64('card_a/missing.jpg'), isNull);
    expect((await storage.imageFile(relative)).path, '${dir.path}/card_a/photo.jpg');
  });

  test('saveAnchor 按字节头选择扩展名并更新卡片映射', () async {
    await storage.saveCard(_card('card_a', '豆豆'));
    final png = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
    final jpg = base64Encode([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0]);

    final pngPath = await storage.saveAnchor('card_a', 'watercolor', png);
    final jpgPath = await storage.saveAnchor(
      'card_a',
      'anime',
      'data:image/jpeg;base64,$jpg',
    );
    expect(pngPath, 'card_a/anchor_watercolor.png');
    expect(jpgPath, 'card_a/anchor_anime.jpg');

    final card = (await storage.loadCards()).single;
    expect(card.anchorImagePaths, {
      'watercolor': 'card_a/anchor_watercolor.png',
      'anime': 'card_a/anchor_anime.jpg',
    });
    expect(await File('${dir.path}/card_a/anchor_anime.jpg').exists(), isTrue);
  });

  test('saveAnchor 同一画风换格式时删除旧文件', () async {
    await storage.saveCard(_card('card_a', '豆豆'));
    await storage.saveAnchor(
      'card_a',
      'watercolor',
      base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]),
    );
    await storage.saveAnchor(
      'card_a',
      'watercolor',
      base64Encode([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0]),
    );
    expect(
      await File('${dir.path}/card_a/anchor_watercolor.png').exists(),
      isFalse,
    );
    expect(
      await File('${dir.path}/card_a/anchor_watercolor.jpg').exists(),
      isTrue,
    );
    expect(
      (await storage.loadCards()).single.anchorImagePaths['watercolor'],
      'card_a/anchor_watercolor.jpg',
    );
  });

  test('saveAnchor 对不存在的卡片抛错且不留下文件', () async {
    await expectLater(
      storage.saveAnchor('card_missing', 'watercolor', base64Encode([1, 2])),
      throwsStateError,
    );
    expect(
      await File('${dir.path}/card_missing/anchor_watercolor.jpg').exists(),
      isFalse,
    );
  });

  test('clearAnchors 删除文件并清空映射', () async {
    await storage.saveCard(_card('card_a', '豆豆'));
    await storage.saveAnchor(
      'card_a',
      'watercolor',
      base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]),
    );
    await storage.clearAnchors('card_a');
    expect((await storage.loadCards()).single.anchorImagePaths, isEmpty);
    expect(
      await File('${dir.path}/card_a/anchor_watercolor.png').exists(),
      isFalse,
    );
  });

  test('删除卡片连带删除其目录', () async {
    await storage.saveCard(_card('card_a', '豆豆'));
    await storage.writeImage('card_a', 'photo.jpg', Uint8List.fromList([1]));
    await storage.deleteCard('card_a');
    expect(await storage.loadCards(), isEmpty);
    expect(await Directory('${dir.path}/card_a').exists(), isFalse);
  });

  test('含路径分隔符或 .. 的 id 被拒绝，不触碰文件系统', () async {
    final sibling = Directory('${dir.path}/../bookbuddy-sibling-${dir.uri.pathSegments.where((s) => s.isNotEmpty).last}')
      ..createSync(recursive: true);
    addTearDown(() {
      if (sibling.existsSync()) sibling.deleteSync(recursive: true);
    });
    final escaping = '../${sibling.uri.pathSegments.where((s) => s.isNotEmpty).last}';

    expect(() => storage.saveCard(_card(escaping, '越界')), throwsArgumentError);
    expect(() => storage.saveCard(_card('..', '越界')), throwsArgumentError);
    expect(() => storage.saveCard(_card('a/b', '越界')), throwsArgumentError);
    await expectLater(storage.deleteCard(escaping), throwsArgumentError);
    await expectLater(
      storage.writeImage(escaping, 'photo.jpg', Uint8List.fromList([1])),
      throwsArgumentError,
    );
    expect(sibling.existsSync(), isTrue);
  });

  test('imageFile 拒绝逃出角色库目录的相对路径', () async {
    await expectLater(storage.imageFile('../x.png'), throwsArgumentError);
    await expectLater(storage.imageFile('card_a/../../x.png'), throwsArgumentError);
    await expectLater(storage.imageFile('/etc/passwd'), throwsArgumentError);
    expect(await storage.readImageBase64('card_a/photo.jpg'), isNull);
  });

  test('cards.json 里 id 非法的条目在读取时被丢弃', () async {
    await storage.saveCard(_card('card_ok', '正常'));
    final file = File('${dir.path}/cards.json');
    final list = jsonDecode(await file.readAsString()) as List;
    list.add({'id': '../evil', 'name': '坏', 'appearance': 'x'});
    await file.writeAsString(jsonEncode(list), flush: true);
    final cards = await storage.loadCards();
    expect(cards.map((c) => c.id), ['card_ok']);
  });

  test('touchLastUsed 只更新指定卡片的 lastUsedAt 并影响排序', () async {
    await storage.saveCard(
      _card('card_a', '豆豆', createdAt: DateTime.utc(2026, 9, 1)),
    );
    await storage.saveCard(
      _card('card_b', '小满', createdAt: DateTime.utc(2026, 9, 2)),
    );
    final before = CharacterStorageService.cardsChangedNotifier.value;

    await storage.touchLastUsed(['card_a', 'card_missing', '../evil']);

    final cards = await storage.loadCards();
    expect(cards.first.id, 'card_a');
    expect(cards.first.lastUsedAt, isNotNull);
    expect(cards.first.name, '豆豆');
    expect(cards.last.lastUsedAt, isNull);
    expect(CharacterStorageService.cardsChangedNotifier.value, before + 1);
  });

  test('touchLastUsed 空集合不写盘不通知', () async {
    await storage.saveCard(_card('card_a', '豆豆'));
    final before = CharacterStorageService.cardsChangedNotifier.value;
    await storage.touchLastUsed(const []);
    expect(CharacterStorageService.cardsChangedNotifier.value, before);
    expect((await storage.loadCards()).single.lastUsedAt, isNull);
  });

  test('deleteImage 删除卡片目录里的图片，文件不存在时不报错', () async {
    final relative =
        await storage.writeImage('card_a', 'photo.jpg', Uint8List.fromList([1, 2]));
    expect(await File('${dir.path}/card_a/photo.jpg').exists(), isTrue);
    await storage.deleteImage(relative);
    expect(await File('${dir.path}/card_a/photo.jpg').exists(), isFalse);
    await storage.deleteImage(relative);
  });

  test('deleteImage 拒绝逃出角色库目录的路径', () async {
    await expectLater(storage.deleteImage('../x.jpg'), throwsArgumentError);
  });
}
