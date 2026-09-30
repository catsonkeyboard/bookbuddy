import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/book.dart';
import '../models/character_card.dart';

class StoryboardDraft {
  final List<BookCharacter> characters;
  final List<BookPageItem> pages;

  const StoryboardDraft({required this.characters, required this.pages});
}

/// 故事助手的输出：标题 + 正文。
class StoryDraftResult {
  final String title;
  final String story;

  const StoryDraftResult({required this.title, required this.story});
}

/// 随文本一起发给大模型的一张图片（原始 base64，不带 data: 前缀）。
class LlmImageInput {
  final String base64;
  final String mimeType;

  const LlmImageInput({required this.base64, required this.mimeType});
}

/// 识图得到的角色卡草稿，由用户确认后填进表单。
class CharacterCardDraft {
  final String name;
  final CharacterKind kind;
  final String species;
  final String appearance;
  final String defaultOutfit;
  final String personality;
  final String catchphrase;

  const CharacterCardDraft({
    required this.name,
    required this.kind,
    this.species = '',
    required this.appearance,
    this.defaultOutfit = '',
    this.personality = '',
    this.catchphrase = '',
  });
}

/// 从角色库选中、要固定进本书的角色：卡片本体 + 当前画风的定妆图（可能为空）。
/// photoBase64 留给拍照阶段使用，P1 恒为空。
class PinnedCharacter {
  final CharacterCard card;
  final String? anchorBase64;
  final String? photoBase64;

  const PinnedCharacter({
    required this.card,
    this.anchorBase64,
    this.photoBase64,
  });
}

class _ImageReference {
  final String name;
  final String base64;
  final bool isPhoto;
  const _ImageReference(this.name, this.base64, {this.isPhoto = false});
}

class BookEngineService {
  final Dio _dio;

  /// 真实照片作参考图时附在说明里的要求（三条生图分支共用）。
  static const _photoGuidance =
      '请按照片中的外形、颜色、材质和标志性细节绘制这个角色，并转换为当前绘本画风；忽略照片的背景、光线和拍摄角度。';

