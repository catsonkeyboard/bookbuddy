import 'dart:convert';
import 'dart:io';

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
}
