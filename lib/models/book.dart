class PictureBook {
  final String id;
  final String title;
  final String styleId;
  final String styleName;
  final List<BookPageItem> pages;
  final DateTime createdAt;
  String? protagonistRefImage; // 主角定妆照参考图（Base64），全书所有页面及单独重绘共用，锁定角色外貌

  PictureBook({
    required this.id,
    required this.title,
    required this.styleId,
    required this.styleName,
    required this.pages,
    required this.createdAt,
    this.protagonistRefImage,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'styleId': styleId,
        'styleName': styleName,
        'pages': pages.map((p) => p.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
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
        protagonistRefImage: json['protagonistRefImage'],
      );
}

class BookPageItem {
  final int pageIndex;
  String text;
  String sceneAction;
  String sceneEmotion;
  String? rawPrompt; // 原生图提示词
  String? imageBase64;
  String? imagePath;
  bool isPlaceholder;
  String? customInstruction;
  bool needIllustration; // 是否生成插画

  BookPageItem({
    required this.pageIndex,
    required this.text,
    this.sceneAction = '',
    this.sceneEmotion = '',
    this.rawPrompt,
    this.imageBase64,
    this.imagePath,
    this.isPlaceholder = false,
    this.customInstruction,
    this.needIllustration = true,
  });

  Map<String, dynamic> toJson() => {
        'pageIndex': pageIndex,
        'text': text,
        'sceneAction': sceneAction,
        'sceneEmotion': sceneEmotion,
        'rawPrompt': rawPrompt,
        'imageBase64': imageBase64,
        'imagePath': imagePath,
        'isPlaceholder': isPlaceholder,
        'customInstruction': customInstruction,
        'needIllustration': needIllustration,
      };

  factory BookPageItem.fromJson(Map<String, dynamic> json) => BookPageItem(
        pageIndex: json['pageIndex'] ?? 0,
        text: json['text'] ?? '',
        sceneAction: json['sceneAction'] ?? '',
        sceneEmotion: json['sceneEmotion'] ?? '',
        rawPrompt: json['rawPrompt'],
        imageBase64: json['imageBase64'],
        imagePath: json['imagePath'],
        isPlaceholder: json['isPlaceholder'] ?? false,
        customInstruction: json['customInstruction'],
        needIllustration: json['needIllustration'] ?? true,
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
