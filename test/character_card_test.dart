import 'package:bookbuddy/models/character_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CharacterCard sample() => CharacterCard(
        id: 'card_ab12cd34',
        source: CharacterCardSource.photo,
        name: '豆豆',
        kind: CharacterKind.animal,
        species: '毛绒恐龙',
        appearance: '绿色毛绒身体，肚皮米白，圆圆的黑眼睛',
        defaultOutfit: '红色小围巾',
        personality: '胆子大、爱冒险',
        catchphrase: '冲啊！',
        anchorImagePaths: {'watercolor': 'card_ab12cd34/anchor_watercolor.png'},
        photoPath: 'card_ab12cd34/photo.jpg',
        createdAt: DateTime.utc(2026, 9, 28),
        lastUsedAt: DateTime.utc(2026, 9, 29),
      );

  test('toJson/fromJson 往返保留所有字段', () {
    final restored = CharacterCard.fromJson(sample().toJson());
    expect(restored.id, 'card_ab12cd34');
    expect(restored.source, CharacterCardSource.photo);
    expect(restored.name, '豆豆');
    expect(restored.kind, CharacterKind.animal);
    expect(restored.species, '毛绒恐龙');
    expect(restored.appearance, contains('绿色毛绒'));
    expect(restored.defaultOutfit, '红色小围巾');
    expect(restored.personality, '胆子大、爱冒险');
    expect(restored.catchphrase, '冲啊！');
    expect(
      restored.anchorImagePaths['watercolor'],
      'card_ab12cd34/anchor_watercolor.png',
    );
    expect(restored.photoPath, 'card_ab12cd34/photo.jpg');
    expect(restored.createdAt, DateTime.utc(2026, 9, 28));
    expect(restored.lastUsedAt, DateTime.utc(2026, 9, 29));
  });

  test('缺失或未知字段回退到默认值', () {
    final card = CharacterCard.fromJson({
      'id': 'card_x',
      'name': '小石头',
      'appearance': '灰色',
      'kind': 'alien',
      'source': 'dream',
    });
    expect(card.kind, CharacterKind.human);
    expect(card.source, CharacterCardSource.manual);
    expect(card.species, '');
    expect(card.defaultOutfit, '');
    expect(card.personality, '');
    expect(card.catchphrase, '');
    expect(card.anchorImagePaths, isEmpty);
    expect(card.photoPath, isNull);
    expect(card.lastUsedAt, isNull);
    expect(card.createdAt, isA<DateTime>());
  });

  test('toBookCharacter 保留 id 并映射 isAnimal', () {
    final book = sample().toBookCharacter(referenceImageBase64: 'img');
    expect(book.id, 'card_ab12cd34');
    expect(book.name, '豆豆');
    expect(book.species, '毛绒恐龙');
    expect(book.isAnimal, isTrue);
    expect(book.appearance, '绿色毛绒身体，肚皮米白，圆圆的黑眼睛');
    expect(book.defaultOutfit, '红色小围巾');
    expect(book.referenceImageBase64, 'img');
  });

  test('物件角色无服装时外貌追加拟人后缀，有服装时不追加', () {
    final stone = CharacterCard(
      id: 'card_stone',
      name: '小满',
      kind: CharacterKind.object,
      species: '石头',
      appearance: '圆润的灰色鹅卵石，脸上有两个小坑当眼睛',
    );
    final book = stone.toBookCharacter();
    expect(book.isAnimal, isFalse);
    expect(book.appearance, endsWith(kObjectAppearanceSuffix));
    expect(book.referenceImageBase64, isNull);

    stone.defaultOutfit = '蓝色小帽';
    expect(
      stone.toBookCharacter().appearance,
      isNot(contains(kObjectAppearanceSuffix)),
    );
  });

  test('人类角色无服装时不追加物件后缀', () {
    final human = CharacterCard(
      id: 'card_h',
      name: '小明',
      kind: CharacterKind.human,
      appearance: '短黑发男孩',
    );
    expect(
      human.toBookCharacter().appearance,
      isNot(contains(kObjectAppearanceSuffix)),
    );
  });

  test('newId 带 card_ 前缀、长度 13 且唯一', () {
    final a = CharacterCard.newId();
    final b = CharacterCard.newId();
    expect(a, startsWith('card_'));
    expect(a.length, 13);
    expect(a, isNot(b));
  });

  test('每本绘本角色卡上限为 3', () {
    expect(kMaxCharacterCardsPerBook, 3);
  });
}
