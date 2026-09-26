class PictureBook {
  final String id;
  final String title;
  final String styleId;
  final String styleName;
  final List<BookPageItem> pages;
  final DateTime createdAt;
  final List<BookCharacter> characters;
  String? protagonistRefImage; // 主角定妆照参考图（Base64），全书所有页面及单独重绘共用，锁定角色外貌

  PictureBook({
    required this.id,
    required this.title,
    required this.styleId,
    required this.styleName,
    required this.pages,
    required this.createdAt,
    this.characters = const [],
    this.protagonistRefImage,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'styleId': styleId,
    'styleName': styleName,
    'pages': pages.map((p) => p.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'characters': characters.map((c) => c.toJson()).toList(),
    'protagonistRefImage': protagonistRefImage,
  };

  factory PictureBook.fromJson(Map<String, dynamic> json) => PictureBook(
    id: json['id'] ?? '',
    title: json['title'] ?? '未命名绘本',
    styleId: json['styleId'] ?? 'watercolor',
    styleName: json['styleName'] ?? '水彩童话',
    pages: (json['pages'] as List<dynamic>? ?? [])
        .map((p) => BookPageItem.fromJson(p))
        .toList(),
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    characters: (json['characters'] as List<dynamic>? ?? [])
        .map((c) => BookCharacter.fromJson(c as Map<String, dynamic>))
        .toList(),
    protagonistRefImage: json['protagonistRefImage'],
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
    pageIndex: json['pageIndex'] ?? 0,
    text: json['text'] ?? '',
    sceneAction: json['sceneAction'] ?? '',
    sceneEmotion: json['sceneEmotion'] ?? '',
    sceneComposition: json['sceneComposition'] ?? '',
    characterIds: (json['characterIds'] as List<dynamic>? ?? [])
        .map((id) => id.toString())
        .toList(),
    outfitOverrides: (json['outfitOverrides'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    rawPrompt: json['rawPrompt'],
    imageBase64: json['imageBase64'],
    imagePath: json['imagePath'],
    isPlaceholder: json['isPlaceholder'] ?? false,
    customInstruction: json['customInstruction'],
    needIllustration: json['needIllustration'] ?? true,
    generationError: json['generationError'],
    imageModelUsed: json['imageModelUsed'],
    imageProviderUsed: json['imageProviderUsed'],
    imageReferenceApplied: json['imageReferenceApplied'] ?? false,
    audioPath: json['audioPath'],
    audioError: json['audioError'],
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
