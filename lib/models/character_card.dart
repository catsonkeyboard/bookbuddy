import 'package:uuid/uuid.dart';

import 'book.dart';

/// 每本绘本最多可选的角色卡数量。每页请求会携带全部出场角色的定妆图，
/// 超过 3 张会挤占场景描述并增加身份串染概率。实测稳定后可调。
const int kMaxCharacterCardsPerBook = 3;

/// 物件角色没有服装时追加到外貌末尾，避免现有提示词把非动物角色当人类穿衣。
const String kObjectAppearanceSuffix = '（非生物物件拟人化角色，不添加人类服饰和鞋靴）';

enum CharacterCardSource { manual, photo }

/// 人类 / 动物 / 非生物物件（玩具、石头等拟人角色）
enum CharacterKind { human, animal, object }

/// 跨绘本复用的角色卡。图片一律以相对角色库根目录的文件路径引用，不存 base64。
class CharacterCard {
  final String id;
  CharacterCardSource source;
  String name;
  CharacterKind kind;
  String species;
  String appearance;
  String defaultOutfit;
  String personality;
  String catchphrase;

  /// styleId -> 相对路径，例如 {'watercolor': 'card_ab12cd34/anchor_watercolor.png'}
  Map<String, String> anchorImagePaths;

  /// 原始照片相对路径，仅 photo 来源。
  String? photoPath;
  final DateTime createdAt;
  DateTime? lastUsedAt;

  CharacterCard({
    required this.id,
    this.source = CharacterCardSource.manual,
    required this.name,
    this.kind = CharacterKind.animal,
    this.species = '',
    required this.appearance,
    this.defaultOutfit = '',
    this.personality = '',
    this.catchphrase = '',
    Map<String, String>? anchorImagePaths,
    this.photoPath,
    DateTime? createdAt,
    this.lastUsedAt,
  })  : anchorImagePaths = anchorImagePaths ?? {},
        createdAt = createdAt ?? DateTime.now();

  static String newId() =>
      'card_${const Uuid().v4().replaceAll('-', '').substring(0, 8)}';

  bool get isAnimal => kind == CharacterKind.animal;

  /// 投影为书内快照。定妆图 base64 由调用方按画风读文件后传入。
  /// 空服装按类型投影为明确描述，避免提示词里出现「默认服装：。」。
  BookCharacter toBookCharacter({String? referenceImageBase64}) {
    var projectedAppearance = appearance;
    if (kind == CharacterKind.object && defaultOutfit.trim().isEmpty) {
      projectedAppearance = '$appearance$kObjectAppearanceSuffix';
    }
    final projectedOutfit = defaultOutfit.trim().isEmpty
        ? _defaultOutfitFor(kind)
        : defaultOutfit;
    return BookCharacter(
      id: id,
      name: name,
      species: species,
      isAnimal: isAnimal,
      appearance: projectedAppearance,
      defaultOutfit: projectedOutfit,
      referenceImageBase64: referenceImageBase64,
    );
  }

  static String _defaultOutfitFor(CharacterKind kind) => switch (kind) {
        CharacterKind.animal => '自然毛皮或羽毛，不穿人类服饰',
        CharacterKind.object => '无服装，保持物件本来的外观',
        CharacterKind.human => '简洁的日常服装',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'name': name,
        'kind': kind.name,
        'species': species,
        'appearance': appearance,
        'defaultOutfit': defaultOutfit,
        'personality': personality,
        'catchphrase': catchphrase,
        'anchorImagePaths': anchorImagePaths,
        'photoPath': photoPath,
        'createdAt': createdAt.toIso8601String(),
        'lastUsedAt': lastUsedAt?.toIso8601String(),
      };

  factory CharacterCard.fromJson(Map<String, dynamic> json) => CharacterCard(
        id: json['id']?.toString() ?? '',
        source: CharacterCardSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => CharacterCardSource.manual,
        ),
        name: json['name']?.toString() ?? '',
        kind: CharacterKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => CharacterKind.human,
        ),
        species: json['species']?.toString() ?? '',
        appearance: json['appearance']?.toString() ?? '',
        defaultOutfit: json['defaultOutfit']?.toString() ?? '',
        personality: json['personality']?.toString() ?? '',
        catchphrase: json['catchphrase']?.toString() ?? '',
        anchorImagePaths: (json['anchorImagePaths'] as Map? ?? {}).map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ),
        photoPath: json['photoPath'] as String?,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        lastUsedAt: DateTime.tryParse(json['lastUsedAt']?.toString() ?? ''),
      );
}
