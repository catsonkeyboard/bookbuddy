class PictureBook {
  final String id;
  final String title;
  final String styleId;
  final String styleName;
  final List<BookPageItem> pages;
  final DateTime createdAt;
  final List<BookCharacter> characters;
  String? protagonistRefImage; // 主角定妆照参考图（Base64），全书所有页面及单独重绘共用，锁定角色外貌
  List<String> characterCardIds; // 本书使用的角色卡 id（书内角色仍是快照，卡片编辑不回溯）

  PictureBook({
    required this.id,
    required this.title,
    required this.styleId,
    required this.styleName,
    required this.pages,
    required this.createdAt,
    this.characters = const [],
    this.protagonistRefImage,
    List<String>? characterCardIds,
  }) : characterCardIds = characterCardIds ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'styleId': styleId,
    'styleName': styleName,
    'pages': pages.map((p) => p.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'characters': characters.map((c) => c.toJson()).toList(),
    'protagonistRefImage': protagonistRefImage,
    'characterCardIds': characterCardIds,
  };

  factory PictureBook.fromJson(Map<String, dynamic> json) => PictureBook(
    id: json['id'] ?? '',
    title: json['title'] ?? '未命名绘本',
    styleId: json['styleId'] ?? 'watercolor',
    styleName: json['styleName'] ?? '水彩童话',
    pages: (json['pages'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((p) => BookPageItem.fromJson(Map<String, dynamic>.from(p)))
        .toList(),
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    // jsonDecode 出的元素是 _Map<dynamic,dynamic>，直接强转会抛 TypeError，先统一转成 Map<String, dynamic>
    characters: (json['characters'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((c) => BookCharacter.fromJson(Map<String, dynamic>.from(c)))
        .toList(),
    protagonistRefImage: json['protagonistRefImage'],
    characterCardIds: (json['characterCardIds'] as List<dynamic>? ?? [])
        .map((id) => id.toString())
        .toList(),
  );

  /// 已成功绘制的插画数量
  int get completedIllustrationCount => pages
      .where(
        (p) =>
            p.needIllustration &&
            p.imageBase64 != null &&
            p.imageBase64!.isNotEmpty,
      )
      .length;

  /// 预期需要绘制的总插画数量
  int get targetIllustrationCount =>
      pages.where((p) => p.needIllustration).length;

  /// 是否存在待绘制或未完成/失败的插画
  bool get hasUnfinishedIllustrations =>
      targetIllustrationCount > 0 &&
      completedIllustrationCount < targetIllustrationCount;

  /// 尚待绘制的页面列表
  List<BookPageItem> get pendingIllustrationPages => pages
      .where(
        (p) =>
            p.needIllustration &&
            (p.imageBase64 == null || p.imageBase64!.isEmpty),
      )
      .toList();
}

/// 书架列表展示一本绘本所需的全部信息，不带任何插画数据。
///
/// 整本 [PictureBook] 内嵌每页插画的 base64，一本十几 MB；书架只拿摘要，
/// 打开某一本时再单独加载整本。
class BookSummary {
  final String id;
  final String title;
  final String styleName;
  final DateTime createdAt;
  final int pageCount;
  final bool usesCharacterCards;
  final int completedIllustrationCount;
  final int targetIllustrationCount;
  final bool hasUnfinishedIllustrations;

  BookSummary.of(PictureBook book)
    : id = book.id,
      title = book.title,
      styleName = book.styleName,
      createdAt = book.createdAt,
      pageCount = book.pages.length,
      usesCharacterCards = book.characterCardIds.isNotEmpty,
      completedIllustrationCount = book.completedIllustrationCount,
      targetIllustrationCount = book.targetIllustrationCount,
      hasUnfinishedIllustrations = book.hasUnfinishedIllustrations;
}

/// 全书共用的角色设定。换装仅由页面的 outfitOverrides 明确指定。
class BookCharacter {
  final String id;
  String name;
  String species;
  bool isAnimal;
  String appearance;
  String defaultOutfit;
  String? referenceImageBase64;

  BookCharacter({
    required this.id,
    required this.name,
    this.species = '',
    this.isAnimal = false,
    required this.appearance,
    required this.defaultOutfit,
    this.referenceImageBase64,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'species': species,
    'isAnimal': isAnimal,
    'appearance': appearance,
    'defaultOutfit': defaultOutfit,
    'referenceImageBase64': referenceImageBase64,
  };

  factory BookCharacter.fromJson(Map<String, dynamic> json) => BookCharacter(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    species: json['species']?.toString() ?? '',
    isAnimal: json['isAnimal'] == true,
    appearance: json['appearance']?.toString() ?? '',
    defaultOutfit: json['defaultOutfit']?.toString() ?? '',
    referenceImageBase64: json['referenceImageBase64'] as String?,
  );
}

class BookPageItem {
  final int pageIndex;
  String text;
  String sceneAction;
  String sceneEmotion;
  String sceneComposition;
  List<String> characterIds;
  Map<String, String> outfitOverrides;
  String? rawPrompt; // 原生图提示词
  String? imageBase64;
  String? imagePath;
  bool isPlaceholder;
  String? customInstruction;
  bool needIllustration; // 是否生成插画
  String? generationError; // 生图失败原因（如被安全策略拦截）
  String? imageModelUsed;
  String? imageProviderUsed;
  bool imageReferenceApplied;
  String? audioPath; // 本地朗读音频路径 (.mp3)
  String? audioError; // 语音生成失败原因

  BookPageItem({
    required this.pageIndex,
    required this.text,
    this.sceneAction = '',
    this.sceneEmotion = '',
    this.sceneComposition = '',
    this.characterIds = const [],
    this.outfitOverrides = const {},
    this.rawPrompt,
    this.imageBase64,
    this.imagePath,
    this.isPlaceholder = false,
    this.customInstruction,
    this.needIllustration = true,
    this.generationError,
    this.imageModelUsed,
    this.imageProviderUsed,
    this.imageReferenceApplied = false,
    this.audioPath,
    this.audioError,
  });

  Map<String, dynamic> toJson() => {
    'pageIndex': pageIndex,
    'text': text,
    'sceneAction': sceneAction,
    'sceneEmotion': sceneEmotion,
    'sceneComposition': sceneComposition,
    'characterIds': characterIds,
    'outfitOverrides': outfitOverrides,
    'rawPrompt': rawPrompt,
    'imageBase64': imageBase64,
    'imagePath': imagePath,
    'isPlaceholder': isPlaceholder,
    'customInstruction': customInstruction,
    'needIllustration': needIllustration,
    'generationError': generationError,
    'imageModelUsed': imageModelUsed,
    'imageProviderUsed': imageProviderUsed,
    'imageReferenceApplied': imageReferenceApplied,
    'audioPath': audioPath,
    'audioError': audioError,
  };

  factory BookPageItem.fromJson(Map<String, dynamic> json) => BookPageItem(
    pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
    text: json['text']?.toString() ?? '',
    sceneAction: json['sceneAction']?.toString() ?? '',
    sceneEmotion: json['sceneEmotion']?.toString() ?? '',
    sceneComposition: json['sceneComposition']?.toString() ?? '',
    characterIds: (json['characterIds'] as List<dynamic>? ?? [])
        .map((id) => id.toString())
        .toList(),
    outfitOverrides: (json['outfitOverrides'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    rawPrompt: json['rawPrompt']?.toString(),
    imageBase64: json['imageBase64']?.toString(),
    imagePath: json['imagePath']?.toString(),
    isPlaceholder: json['isPlaceholder'] == true,
    customInstruction: json['customInstruction']?.toString(),
    // 缺键视为需要插画，仅显式 false 才关闭
    needIllustration: json['needIllustration'] != false,
    generationError: json['generationError']?.toString(),
    imageModelUsed: json['imageModelUsed']?.toString(),
    imageProviderUsed: json['imageProviderUsed']?.toString(),
    imageReferenceApplied: json['imageReferenceApplied'] == true,
    audioPath: json['audioPath']?.toString(),
    audioError: json['audioError']?.toString(),
  );
}

class BookStyle {
  final String id;
  final String name;
  final String desc;
  final String prefix;
  final String negative;

  const BookStyle({
    required this.id,
    required this.name,
    required this.desc,
    required this.prefix,
    required this.negative,
  });
}