  BookEngineService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 45),
              receiveTimeout: const Duration(seconds: 90),
            ),
          );

  /// 阶段 1：通过 LLM 将故事重构为 8~12 幕紧凑的绘本跨页镜头
  Future<List<BookPageItem>> createStoryboards({
    required AppSettings settings,
    required String title,
    required String storyText,
  }) async => (await createStoryboardDraft(
    settings: settings,
    title: title,
    storyText: storyText,
  )).pages;

  /// 故事创作助手：按角色卡与一句描述写儿童卡通故事。
  /// 传入 currentStory（编辑框现文本）与 feedback 时进入修改模式，只改反馈涉及的部分。
  Future<StoryDraftResult> composeStory({
    required AppSettings settings,
    required List<CharacterCard> cards,
    required String brief,
    String? currentStory,
    String? feedback,
  }) async {
    if (cards.length > kMaxCharacterCardsPerBook) {
      throw ArgumentError('最多只能选择 $kMaxCharacterCardsPerBook 张角色卡');
    }
    final trimmedBrief = brief.trim();
    if (trimmedBrief.isEmpty) {
      throw ArgumentError('请先写一句你想讲的故事');
    }

    final systemPrompt = '''
你是一位面向 3 到 8 岁儿童的卡通故事作者。语言温暖、有画面感、朗读顺畅；不出现恐怖、暴力、说教或成人话题。
${_storyCastBlock(cards)}
## 故事结构
- 开端 → 一个小冲突或小任务 → 转折 → 温暖收尾。
- 正文 400 到 700 字；分 8 到 12 个自然段，每段是一个可以画出来的场景，为后续分镜留好接口。
- 对话简短，符合孩子的理解力；结尾给孩子一点温暖的感受，不要生硬说教。
## 输出格式
只输出合法 JSON：{"title": "故事标题（不超过 12 个字）", "story": "正文，段落之间用换行分隔"}。story 字符串里的换行必须写成 \\n 转义，不要输出真实换行；对话请用中文引号“”，不要用英文双引号。
''';

    final isRevision = currentStory != null && currentStory.trim().isNotEmpty;
    final trimmedFeedback = (feedback ?? '').trim();
    final userPrompt = isRevision
        ? '''
### 故事要求
$trimmedBrief

### 当前故事（用户可能已手动修改过）
${currentStory.trim()}

### 用户的修改意见
${trimmedFeedback.isEmpty ? '（无具体意见，请在保持原文的前提下小幅润色）' : trimmedFeedback}

请只修改反馈涉及的部分，其余保持原文不动；若反馈明确要求整体重写则可以重写。仍然只输出同一格式的 JSON。
'''
        : '''
### 故事要求
$trimmedBrief

请据此创作故事，只输出 JSON。
''';

    String raw;
    try {
      raw = await _callLlm(
        settings: settings,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        temperature: 0.8,
      );
    } on DioException catch (e) {
      // 部分 OpenAI 兼容的推理模型不接受自定义 temperature（400），去掉后重试一次。
      final body = '${e.response?.data ?? ''}';
      if (e.response?.statusCode == 400 && body.contains('temperature')) {
        raw = await _callLlm(
          settings: settings,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
        );
      } else {
        rethrow;
      }
    }
    final parsed = _extractJson(raw);
    final rawStory = parsed is Map ? parsed['story'] : null;
    final story = switch (rawStory) {
      List list => list.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join('\n\n'),
      _ => rawStory?.toString().trim() ?? '',
    };
    if (story.isEmpty) {
      throw const FormatException('故事生成结果格式不正确');
    }
    var title = parsed is Map ? (parsed['title']?.toString().trim() ?? '') : '';
    if (title.isEmpty) {
      final firstSentence = story.split(RegExp(r'[。！？!?\n]')).first.trim();
      title = firstSentence.length > 12
          ? firstSentence.substring(0, 12)
          : firstSentence;
    }
    return StoryDraftResult(title: title, story: story);
  }

  /// 故事助手的角色段落：有卡片时逐条列出并要求原样使用，没有则让大模型自行设计。
  String _storyCastBlock(List<CharacterCard> cards) {
    if (cards.isEmpty) {
      return '## 角色\n用户没有指定角色，请根据故事要求自行设计 1 到 3 个可爱的角色，并给他们起亲切易读的名字。';
    }
    String kindLabel(CharacterKind kind) => switch (kind) {
          CharacterKind.human => '人类',
          CharacterKind.animal => '动物',
          CharacterKind.object => '物件',
        };
    String orBlank(String value, String fallback) =>
        value.trim().isEmpty ? fallback : value.trim();
    final lines = cards.map((c) {
      final projected = c.toBookCharacter();
      final species = c.species.trim().isEmpty ? '' : '，${c.species.trim()}';
      return '- ${c.name}（${kindLabel(c.kind)}$species）：外貌 ${projected.appearance}；'
          '服装 ${projected.defaultOutfit}；'
          '性格 ${orBlank(c.personality, '未填写')}；'
          '口头禅 ${orBlank(c.catchphrase, '无')}';
    }).join('\n');
    return '''
## 角色（必须原样使用）
$lines
- 名字与设定必须原样使用，不得改名，不得改变物种或外貌。
- 每个有口头禅的角色，口头禅至少自然地出现一次；性格通过行为和对话体现，不要直接罗列。
''';
  }

  /// 看一张玩具 / 宠物 / 物件照片，设计成一个适合绘本的拟人角色草稿。
  /// 激活的文本模型不支持图片时，上游错误原样抛出，由页面提示切换模型。
  Future<CharacterCardDraft> describeCharacterFromPhoto({
    required AppSettings settings,
    required String photoBase64,
    required String mimeType,
  }) async {
    if (photoBase64.isEmpty) {
      throw ArgumentError('请先选择一张照片');
    }
    const systemPrompt = '''
你是一位儿童绘本角色设计师。用户会给你一张儿童玩具、宠物或日常物件的照片，请把照片里的主体设计成一个适合 3 到 8 岁儿童绘本的拟人角色。
要求：
- appearance 必须是可以直接画出来的具体外貌：颜色、材质、体型、五官或标志性细节；只写主体本身，不写背景、光线和拍摄角度。
- name 亲切易读，2 到 4 个汉字。
- catchphrase 一句，不超过 12 个字；personality 用一两句话写性格。
- kind 按实物判断：毛绒动物玩具与真实动物都算 animal，人形玩偶或人物算 human，石头、机器人、汽车等物件算 object。
- species 写物种或物件名，如「毛绒恐龙」「橘猫」「鹅卵石」；defaultOutfit 只写照片里确实穿戴的衣物或配饰，没有就留空字符串。
只输出合法 JSON，不要解释，不要代码块；字符串里不要出现真实换行，引号用中文引号“”：
{"name": "", "kind": "animal", "species": "", "appearance": "", "defaultOutfit": "", "personality": "", "catchphrase": ""}
''';
    final raw = await _callLlm(
      settings: settings,
      systemPrompt: systemPrompt,
      userPrompt: '请根据这张照片设计角色，只输出 JSON。',
      images: [LlmImageInput(base64: photoBase64, mimeType: mimeType)],
    );
    final parsed = _extractJson(raw);
    String field(String key) =>
        parsed is Map ? (parsed[key]?.toString().trim() ?? '') : '';
    final name = field('name');
    final kindName = field('kind');
    final appearance = field('appearance');
    if (name.isEmpty || kindName.isEmpty || appearance.isEmpty) {
      throw const FormatException('识图结果格式不正确');
    }
    return CharacterCardDraft(
      name: name,
      kind: CharacterKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => CharacterKind.animal,
      ),
      species: field('species'),
      appearance: appearance,
      defaultOutfit: field('defaultOutfit'),
      personality: field('personality'),
      catchphrase: field('catchphrase'),
    );
  }

  Future<StoryboardDraft> createStoryboardDraft({
    required AppSettings settings,
    required String title,
    required String storyText,
    List<PinnedCharacter> pinnedCharacters = const [],
  }) async {
    if (pinnedCharacters.length > kMaxCharacterCardsPerBook) {
      throw ArgumentError('最多只能选择 $kMaxCharacterCardsPerBook 张角色卡');
    }
    final pinnedNames = <String, String>{};
    for (final p in pinnedCharacters) {
      final name = p.card.name.trim();
      final other = pinnedNames[name];
      if (other != null && other != p.card.id) {
        throw ArgumentError(
          '选择的角色卡里有两张都叫「$name」，请先在角色库里改名，再一起使用。',
        );
      }
      pinnedNames[name] = p.card.id;
    }
    final systemPrompt = '''
你是一位资深儿童绘本分镜大师。请阅读完整故事，将故事整体改编并重构为 8 ~ 12 个连续生动的【绘本跨页镜头（Scenes）】。
## 绘本核心原则：
1. 【一页一图、图文对应】：每个镜头即为绘本的一页，必须包含本页文本以及对应的一幅插画画面设定。
2. 【场景聚合、杜绝零碎】：将发生在同一时空环境下的动作、相关对话及叙述自然融合成一段（2~4句话，朗读顺畅有画面感），严禁将一句问一句答切成孤立碎片。
3. 【画面动作与角色描述规范】：
   - 人物与动物名词规范：自然界中的动物（如乌龟、小蝌蚪、大青蛙、鲤鱼、小鸟、小羊、小猪等）直接使用标准生物名词（如“一只大乌龟”、“一群黑色小蝌蚪”、“绿色大青蛙”），【绝对不要】抽象化改写为“甲壳水生动物”、“水生幼体”等怪异生硬词汇！
   - 商标版权规避（仅限特定商业IP）：仅对具有明确商业版权/商标的人物IP（如迪士尼特有的“辛德瑞拉”、“白雪公主”）才转换为通用外貌（如“金发少女”、“黑发少女”）；
   - 动作和神态描述保持童趣温馨，避免“双膝跪地”、“使唤”、“刻薄”等容易被 AI 审核判定为霸凌或受虐倾向的词汇，改用“正在壁炉旁擦拭地面”、“神态温和恬静”等健康正向画面词汇。
4. 【动物外貌与服饰】：动物保留准确物种、毛皮或羽毛以及身体特征。原故事未明确穿衣时，不给动物添加鞋靴、帽子、背带裤等人类服饰；故事明确写了服饰时只画指定服饰，不自行添加其他配件。拟人化动作不能改变动物物种。
5. 【角色名单】：把每个反复出场的角色分别列入 characters。例如《不来梅的音乐家》的驴、狗、猫、公鸡是四个独立角色，绝不能把“四个动物伙伴”合并为一个角色，也不能把猫替换成猪。给集合称呼建立 groups，并在每页 characterIds 中列出画面里每个成员的 ID。action 也应写出具体物种和角色，避免只写“几个伙伴”。
6. 【场景因果与镜头】：每页 composition 明确主要角色的位置、身体和视线朝向、动作对象的位置、动作方向以及合适的镜头角度。角色应朝向动作对象，不能为了露出正脸而违背情节。例如狼朝房子吹气，狼应侧身或背侧对镜头、面向房子，气流从狼吹向房子；房子在狼正前方，不能在狼背后。
7. 只能输出合法 JSON 格式，格式如下：
{
  "characters": [
    {
      "id": "c1",
      "name": "故事中稳定使用的角色名",
      "species": "准确物种，如猫、公鸡、鸭子；人类填人类",
      "isAnimal": true,
      "appearance": "不随页面改变的物种、体型、脸型、毛发或发型颜色、标志性特征；具体、可绘制",
      "defaultOutfit": "原故事明确的默认服装；未穿衣的动物写自然毛皮或羽毛、无鞋靴和人类配饰"
    }
  ],
  "groups": {"角色集合称呼": ["c1"]},
  "scenes": [
    {
      "pageIndex": 0,
      "text": "本页绘本文字（2~4句，生动通俗）",
      "action": "当前画面的核心视觉动作，具体点名画面中的角色和物种，不用笼统集合称呼代替名单",
      "emotion": "神态微表情（如：金发少女眼神温柔从容，大灰狼站立在树旁歪嘴坏笑）",
      "composition": "角色在画面中的位置、身体与视线朝向、动作对象的位置和动作方向；如狼在左侧面向右侧草屋吹气，侧面镜头，草屋位于狼前方",
      "characterIds": ["c1"],
      "outfitOverrides": {}
    }
  ]
}
角色档案列出所有需要跨页保持一致的角色，名字、物种和 ID 在全书保持一致。每页 characterIds 只列画面中实际出现的角色，群体成员要逐个列出。默认服装跨页保持不变，只有原故事明确换装时才填写 outfitOverrides，且说明服装颜色和细节。没有故事依据时不要添加鞋子等配饰。不能强行要求角色正面对镜头。
''';
    final fullSystemPrompt = pinnedCharacters.isEmpty
        ? systemPrompt
        : '$systemPrompt${_pinnedPromptBlock(pinnedCharacters)}';

    final userPrompt =
        '''
### 绘本标题
$title

### 故事正文
$storyText
''';

    final rawJson = await _callLlm(
      settings: settings,
      systemPrompt: fullSystemPrompt,
      userPrompt: userPrompt,
    );

    final parsed = _extractJson(rawJson);
    final rawCharacters = parsed is Map
        ? (parsed['characters'] as List? ?? [])
        : [];
    final characters = <BookCharacter>[];
    for (final entry in rawCharacters) {
      if (entry is! Map) continue;
      final id = entry['id']?.toString().trim() ?? '';
      final name = entry['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty || characters.any((c) => c.id == id)) {
        continue;
      }
      final species = entry['species']?.toString().trim() ?? '';
      characters.add(
        BookCharacter(
          id: id,
          name: name,
          species: species,
          isAnimal:
              entry['isAnimal'] == true ||
              RegExp(r'驴|狗|猫|鸡|鸭|鹅|猪|狼|羊|牛|马|兔|鸟|狐|鹿|熊|虎|狮|鱼|龟|鼠|蝌蚪')
                  .hasMatch(species),
          appearance: entry['appearance']?.toString().trim() ?? '',
          defaultOutfit: entry['defaultOutfit']?.toString().trim() ?? '',
        ),
      );
    }
    final rawList = parsed is Map
        ? (parsed['scenes'] as List? ?? [])
        : (parsed is List ? parsed : []);
    final groups = <String, List<String>>{};
    if (parsed is Map && parsed['groups'] is Map) {
      for (final group in (parsed['groups'] as Map).entries) {
        if (group.value is! List) continue;
        groups[group.key.toString()] = (group.value as List)
            .map((id) => id.toString())
            .where((id) => characters.any((c) => c.id == id))
            .toList();
      }
    }
    final List<BookPageItem> pages = [];
    for (int i = 0; i < rawList.length; i++) {
      final s = rawList[i];
      if (s is Map) {
        final ids = (s['characterIds'] as List? ?? [])
            .map((id) => id.toString())
            .where((id) => characters.any((c) => c.id == id))
            .toSet();
        final visualDescription =
            '${s['action'] ?? ''} ${s['emotion'] ?? ''} ${s['composition'] ?? ''}';
        ids.addAll(
          characters
              .where((c) => visualDescription.contains(c.name))
              .map((c) => c.id),
        );
        for (final group in groups.entries) {
          if (visualDescription.contains(group.key)) {
            ids.addAll(group.value);
          }
        }
        // LLM 忘记列集合映射时，仍可恢复「四个动物伙伴」这种常见画面。
        final animals = characters.where((c) => c.isAnimal).toList();
        if (animals.length == 4 &&
            RegExp(r'(四个|四只|四位|4个|4只).{0,4}(动物|伙伴)')
                .hasMatch(visualDescription)) {
          ids.addAll(animals.map((c) => c.id));
        }
        final outfits =
            (s['outfitOverrides'] as Map? ?? {}).map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )..removeWhere(
              (id, value) => !ids.contains(id) || value.trim().isEmpty,
            );
        pages.add(
          BookPageItem(
            pageIndex: i,
            text: s['text'] ?? '',
            sceneAction: s['action'] ?? '',
            sceneEmotion: s['emotion'] ?? '',
            sceneComposition: s['composition'] ?? '',
            characterIds: ids.toList(),
            outfitOverrides: outfits,
          ),
        );
      }
    }
    _reconcilePinned(
      characters: characters,
      pages: pages,
      pinned: pinnedCharacters,
    );
    return StoryboardDraft(characters: characters, pages: pages);
  }

  /// 有固定角色时追加到系统提示词末尾的段落；没有则为空串。
  String _pinnedPromptBlock(List<PinnedCharacter> pinned) {
    if (pinned.isEmpty) return '';
    String kindLabel(CharacterKind kind) => switch (kind) {
          CharacterKind.human => '人类',
          CharacterKind.animal => '动物',
          CharacterKind.object => '物件',
        };
    String orBlank(String value, String fallback) =>
        value.trim().isEmpty ? fallback : value.trim();
    final lines = pinned.map((p) {
      final c = p.card;
      final projected = c.toBookCharacter();
      return '- id: ${c.id}｜名字：${c.name}｜类型：${kindLabel(c.kind)}'
          '｜物种：${orBlank(c.species, '（未填写）')}'
          '｜外貌：${projected.appearance}'
          '｜默认服装：${projected.defaultOutfit}'
          '｜性格：${orBlank(c.personality, '（未填写）')}'
          '｜口头禅：${orBlank(c.catchphrase, '（无）')}';
    }).join('\n');
    // 没有任何卡片填了口头禅或性格时，不要求大模型去体现它们。
    final hasVoice = pinned.any(
      (p) =>
          p.card.catchphrase.trim().isNotEmpty ||
          p.card.personality.trim().isNotEmpty,
    );
    final requirements = <String>[
      'characters 中必须包含上述每个角色，id 原样输出（例如 ${pinned.first.card.id}）；可以另外新增配角（用 c1、c2 编号）。',
      '故事需要主角时优先使用上述角色；每个固定角色至少出现在一个镜头的 characterIds 中。',
      if (hasVoice) '口头禅要自然地出现在该角色至少一页的 text 里；性格要体现在 action 与 emotion 的描写中。',
    ];
    final numbered = [
      for (var i = 0; i < requirements.length; i++) '${i + 1}. ${requirements[i]}',
    ].join('\n');
    return '''

【固定角色，必须原样使用】
以下角色已经存在，必须使用给定的 id、名字、物种、外貌与默认服装，不得改名、不得重新设计外貌、不得更换物种：
$lines
要求：
$numbered
''';
  }

  /// 卡片是唯一真相源：覆盖同 id 条目 → 合并大模型另造的同名角色 → 按名字补漏 → 无出场则报错。
  void _reconcilePinned({
    required List<BookCharacter> characters,
    required List<BookPageItem> pages,
    required List<PinnedCharacter> pinned,
  }) {
    if (pinned.isEmpty) return;
    // 空分镜交给调用方报「未能生成分镜」，不要误报成角色没出场。
    if (pages.isEmpty) return;
    final pinnedIds = pinned.map((p) => p.card.id).toSet();
    for (final p in pinned) {
      final card = p.card;
      final projected = card.toBookCharacter(referenceImageBase64: p.anchorBase64);

      // 规则一：同 id 用卡片字段整体替换；不存在则插到最前。
      final index = characters.indexWhere((c) => c.id == card.id);
      if (index >= 0) {
        characters[index] = projected;
      } else {
        characters.insert(0, projected);
      }

      // 规则二：大模型另造的同名角色合并到卡片 id，页面引用与换装一并改写。
      final name = card.name.trim();
      final duplicates = characters
          .where((c) =>
              c.id != card.id &&
              !pinnedIds.contains(c.id) &&
              c.name.trim() == name)
          .map((c) => c.id)
          .toList();
      if (duplicates.isNotEmpty) {
        characters.removeWhere((c) => duplicates.contains(c.id));
        for (final page in pages) {
          if (page.characterIds.any(duplicates.contains)) {
            page.characterIds = {
              for (final id in page.characterIds)
                duplicates.contains(id) ? card.id : id,
            }.toList();
          }
          for (final dup in duplicates) {
            final outfit = page.outfitOverrides.remove(dup);
            if (outfit != null && !page.outfitOverrides.containsKey(card.id)) {
              page.outfitOverrides[card.id] = outfit;
            }
          }
        }
      }

      // 规则三：没有任何页面列出它时，按名字扫描页面文字补入。
      if (!pages.any((page) => page.characterIds.contains(card.id)) &&
          name.isNotEmpty) {
        for (final page in pages) {
          final visual =
              '${page.text} ${page.sceneAction} ${page.sceneEmotion} ${page.sceneComposition}';
          if (visual.contains(name)) {
            page.characterIds = [...page.characterIds, card.id];
          }
        }
      }

      // 规则四：仍然无出场，明确报错，不静默生成新主角。
      if (!pages.any((page) => page.characterIds.contains(card.id))) {
        throw StateError(
          '角色卡「${card.name}」没有出现在任何分镜中。请在故事里写到它，或取消选择该角色卡。',
        );
      }
    }
  }

  /// 组装默认的原生图提示词
  String buildDefaultPrompt({
    required BookStyle style,
    required BookPageItem page,
  }) {
    final promptBits = [
      style.prefix,
      '场景情节动作：${page.sceneAction}',
      if (page.sceneEmotion.isNotEmpty) '神态微表情：${page.sceneEmotion}',
      '纯净绘本跨页画面，主体突出，温馨和谐，严禁出现三视图、设计稿和字符文字',
    ];
    return promptBits.join('，');
  }

  /// 固定角色设定始终在可编辑的页面提示词之外，避免单页重绘时意外丢失。
  String composePagePrompt({
    required BookPageItem page,
    required List<BookCharacter> characters,
    required String scenePrompt,
  }) {
    final cast = characters
        .where((c) => page.characterIds.contains(c.id))
        .toList();
    final lines = <String>[
      '【本页场景】$scenePrompt',
      '【本页必须遵守的画面约束】',
      '动物角色只穿故事或角色设定明确指定的服饰；没有明确写鞋靴时不要添加鞋靴，也不要自动添加帽子、背带裤等配件。',
      if (cast.isNotEmpty)
        '出场角色名单：${cast.map((c) => '${c.name}（${c.species.isEmpty ? c.appearance : c.species}）').join('、')}。'
            '名单中的每个角色都要出现，不能遗漏、替换物种或添加新的主要角色。',
    ];
    for (final character in cast) {
      final outfit = page.outfitOverrides[character.id]?.trim();
      lines.add(
        '${character.name}（${character.id}，物种：${character.species}）：固定外貌：${character.appearance}；'
        '本页服装：${outfit == null || outfit.isEmpty ? character.defaultOutfit : outfit}。',
      );
      if (character.isAnimal) {
        lines.add(
          '动物角色 ${character.name}：保留${character.species}的自然身体、毛皮或羽毛。'
          '只允许服装字段明确写出的服饰；没有写鞋靴就不能画鞋靴，没有写帽子就不能画帽子。'
          '不要因为拟人化动作而增加人类服装、配件或改变物种。',
        );
      }
    }
    lines.add(
      '【动作目标与空间关系，优先遵守】${page.sceneComposition.isEmpty ? '按场景动作安排角色朝向：角色面向其交互对象，不必正面对镜头；动作对象必须位于动作前方。' : page.sceneComposition}',
    );
    lines.add(
      '若画面描述与故事动作的因果关系冲突，以故事动作和上述空间关系为准。'
      '镜头应服务于故事动作。角色身体、视线与动作必须指向互动对象；'
      '允许侧面和背侧视角，不要为了展示正脸而把角色转向观众。'
      '角色定妆照只用于身份、物种和服装，不复制其姿势、朝向、背景或镜头。',
    );
    return lines.join('\n');
  }

  /// 生图前检查集合称呼是否已有完整的具名角色列表。
  String? validateSceneCast({
    required BookPageItem page,
    required List<BookCharacter> characters,
  }) {
    if (characters.isEmpty) return null; // 旧绘本仍使用原有参考图结构。
    final description = '${page.sceneAction} ${page.sceneComposition}';
    for (final character in characters) {
      if (description.contains(character.name) &&
          !page.characterIds.contains(character.id)) {
        return '画面提到${character.name}，但出场名单中没有该角色';
      }
    }
    final countMatch = RegExp(
      r'(二|两|三|四|五|六|七|八|2|3|4|5|6|7|8)(?:个|只|位).{0,3}(?:动物|伙伴|角色)',
    ).firstMatch(description);
    if (countMatch != null) {
      const counts = {
        '二': 2,
        '两': 2,
        '三': 3,
        '四': 4,
        '五': 5,
        '六': 6,
        '七': 7,
        '八': 8,
      };
      final raw = countMatch.group(1)!;
      final expected = counts[raw] ?? int.tryParse(raw) ?? 0;
      if (page.characterIds.length < expected) {
        return '画面描述有 $expected 个角色，出场名单只有 ${page.characterIds.length} 个';
      }
    }
    if (page.characterIds.isEmpty &&
        RegExp(r'动物伙伴|伙伴们|角色们').hasMatch(description)) {
      return '画面使用了集合称呼，但没有指定具体出场角色';
    }
    return null;
  }

  bool supportsCharacterReference({
    required String type,
    required String baseUrl,
    required String model,
  }) =>
      type == 'tokenhub' ||
      baseUrl.contains('tokenhub.tencentmaas.com') ||
      baseUrl.contains('wand/hunyuan-image') ||
      model.toLowerCase().contains('hy-image') ||
      (type == 'gemini' && !model.toLowerCase().contains('imagen'));

  Future<String?> generateCharacterReference({
    required AppSettings settings,
    required BookStyle style,
    required BookCharacter character,
    String? photoReferenceBase64,
  }) async {
    final prompt =
        '${style.prefix}。单独绘制角色定妆照：${character.name}。'
        '固定外貌：${character.appearance}。默认服装：${character.defaultOutfit}。'
        '全身自然站立，三分之二侧面视角，面部与物种特征清晰，简洁纯色背景。'
        '这是身份参考，后续故事页可用任何符合动作的朝向，不固定正面姿势。'
        '画面中只能有这一个角色，不要文字、其他人物或场景。';
    // 通道能接收参考图时才带上照片；否则只按文字生成（调用方已提前提示用户）。
    final photo = (photoReferenceBase64 != null &&
            photoReferenceBase64.isNotEmpty &&
            supportsCharacterReference(
              type: settings.imageType,
              baseUrl: settings.imageBaseUrl,
              model: settings.imageModel,
            ))
        ? photoReferenceBase64
        : null;
    return _callImageApi(
      type: settings.imageType,
      baseUrl: settings.imageBaseUrl,
      apiKey: settings.imageApiKey,
      model: settings.imageModel,
      prompt: sanitizePrompt(prompt),
      negative: style.negative,
      references: [
        if (photo != null) _ImageReference(character.name, photo, isPhoto: true),
      ],
    );
  }

  /// 对 prompt 进行安全净化，消除容易触发上游审查拦截的敏感专有名词与词汇
  String sanitizePrompt(String raw) {
    var p = raw;
    final replacements = {
      '辛德瑞拉': '金发少女',
      '灰姑娘': '质朴金发少女',
      'Cinderella': 'fair-haired maiden',
      '白雪公主': '黑发纯真少女',
      'Snow White': 'fair maiden',
      '睡美人': '沉睡的公主',
      '双膝跪地': '蹲在地上',
      '跪地': '在地面',
      '刻薄': '神态冷淡',
      '使唤': '指点',
      '隐忍': '安静乖巧',
      '上身赤裸': '身披微光纱衣',
      '一丝不挂': '穿着轻薄长袍',
      '没穿衣服': '身着特制透明礼服',
      '没穿衣物': '身着特制透明礼服',
      '光着身子': '身着特制透明礼服',
      '光着身体': '身着特制透明礼服',
    };
    replacements.forEach((key, val) {
      p = p.replaceAll(key, val);
    });
    return p;
  }

  /// 阶段 2：生成单页绘本插画（注入全书统一主角定妆照 referenceImageBase64 锁定外貌一致性）
  Future<String?> generateIllustration({
    required AppSettings settings,
    required BookStyle style,
    required BookPageItem page,
    String? fullPromptOverride,
    String? customInstruction,
    String? referenceImageBase64,
    List<BookCharacter> characters = const [],
  }) async {
    final castError = validateSceneCast(page: page, characters: characters);
    if (castError != null) {
      throw StateError('角色名单不完整：$castError。请在分镜页编辑出场角色。');
    }
    // 优先使用用户编辑/重写的完整提示词；否则按规范组装
    String finalPrompt;
    if (fullPromptOverride != null && fullPromptOverride.trim().isNotEmpty) {
      finalPrompt = fullPromptOverride.trim();
    } else {
      finalPrompt = buildDefaultPrompt(style: style, page: page);
      if (customInstruction != null && customInstruction.isNotEmpty) {
        finalPrompt += '，画面微调要求：$customInstruction';
      }
    }

    // 记录本次实际使用的原生生图提示词
    page.rawPrompt = finalPrompt;

    final pagePrompt = composePagePrompt(
      page: page,
      characters: characters,
      scenePrompt: finalPrompt,
    );
    final references = <_ImageReference>[
      for (final c in characters)
        if (page.characterIds.contains(c.id) &&
            c.referenceImageBase64 != null &&
            c.referenceImageBase64!.isNotEmpty)
          _ImageReference(c.name, c.referenceImageBase64!),
    ];
    if (supportsCharacterReference(
          type: settings.imageType,
          baseUrl: settings.imageBaseUrl,
          model: settings.imageModel,
        ) &&
        characters.any(
          (c) =>
              page.characterIds.contains(c.id) &&
              (c.referenceImageBase64 == null ||
                  c.referenceImageBase64!.isEmpty),
        )) {
      throw StateError('出场角色缺少定妆照，请先生成并确认角色参考图。');
    }
    if (references.isEmpty &&
        referenceImageBase64 != null &&
        referenceImageBase64.isNotEmpty) {
      references.add(_ImageReference('主角', referenceImageBase64));
    }

    // 进行安全脱敏过滤（防止触发 PROHIBITED_CONTENT）
    final cleanPrompt = sanitizePrompt(pagePrompt);
    final negative = style.negative;

    // 1. 尝试主通道
    try {
      final b64 = await _callImageApi(
        type: settings.imageType,
        baseUrl: settings.imageBaseUrl,
        apiKey: settings.imageApiKey,
        model: settings.imageModel,
        prompt: cleanPrompt,
        negative: negative,
        references: references,
      );
      if (b64 != null && b64.isNotEmpty) {
        page.generationError = null;
        page.imageProviderUsed = settings.imageType;
        page.imageModelUsed = settings.imageModel;
        page.imageReferenceApplied =
            references.isNotEmpty &&
            supportsCharacterReference(
              type: settings.imageType,
              baseUrl: settings.imageBaseUrl,
              model: settings.imageModel,
            );
        return b64;
      }
    } catch (e) {
      // 主通道失败，检查是否有备用通道
      if (!settings.enableImageFallback ||
          settings.fallbackImageApiKey.isEmpty) {
        page.generationError = e.toString();
        rethrow;
      }
    }

    // 2. 尝试备用通道
    if (settings.enableImageFallback &&
        settings.fallbackImageApiKey.isNotEmpty) {
      final primaryUsesReference =
          references.isNotEmpty &&
          supportsCharacterReference(
            type: settings.imageType,
            baseUrl: settings.imageBaseUrl,
            model: settings.imageModel,
          );
      if (primaryUsesReference &&
          !supportsCharacterReference(
            type: settings.fallbackImageType,
            baseUrl: settings.fallbackImageBaseUrl,
            model: settings.fallbackImageModel,
          )) {
        page.generationError = '备用生图通道不支持角色参考图，已停止自动降级；请重试主通道或调整备用模型。';
        throw StateError(page.generationError!);
      }
      try {
        final b64 = await _callImageApi(
          type: settings.fallbackImageType,
          baseUrl: settings.fallbackImageBaseUrl,
          apiKey: settings.fallbackImageApiKey,
          model: settings.fallbackImageModel,
          prompt: cleanPrompt,
          negative: negative,
          references: references,
        );
        if (b64 != null && b64.isNotEmpty) {
          page.generationError = null;
          page.imageProviderUsed = settings.fallbackImageType;
          page.imageModelUsed = settings.fallbackImageModel;
          page.imageReferenceApplied =
              references.isNotEmpty &&
              supportsCharacterReference(
                type: settings.fallbackImageType,
                baseUrl: settings.fallbackImageBaseUrl,
                model: settings.fallbackImageModel,
              );
          return b64;
        }
      } catch (e) {
        page.generationError = e.toString();
        rethrow;
      }
    }

    return null;
  }

  Future<String> _callLlm({
    required AppSettings settings,
    required String systemPrompt,
    required String userPrompt,
    double? temperature,
    List<LlmImageInput> images = const [],
  }) async {
    if (settings.llmType == 'gemini') {
      final base = settings.llmBaseUrl.replaceAll(RegExp(r'/v1(beta)?/?$'), '');
      final url = '$base/v1beta/models/${settings.llmModel}:generateContent';
      final resp = await _dio.post(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': settings.llmApiKey,
          },
        ),
        data: {
          'contents': [
            {
              'role': 'user',
              'parts': [
                for (final image in images)
                  {
                    'inlineData': {'mimeType': image.mimeType, 'data': image.base64},
                  },
                {'text': userPrompt},
              ],
            },
          ],
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'generationConfig': {'temperature': temperature ?? 0.3},
        },
      );
      final cands = resp.data['candidates'] as List? ?? [];
      if (cands.isEmpty) throw Exception('Gemini 未返回内容');
      final parts = cands[0]['content']['parts'] as List? ?? [];
      return parts.map((p) => p['text'] ?? '').join();
    } else if (settings.llmType == 'anthropic') {
      final base = settings.llmBaseUrl.endsWith('/')
          ? settings.llmBaseUrl.substring(0, settings.llmBaseUrl.length - 1)
          : settings.llmBaseUrl;
      final url = '$base/v1/messages';
      final resp = await _dio.post(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': settings.llmApiKey,
            'anthropic-version': '2023-06-01',
          },
        ),
        data: {
          'model': settings.llmModel,
          'max_tokens': 4096,
          'temperature': ?temperature,
          'system': systemPrompt,
          'messages': [
            {
              'role': 'user',
              'content': images.isEmpty
                  ? userPrompt
                  : [
                      for (final image in images)
                        {
                          'type': 'image',
                          'source': {
                            'type': 'base64',
                            'media_type': image.mimeType,
                            'data': image.base64,
                          },
                        },
                      {'type': 'text', 'text': userPrompt},
                    ],
            },
          ],
        },
      );
      final content = resp.data['content'] as List? ?? [];
      if (content.isEmpty) throw Exception('Anthropic Claude 接口未返回内容');
      final textParts = content
          .where((c) => c['type'] == 'text')
          .map((c) => c['text'] ?? '')
          .toList();
      return textParts.join();
    } else {
      // OpenAI 兼容协议
      final base = settings.llmBaseUrl.endsWith('/v1')
          ? settings.llmBaseUrl
          : '${settings.llmBaseUrl}/v1';
      final resp = await _dio.post(
        '$base/chat/completions',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${settings.llmApiKey}',
          },
        ),
        data: {
          'model': settings.llmModel,
          'temperature': ?temperature,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {
              'role': 'user',
              'content': images.isEmpty
                  ? userPrompt
                  : [
                      for (final image in images)
                        {
                          'type': 'image_url',
                          'image_url': {'url': 'data:${image.mimeType};base64,${image.base64}'},
                        },
                      {'type': 'text', 'text': userPrompt},
                    ],
            },
          ],
        },
      );
      final choices = resp.data['choices'] as List? ?? [];
      if (choices.isEmpty) throw Exception('OpenAI 接口未返回内容');
      return choices[0]['message']['content'] ?? '';
    }
  }

  Future<String?> _callImageApi({
    required String type,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required String negative,
    List<_ImageReference> references = const [],
  }) async {
    // 自动判定或按协议走 腾讯 TokenHub 混元 3.5 生图接口
    final isTokenHub =
        type == 'tokenhub' ||
        baseUrl.contains('tokenhub.tencentmaas.com') ||
        baseUrl.contains('wand/hunyuan-image') ||
        model.toLowerCase().contains('hy-image');

    if (isTokenHub) {
      String targetUrl = baseUrl.trim();
      if (!targetUrl.contains('v35-generation')) {
        final clean = targetUrl.endsWith('/')
            ? targetUrl.substring(0, targetUrl.length - 1)
            : targetUrl;
        if (clean.endsWith('/v1')) {
          targetUrl = '$clean/wand/hunyuan-image/v35-generation';
        } else {
          targetUrl = '$clean/v1/wand/hunyuan-image/v35-generation';
        }
      }

      final sessionId = 'bookbuddy-${DateTime.now().millisecondsSinceEpoch}';
      final List<Map<String, dynamic>> contentList = [
        {'type': 'text', 'text': prompt},
      ];

      // 每张参考图对应一个明确的角色，避免多角色参考图身份混淆。
      for (final reference in references) {
        contentList.add({
          'type': 'text',
          'text': reference.isPhoto
              ? '以下参考图是${sanitizePrompt(reference.name)}的真实玩具或物件照片。$_photoGuidance'
              : '以下参考图是${sanitizePrompt(reference.name)}的定妆照，仅参考此角色的外貌与服装，不复制姿势和朝向。',
        });
        contentList.add({
          'type': 'image_url',
          'image_url': {'url': _referenceDataUrl(reference.base64)},
        });
      }

      final resp = await _dio.post(
        targetUrl,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
        ),
        data: {
          'model': model.isNotEmpty ? model : 'hy-image-v3.5-preview',
          'session': sessionId,
          'messages': [
            {'role': 'user', 'content': contentList},
          ],
        },
      );

      final imgResult = await _extractImageFromResponse(resp.data);
      if (imgResult != null) {
        return imgResult;
      }
      throw Exception('腾讯 TokenHub 接口已响应但未提取到有效图片数据: ${resp.data}');
    }

    if (type == 'gemini') {
      final base = baseUrl.replaceAll(RegExp(r'/v1(beta)?/?$'), '');
      if (model.toLowerCase().contains('imagen')) {
        final url = '$base/v1beta/models/$model:predict';
        final resp = await _dio.post(
          url,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
          ),
          data: {
            'instances': [
              {'prompt': prompt},
            ],
            'parameters': {'sampleCount': 1, 'aspectRatio': '16:9'},
          },
        );
        final preds = resp.data['predictions'] as List? ?? [];
        if (preds.isNotEmpty && preds[0]['bytesBase64Encoded'] != null) {
          return preds[0]['bytesBase64Encoded'];
        }
      } else {
        // 多模态生图 generateContent (支持注入参考图锁定主角外貌)
        final url = '$base/v1beta/models/$model:generateContent';
        final List<Map<String, dynamic>> parts = [];

        for (final reference in references) {
          parts.add({
            'inlineData': {
              'mimeType': _referenceMimeType(reference.base64),
              'data': _rawBase64(reference.base64),
            },
          });
          parts.add({
            'text': reference.isPhoto
                ? '上一张图片是${sanitizePrompt(reference.name)}的真实玩具或物件照片。$_photoGuidance'
                : '上一张图片是${sanitizePrompt(reference.name)}的定妆照。只将其用于此角色的外貌和默认服装，不复制背景、姿势或朝向。',
          });
        }
        parts.add({'text': prompt});

        final resp = await _dio.post(
          url,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
          ),
          data: {
            'contents': [
              {'parts': parts},
            ],
            'generationConfig': {
              'responseModalities': ['IMAGE', 'TEXT'],
            },
            'safetySettings': [
              {
                'category': 'HARM_CATEGORY_HARASSMENT',
                'threshold': 'BLOCK_NONE',
              },
              {
                'category': 'HARM_CATEGORY_HATE_SPEECH',
                'threshold': 'BLOCK_NONE',
              },
              {
                'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
                'threshold': 'BLOCK_NONE',
              },
              {
                'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
                'threshold': 'BLOCK_NONE',
              },
              {
                'category': 'HARM_CATEGORY_CIVIC_INTEGRITY',
                'threshold': 'BLOCK_NONE',
              },
            ],
          },
        );
        final cands = resp.data['candidates'] as List? ?? [];
        if (cands.isNotEmpty) {
          final finishReason = cands[0]['finishReason'];
          if (finishReason == 'PROHIBITED_CONTENT') {
            throw Exception(
              '提示词触发了上游 AI 服务商的内容安全过滤 (PROHIBITED_CONTENT)，请微调提示词规避敏感人物/动作',
            );
          }
          final candParts = cands[0]['content']?['parts'] as List? ?? [];
          for (var p in candParts) {
            if (p['inlineData'] != null && p['inlineData']['data'] != null) {
              return p['inlineData']['data'];
            }
          }
        }
        final promptFeedback = resp.data['promptFeedback'];
        if (promptFeedback != null && promptFeedback['blockReason'] != null) {
          throw Exception('请求被上游安全策略拦截: ${promptFeedback['blockReason']}');
        }
      }
    } else {
      // OpenAI 规范生图 (智谱 GLM CogView / 腾讯 TokenHub / DALL-E 3 / 自建兼容网关)
      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

      String imgUrl;
      if (cleanBase.contains('bigmodel.cn')) {
        // 智谱官方开放平台：无论输入是域名根目录还是 /v4，统一自动规范化为 /api/paas/v4/images/generations
        imgUrl = cleanBase.endsWith('/images/generations')
            ? cleanBase
            : (cleanBase.endsWith('/v4')
                  ? '$cleanBase/images/generations'
                  : 'https://open.bigmodel.cn/api/paas/v4/images/generations');
      } else {
        imgUrl = cleanBase.endsWith('/images/generations')
            ? cleanBase
            : (cleanBase.endsWith('/v1') || cleanBase.endsWith('/v4')
                  ? '$cleanBase/images/generations'
                  : '$cleanBase/v1/images/generations');
      }

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      final Map<String, dynamic> requestData = {
        'model': model,
        'prompt': prompt,
      };

      // 针对智谱 GLM 生图各版本精确适配分辨率
      final lowerModel = model.toLowerCase();
      if (lowerModel.contains('glm-image')) {
        requestData['size'] = '1280x1280';
      } else if (lowerModel.contains('cogview-3')) {
        // CogView-3 系列仅支持 1024x1024，不可乱填 1280x1280 避免触发 1214 尺寸报错
        requestData['size'] = '1024x1024';
      } else if (lowerModel.contains('cogview-4') ||
          baseUrl.contains('bigmodel.cn')) {
        requestData['size'] = '1280x1280';
      }

      // 1. 优先尝试标准生图接口 /images/generations (智谱 GLM, DALL-E, 腾讯聚合均遵循此标准)
      try {
        final resp = await _dio.post(
          imgUrl,
          options: Options(headers: headers),
          data: requestData,
        );

        final res = await _extractImageFromResponse(resp.data);
        if (res != null) return res;
      } on DioException catch (dioErr) {
        final code = dioErr.response?.statusCode;
        // 仅在明确为 404 (端点未找到) 或 405 (Method Not Allowed) 时，才降级尝试 /chat/completions
        if (code == 404 || code == 405) {
          // 继续尝试下游聊天降级
        } else {
          // 400 (敏感词过滤/参数非法)、401 (Key无效)、402 (余额不足)、429 (限流) 均为明确业务错误，提取后明确抛出！
          final errorMsg = _extractErrorMessage(dioErr);
          throw Exception(errorMsg);
        }
      } catch (e) {
        if (e is! DioException) rethrow;
      }

      // 2. 降级尝试聊天补全多模态生图 (适用于某些将生图封装为 chat/completions 的网关)
      final chatUrl = cleanBase.endsWith('/chat/completions')
          ? cleanBase
          : (cleanBase.endsWith('/v1') || cleanBase.endsWith('/v4')
                ? '$cleanBase/chat/completions'
                : '$cleanBase/v1/chat/completions');

      dynamic content;
      if (references.isNotEmpty) {
        content = [
          {'type': 'text', 'text': prompt},
          for (final reference in references) ...[
            {
              'type': 'text',
              'text': reference.isPhoto
                  ? '以下图片是${sanitizePrompt(reference.name)}的真实玩具或物件照片。$_photoGuidance'
                  : '以下图片是${sanitizePrompt(reference.name)}的定妆照。',
            },
            {
              'type': 'image_url',
              'image_url': {'url': _referenceDataUrl(reference.base64)},
            },
          ],
        ];
      } else {
        content = prompt;
      }

      final resp = await _dio.post(
        chatUrl,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
        ),
        data: {
          'model': model,
          'messages': [
            {'role': 'user', 'content': content},
          ],
        },
      );

      final chatRes = await _extractImageFromResponse(resp.data);
      if (chatRes != null) return chatRes;
    }
    return null;
  }

  String _rawBase64(String value) => value.startsWith('data:')
      ? value.substring(value.indexOf(',') + 1)
      : value;

  String _referenceDataUrl(String value) => value.startsWith('data:')
      ? value
      : 'data:${_referenceMimeType(value)};base64,$value';

  String _referenceMimeType(String value) {
    if (value.startsWith('data:')) {
      return value.substring(5, value.indexOf(';'));
    }
    try {
      final bytes = base64Decode(value);
      if (bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47) {
        return 'image/png';
      }
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45) {
        return 'image/webp';
      }
    } catch (_) {}
    return 'image/jpeg';
  }

  /// 从上游各种异构 JSON 响应（choices、delta、assembled_history、data、images、url）中稳健提取图片并转为 Base64
  Future<String?> _extractImageFromResponse(dynamic data) async {
    if (data == null) return null;

    // 1. 腾讯 TokenHub 混元 3.5: choices[].delta.image.url
    if (data is Map && data['choices'] is List) {
      final choices = data['choices'] as List;
      for (var choice in choices) {
        if (choice is Map) {
          // delta.image.url
          final delta = choice['delta'];
          if (delta is Map) {
            final imgObj = delta['image'];
            if (imgObj is Map && imgObj['url'] != null) {
              final u = imgObj['url'].toString();
              if (u.isNotEmpty) return await _downloadImageAsBase64(u);
            }
            if (delta['image_url'] != null) {
              final u = delta['image_url'] is Map
                  ? delta['image_url']['url']?.toString()
                  : delta['image_url'].toString();
              if (u != null && u.isNotEmpty)
                return await _downloadImageAsBase64(u);
            }
          }

          // message.images 或 message.image_url
          final msg = choice['message'];
          if (msg is Map) {
            if (msg['images'] is List) {
              final imgs = msg['images'] as List;
              for (var img in imgs) {
                String? u;
                if (img is Map) {
                  u =
                      img['url']?.toString() ??
                      img['image_url']?['url']?.toString();
                } else if (img is String) {
                  u = img;
                }
                if (u != null && u.isNotEmpty)
                  return await _downloadImageAsBase64(u);
              }
            }
            if (msg['image_url'] != null) {
              final u = msg['image_url'] is Map
                  ? msg['image_url']['url']?.toString()
                  : msg['image_url'].toString();
              if (u != null && u.isNotEmpty)
                return await _downloadImageAsBase64(u);
            }

            // message.content 中的纯 URL 或 Markdown 图片语法
            final textContent = msg['content']?.toString() ?? '';
            if (textContent.startsWith('http')) {
              return await _downloadImageAsBase64(textContent.trim());
            }
            final mdImgMatch = RegExp(r'!\[.*?\]\((https?://[^\s\)]+)\)')
                .firstMatch(textContent);
            if (mdImgMatch != null) {
              return await _downloadImageAsBase64(mdImgMatch.group(1)!);
            }
            final rawUrlMatch = RegExp(
              r'https?://[^\s"]+\.(?:png|jpg|jpeg|webp)',
            ).firstMatch(textContent);
            if (rawUrlMatch != null) {
              return await _downloadImageAsBase64(rawUrlMatch.group(0)!);
            }
          }
        }
      }
    }

    // 2. 腾讯 TokenHub 混元 3.5 工具历史链: assembled_history[].content[].image_url.url
    if (data is Map && data['assembled_history'] is List) {
      final history = data['assembled_history'] as List;
      for (var item in history) {
        if (item is Map && item['content'] is List) {
          final contents = item['content'] as List;
          for (var c in contents) {
            if (c is Map) {
              if (c['image_url'] != null) {
                final u = c['image_url'] is Map
                    ? c['image_url']['url']?.toString()
                    : c['image_url'].toString();
                if (u != null && u.isNotEmpty)
                  return await _downloadImageAsBase64(u);
              }
              if (c['url'] != null) {
                final u = c['url'].toString();
                if (u.isNotEmpty) return await _downloadImageAsBase64(u);
              }
            }
          }
        }
      }
    }

    // 3. 标准 OpenAI / 智谱 GLM 风格: data[].b64_json 或 data[].url
    if (data is Map && data['data'] is List) {
      final list = data['data'] as List;
      for (var item in list) {
        if (item is Map) {
          if (item['b64_json'] != null &&
              item['b64_json'].toString().isNotEmpty) {
            return item['b64_json'].toString();
          }
          final u = item['url']?.toString();
          if (u != null && u.isNotEmpty) {
            return await _downloadImageAsBase64(u);
          }
        }
      }
    }

    // 4. images 列表风格
    if (data is Map && data['images'] is List) {
      final imgs = data['images'] as List;
      for (var img in imgs) {
        String? u;
        if (img is Map) {
          u = img['url']?.toString() ?? img['image_url']?['url']?.toString();
        } else if (img is String) {
          u = img;
        }
        if (u != null && u.isNotEmpty) {
          return await _downloadImageAsBase64(u);
        }
      }
    }

    // 5. 顶层直接包含 url 字段
    if (data is Map && data['url'] != null) {
      final u = data['url'].toString();
      if (u.isNotEmpty) return await _downloadImageAsBase64(u);
    }

    // 6. 深度递归兜底扫描：探测任意包含图片 URL 或 Base64 的叶子字段
    final recursiveUrl = _findFirstImageUrl(data);
    if (recursiveUrl != null) {
      return await _downloadImageAsBase64(recursiveUrl);
    }

    return null;
  }

  /// 递归深度扫描未知嵌套 JSON 中的有效图片下载链接
  String? _findFirstImageUrl(dynamic node) {
    if (node is Map) {
      for (var entry in node.entries) {
        final val = entry.value;
        if (val is String &&
            val.startsWith('http') &&
            (val.contains('.png') ||
                val.contains('.jpg') ||
                val.contains('.jpeg') ||
                val.contains('.webp') ||
                val.contains('cos.') ||
                val.contains('myqcloud.com') ||
                val.contains('image'))) {
          return val;
        }
        final found = _findFirstImageUrl(val);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (var item in node) {
        final found = _findFirstImageUrl(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// 远程图片下载并转换为本地 Base64 编码
  Future<String> _downloadImageAsBase64(String imageUrl) async {
    if (imageUrl.startsWith('data:image')) {
      return imageUrl.split(',').last;
    }
    final response = await _dio.get<List<int>>(
      imageUrl,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    if (response.data != null && response.data!.isNotEmpty) {
      return base64Encode(response.data!);
    }
    throw Exception('下载上游生成的图片失败，数据为空');
  }

  /// 提取第三方 AI 平台详细的错误说明（如智谱 1301 敏感词、1214 密钥错误、余额不足等）
  String _extractErrorMessage(DioException dioErr) {
    final data = dioErr.response?.data;
    if (data is Map) {
      if (data['error'] is Map) {
        final err = data['error'] as Map;
        final msg = err['message'] ?? err['msg'];
        final code = err['code'];
        if (msg != null && msg.toString().isNotEmpty) {
          return code != null ? '上游接口报错 [$code]: $msg' : '上游接口报错: $msg';
        }
      }
      final msg = data['message'] ?? data['msg'];
      if (msg != null && msg.toString().isNotEmpty) {
        final code = data['code'];
        return code != null ? '上游接口报错 [$code]: $msg' : '上游接口报错: $msg';
      }
    }
    final status = dioErr.response?.statusCode;
    if (status != null) {
      if (status == 401) return 'API Key 无效或未授权 (401)，请检查填写的密钥';
      if (status == 402 || status == 429)
        return '接口余额不足或请求频率超限 (429/402)，请检查账户额度';
      if (status == 400) return '接口请求参数错误或提示词触发安全风控拦截 (400)';
    }
    return dioErr.message ?? dioErr.toString();
  }

  dynamic _extractJson(String raw) {
    var str = raw.trim();
    if (str.startsWith('```')) {
      final lines = str.split('\n');
      if (lines.length > 2) {
        str = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    try {
      return jsonDecode(str);
    } catch (_) {
      final start = str.indexOf('{');
      final end = str.lastIndexOf('}');
      if (start != -1 && end > start) {
        try {
          return jsonDecode(str.substring(start, end + 1));
        } catch (_) {
          // 仍不是合法 JSON：交给调用方按「格式不正确」处理，不把 Dart 的原始报错抛给用户。
        }
      }
    }
    return {};
  }

  @visibleForTesting
  Future<String?> extractImageFromResponseForTesting(dynamic data) =>
      _extractImageFromResponse(data);
}
