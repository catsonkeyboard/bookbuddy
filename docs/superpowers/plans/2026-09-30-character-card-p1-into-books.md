# 角色卡 P1：融入绘本 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新建绘本时可以选最多 3 张角色卡作为固定主角，大模型分镜必须原样使用它们，生图沿用卡片定妆图，缺画风的定妆图在审核页补画并写回卡片；绘本记录使用了哪些卡，角色库、书架和阅读器能看到这层关系。

**Architecture:** 在现有「故事文本 → 分镜 → 审核 → 逐页生图」管线上加一条注入链：创建页读取所选卡片与当前画风的定妆图，组成 `PinnedCharacter` 传给引擎；引擎在系统提示词末尾追加「固定角色」段落，解析后用四条对账规则把卡片投影为书内 `BookCharacter` 快照（卡片是唯一真相源）；审核页的定妆照流程不变，只在卡片角色生成定妆照后多做一次「写回角色卡 + 清图片缓存」，并在首次落盘时更新卡片的 `lastUsedAt`。`PictureBook` 只新增 `characterCardIds` 一个字段；旧书不受影响。

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4，`dio`、`path_provider`、`shared_preferences`、`wakelock_plus`（均为已有依赖），`flutter_test`。本期**不新增任何依赖**。

**Spec:** `docs/superpowers/specs/2026-09-28-character-card-design.md`（第 1 节决策 1–3、3.2、3.3、5.4、6.1 书架角标、6.2「出演 N 本」、6.4、6.5、6.6、第 8 节对账失败一行、第 9 节、第 10 节 P1）。P0 已合并到 `main`（提交 5385a62 及之前），本计划从 `main` 分支。

## Global Constraints

- Flutter SDK 绝对路径 `$HOME/development/flutter/bin/flutter`；本期无需 `pub get`，不新增依赖。
- 每个任务结束前运行 `$HOME/development/flutter/bin/flutter analyze` 与对应测试文件；analyze 的标准是**按文件核对**：涉及的 `lib/` 与 `test/` 文件不得出现任何新行（仓库原有的 `main.dart` `withOpacity` 弃用提示不算）。
- 模型字段增删必须同步构造函数、`toJson()`、`fromJson()` 与单元测试；旧 JSON 缺键必须回退默认值。
- 常量 `kMaxCharacterCardsPerBook = 3`（`lib/models/character_card.dart`）：创建页与引擎都以它为上限，超出引擎抛 `ArgumentError`。
- 卡片是唯一真相源：解析后对账四条规则（覆盖同 id → 合并同名 → 按名字补漏 → 无出场抛 `StateError`），错误文案固定为 `角色卡「<名字>」没有出现在任何分镜中。请在故事里写到它，或取消选择该角色卡。`
- 书内角色是卡片的**快照**（`CharacterCard.toBookCharacter()` 投影），编辑卡片不回溯旧书；审核页内编辑卡片来源角色只改书内快照。
- 卡片来源角色的 id 就是卡片 id（`card_` 前缀），书内自增角色仍是 `c1/c2`。
- 定妆图写回只走 `CharacterStorageService.saveAnchor`（按 `_mutate` 读改写，不整卡覆盖），写回后必须 `FileImage(...).evict()`；`lastUsedAt` 只走新增的 `touchLastUsed`。写回失败只提示，不阻断绘本生成。
- 界面文案使用简体中文，风格与现有页面一致（金色 `Color(0xFFD8A24A)`）。
- widget 测试里凡是由控件回调触发的文件 IO，都用 `runIo(tester, body, until: ...)`（交替 `runAsync` / `pump`，带完成判定，见 `test/character_library_screen_test.dart:21-36`）；断言优先用同步文件 API。
- 提交信息遵循 Conventional Commits，末尾附 `Co-Authored-By: Claude <模型名> <noreply@anthropic.com>`（任意 Claude 型号均可）。
- 手动验收（spec §10 P1）留给用户，实现者不执行。

---

## 文件结构

| 文件 | 改动 |
|---|---|
| `lib/models/book.dart` | `PictureBook.characterCardIds` |
| `lib/models/character_card.dart` | `toBookCharacter` 空服装按类型投影为明确描述 |
| `lib/services/character_storage_service.dart` | `touchLastUsed(cardIds)` |
| `lib/services/book_engine_service.dart` | `PinnedCharacter`；`createStoryboardDraft(pinnedCharacters:)`；提示词注入；`_reconcilePinned` |
| `lib/screens/storyboard_review_screen.dart` | 新参数；`characterCardIds` 入草稿；定妆照写回；`lastUsedAt`；「角色卡」标签与编辑提示；可注入依赖 |
| `lib/screens/create_book_screen.dart` | 角色卡选择区（≤3）、画风不匹配提示、组装 `PinnedCharacter`、对账错误提示、传参到审核页；可注入依赖 |
| `lib/screens/character_library_screen.dart` | 副标题加「出演 N 本」 |
| `lib/main.dart` | 书架条目角标 |
| `lib/screens/book_reader_screen.dart` | 角色面板「角色卡」标签 |
| `AGENTS.md` | §2.1 功能全景补一行 |
| `test/character_card_test.dart` | 追加：空服装投影、`PictureBook.characterCardIds` |
| `test/character_storage_service_test.dart` | 追加：`touchLastUsed` |
| `test/book_engine_pinned_test.dart`（新建） | 提示词注入、对账四规则、上限 |
| `test/storyboard_review_pinned_test.dart`（新建） | 标签与提示、定妆照写回 |
| `test/create_book_screen_test.dart`（新建） | 选卡上限、空库入口、画风提示 |
| `test/character_library_screen_test.dart` | 更新副标题断言，新增「出演 N 本」 |

---

### Task 0: 建立功能分支

**Files:** 无

- [ ] **Step 1: 确认在 main 且工作区干净，建分支**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git checkout main && git status --short && git checkout -b feat/character-cards-p1
```

Expected: `git status --short` 无输出；切换到 `feat/character-cards-p1`。

- [ ] **Step 2: 提交本计划**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add docs/superpowers/plans/2026-09-30-character-card-p1-into-books.md && git commit -m "docs: add character card P1 implementation plan

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 1: 模型：`PictureBook.characterCardIds` 与空服装投影

**Files:**
- Modify: `lib/models/book.dart:1-46`
- Modify: `lib/models/character_card.dart:57-71`（`toBookCharacter`）
- Test: `test/character_card_test.dart`（追加）

**Interfaces:**
- Consumes: 现有 `PictureBook`、`CharacterCard`、`CharacterKind`
- Produces:
  - `PictureBook.characterCardIds: List<String>`（可变，默认 `[]`；构造参数 `List<String>? characterCardIds`）
  - `CharacterCard.toBookCharacter({String? referenceImageBase64})` 在 `defaultOutfit` 为空时返回的 `BookCharacter.defaultOutfit`：动物 `自然毛皮或羽毛，不穿人类服饰`；物件 `无服装，保持物件本来的外观`；人类 `简洁的日常服装`。非空时原样。物件外貌后缀规则不变。

- [ ] **Step 1: 追加失败的测试**

在 `test/character_card_test.dart` 的 import 区加入 `import 'package:bookbuddy/models/book.dart';`，并把文件末尾 `main()` 的收尾 `}` 替换为：

```dart
  test('空服装按类型投影为明确的服装描述', () {
    final animal = CharacterCard(
      id: 'card_a',
      name: '豆豆',
      kind: CharacterKind.animal,
      appearance: '绿色毛绒恐龙',
    );
    expect(animal.toBookCharacter().defaultOutfit, '自然毛皮或羽毛，不穿人类服饰');

    final object = CharacterCard(
      id: 'card_o',
      name: '小满',
      kind: CharacterKind.object,
      appearance: '灰色鹅卵石',
    );
    expect(object.toBookCharacter().defaultOutfit, '无服装，保持物件本来的外观');
    expect(object.toBookCharacter().appearance, endsWith(kObjectAppearanceSuffix));

    final human = CharacterCard(
      id: 'card_h',
      name: '小明',
      kind: CharacterKind.human,
      appearance: '短黑发男孩',
    );
    expect(human.toBookCharacter().defaultOutfit, '简洁的日常服装');

    animal.defaultOutfit = '红色小围巾';
    expect(animal.toBookCharacter().defaultOutfit, '红色小围巾');
  });

  test('PictureBook.characterCardIds 往返保留，旧 JSON 缺键回退为空', () {
    final book = PictureBook(
      id: 'book-1',
      title: '豆豆的雨天',
      styleId: 'watercolor',
      styleName: '水彩童话',
      pages: [BookPageItem(pageIndex: 0, text: '豆豆出门了。')],
      createdAt: DateTime.utc(2026, 9, 30),
      characterCardIds: ['card_ab12cd34', 'card_ef56gh78'],
    );
    final restored = PictureBook.fromJson(book.toJson());
    expect(restored.characterCardIds, ['card_ab12cd34', 'card_ef56gh78']);

    final legacy = PictureBook.fromJson(book.toJson()..remove('characterCardIds'));
    expect(legacy.characterCardIds, isEmpty);

    final fresh = PictureBook(
      id: 'book-2',
      title: '无卡',
      styleId: 'watercolor',
      styleName: '水彩童话',
      pages: const [],
      createdAt: DateTime.utc(2026, 9, 30),
    );
    expect(fresh.characterCardIds, isEmpty);
    fresh.characterCardIds.add('card_x');
    expect(fresh.characterCardIds, ['card_x']);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_card_test.dart`

Expected: 编译失败，`characterCardIds` 不是 `PictureBook` 的命名参数。

- [ ] **Step 3: 实现模型改动**

`lib/models/book.dart`：在 `String? protagonistRefImage;`（第 9 行）之后加字段：

```dart
  List<String> characterCardIds; // 本书使用的角色卡 id（书内角色仍是快照，卡片编辑不回溯）
```

构造函数（第 11–20 行）改为：

```dart
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
```

`toJson()` 在 `'protagonistRefImage': protagonistRefImage,` 之后加：

```dart
    'characterCardIds': characterCardIds,
```

`fromJson` 在 `protagonistRefImage: json['protagonistRefImage'],` 之后加：

```dart
    characterCardIds: (json['characterCardIds'] as List<dynamic>? ?? [])
        .map((id) => id.toString())
        .toList(),
```

`lib/models/character_card.dart`：把 `toBookCharacter` 整体替换为：

```dart
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
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_card_test.dart test/character_consistency_test.dart test/book_storage_service_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "lib/models/(book|character_card)\.dart|test/character_card_test" || echo "analyze: no lines for touched files"`

Expected: 全部通过（`character_card_test` 从 7 条变 9 条）；grep 无输出。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/models/book.dart lib/models/character_card.dart test/character_card_test.dart && git commit -m "feat(character-card): record card ids on books and project empty outfits explicitly

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: 存储：`touchLastUsed`

**Files:**
- Modify: `lib/services/character_storage_service.dart`（在 `clearAnchors` 之后追加）
- Test: `test/character_storage_service_test.dart`（追加）

**Interfaces:**
- Produces: `Future<void> touchLastUsed(Iterable<String> cardIds)` — 只把这些卡片的 `lastUsedAt` 设为当前时间；未知或非法 id 忽略；集合为空时不写盘、不触发通知。

- [ ] **Step 1: 追加失败的测试**

把 `test/character_storage_service_test.dart` 末尾 `main()` 的收尾 `}` 替换为：

```dart
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
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_storage_service_test.dart`

Expected: 编译失败，`touchLastUsed` 未定义。

- [ ] **Step 3: 实现**

在 `lib/services/character_storage_service.dart` 的 `clearAnchors` 方法之后追加：

```dart
  /// 把这些卡片的 lastUsedAt 更新为当前时间；只改这一字段，不覆盖其它内容。
  /// 未知或非法 id 忽略；集合为空时不写盘。
  Future<void> touchLastUsed(Iterable<String> cardIds) async {
    final ids = cardIds.where(isValidId).toSet();
    if (ids.isEmpty) return;
    final now = DateTime.now();
    await _mutate((cards) {
      for (final card in cards) {
        if (ids.contains(card.id)) card.lastUsedAt = now;
      }
    });
  }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_storage_service_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "character_storage" || echo "analyze: no lines for touched files"`

Expected: 18 tests passed；grep 无输出。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/services/character_storage_service.dart test/character_storage_service_test.dart && git commit -m "feat(character-card): add touchLastUsed to bump card usage without overwriting cards

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: 引擎：固定角色注入与对账

**Files:**
- Modify: `lib/services/book_engine_service.dart:1-20`（import 与顶部类型）、`:50-230`（`createStoryboardDraft`）
- Test: `test/book_engine_pinned_test.dart`（新建）

**Interfaces:**
- Consumes: `CharacterCard`、`CharacterKind`、`kMaxCharacterCardsPerBook`（Task 1 及 P0）
- Produces:
  - `class PinnedCharacter { final CharacterCard card; final String? anchorBase64; final String? photoBase64; const PinnedCharacter({required this.card, this.anchorBase64, this.photoBase64}); }`
  - `createStoryboardDraft({required settings, required title, required storyText, List<PinnedCharacter> pinnedCharacters = const []})`：超过 `kMaxCharacterCardsPerBook` 抛 `ArgumentError`；有固定角色时系统提示词末尾追加「【固定角色，必须原样使用】」段；解析后执行对账；对账失败抛 `StateError`。
  - 对账结果：每张卡在 `draft.characters` 中恰好一条，id 为卡片 id，字段来自 `card.toBookCharacter(referenceImageBase64: anchorBase64)`。

- [ ] **Step 1: 写失败的测试**

创建 `test/book_engine_pinned_test.dart`：

```dart
import 'dart:convert';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 伪造 OpenAI 兼容协议的分镜响应，并记录请求体。
Dio fakeLlmDio(Map<String, dynamic> storyboard, List<dynamic> sent) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        sent.add(options.data);
        handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'choices': [
                {
                  'message': {'content': jsonEncode(storyboard)},
                },
              ],
            },
          ),
        );
      },
    ),
  );

AppSettings openAiSettings() => AppSettings(
      llmType: 'openai',
      llmBaseUrl: 'https://example.test',
      llmApiKey: 'test',
      llmModel: 'test',
    );

CharacterCard dino() => CharacterCard(
      id: 'card_dino1',
      name: '豆豆',
      kind: CharacterKind.animal,
      species: '毛绒恐龙',
      appearance: '绿色毛绒身体，肚皮米白，圆圆的黑眼睛',
      defaultOutfit: '红色小围巾',
      personality: '胆子大、爱冒险',
      catchphrase: '冲啊！',
    );

Map<String, dynamic> scene({
  required String text,
  String action = '',
  List<String> ids = const [],
  Map<String, String> outfits = const {},
}) =>
    {
      'text': text,
      'action': action,
      'emotion': '',
      'composition': '',
      'characterIds': ids,
      'outfitOverrides': outfits,
    };

void main() {
  test('有固定角色时系统提示词追加固定角色段落', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [
          {
            'id': 'card_dino1',
            'name': '豆豆',
            'species': '毛绒恐龙',
            'isAnimal': true,
            'appearance': '绿色毛绒身体，肚皮米白，圆圆的黑眼睛',
            'defaultOutfit': '红色小围巾',
          },
        ],
        'groups': {},
        'scenes': [
          scene(text: '豆豆喊：冲啊！', ids: ['card_dino1']),
        ],
      }, sent),
    );
    await engine.createStoryboardDraft(
      settings: openAiSettings(),
      title: '豆豆的雨天',
      storyText: '豆豆在雨天迷路了。',
      pinnedCharacters: [PinnedCharacter(card: dino(), anchorBase64: 'anchor')],
    );
    final system = sent.single['messages'][0]['content'] as String;
    expect(system, contains('【固定角色，必须原样使用】'));
    expect(system, contains('id: card_dino1'));
    expect(system, contains('名字：豆豆'));
    expect(system, contains('口头禅：冲啊！'));
    expect(system, contains('性格：胆子大、爱冒险'));
    expect(system, contains('默认服装：红色小围巾'));
  });

  test('没有固定角色时提示词不含固定角色段落', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [],
        'groups': {},
        'scenes': [scene(text: '从前有座山。')],
      }, sent),
    );
    await engine.createStoryboardDraft(
      settings: openAiSettings(),
      title: '山',
      storyText: '从前有座山。',
    );
    final system = sent.single['messages'][0]['content'] as String;
    expect(system, isNot(contains('【固定角色，必须原样使用】')));
  });

  test('规则一：同 id 条目被卡片字段覆盖并带上定妆图', () async {
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [
          {
            'id': 'card_dino1',
            'name': '豆豆',
            'species': '蜥蜴',
            'isAnimal': true,
            'appearance': '大模型乱改的外貌',
            'defaultOutfit': '大模型乱加的帽子',
          },
        ],
        'groups': {},
        'scenes': [
          scene(text: '豆豆出发。', ids: ['card_dino1']),
        ],
      }, []),
    );
    final draft = await engine.createStoryboardDraft(
      settings: openAiSettings(),
      title: 't',
      storyText: 's',
      pinnedCharacters: [PinnedCharacter(card: dino(), anchorBase64: 'anchor-b64')],
    );
    final c = draft.characters.singleWhere((c) => c.id == 'card_dino1');
    expect(c.species, '毛绒恐龙');
    expect(c.appearance, '绿色毛绒身体，肚皮米白，圆圆的黑眼睛');
    expect(c.defaultOutfit, '红色小围巾');
    expect(c.isAnimal, isTrue);
    expect(c.referenceImageBase64, 'anchor-b64');
    expect(draft.characters, hasLength(1));
  });

  test('规则二：大模型另造的同名角色被合并到卡片 id，页面引用与换装一并改写', () async {
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [
          {
            'id': 'c1',
            'name': '豆豆',
            'species': '恐龙',
            'isAnimal': true,
            'appearance': '另一个豆豆',
            'defaultOutfit': '',
          },
          {
            'id': 'c2',
            'name': '小猫',
            'species': '猫',
            'isAnimal': true,
            'appearance': '橘猫',
            'defaultOutfit': '自然毛皮',
          },
        ],
        'groups': {},
        'scenes': [
          scene(text: '豆豆和小猫玩。', ids: ['c1', 'c2'], outfits: {'c1': '雨衣'}),
          scene(text: '小猫睡觉。', ids: ['c2']),
        ],
      }, []),
    );
    final draft = await engine.createStoryboardDraft(
      settings: openAiSettings(),
      title: 't',
      storyText: 's',
      pinnedCharacters: [PinnedCharacter(card: dino())],
    );
    expect(draft.characters.map((c) => c.id).toList(), ['card_dino1', 'c2']);
    expect(draft.characters.first.appearance, '绿色毛绒身体，肚皮米白，圆圆的黑眼睛');
    expect(draft.pages.first.characterIds, ['card_dino1', 'c2']);
    expect(draft.pages.first.outfitOverrides, {'card_dino1': '雨衣'});
    expect(draft.pages.last.characterIds, ['c2']);
  });

  test('规则三：卡片未被列入名单但名字出现在页面里时按名字补漏', () async {
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [
          {
            'id': 'c1',
            'name': '小猫',
            'species': '猫',
            'isAnimal': true,
            'appearance': '橘猫',
            'defaultOutfit': '自然毛皮',
          },
        ],
        'groups': {},
        'scenes': [
          scene(text: '小猫在等。', ids: ['c1']),
          scene(text: '这时豆豆跑来了，大喊冲啊！', action: '豆豆冲进画面', ids: ['c1']),
        ],
      }, []),
    );
    final draft = await engine.createStoryboardDraft(
      settings: openAiSettings(),
      title: 't',
      storyText: 's',
      pinnedCharacters: [PinnedCharacter(card: dino())],
    );
    expect(draft.characters.first.id, 'card_dino1');
    expect(draft.pages.first.characterIds, ['c1']);
    expect(draft.pages.last.characterIds, ['c1', 'card_dino1']);
  });

  test('规则四：卡片完全没有出场时抛出可读的 StateError', () async {
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [],
        'groups': {},
        'scenes': [scene(text: '从前有座山。')],
      }, []),
    );
    await expectLater(
      engine.createStoryboardDraft(
        settings: openAiSettings(),
        title: 't',
        storyText: 's',
        pinnedCharacters: [PinnedCharacter(card: dino())],
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          '角色卡「豆豆」没有出现在任何分镜中。请在故事里写到它，或取消选择该角色卡。',
        ),
      ),
    );
  });

  test('超过上限的角色卡在请求前就被拒绝', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeLlmDio({'scenes': []}, sent));
    final cards = List.generate(
      kMaxCharacterCardsPerBook + 1,
      (i) => PinnedCharacter(
        card: CharacterCard(id: 'card_$i', name: '角色$i', appearance: 'x'),
      ),
    );
    await expectLater(
      engine.createStoryboardDraft(
        settings: openAiSettings(),
        title: 't',
        storyText: 's',
        pinnedCharacters: cards,
      ),
      throwsArgumentError,
    );
    expect(sent, isEmpty);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/book_engine_pinned_test.dart`

Expected: 编译失败，`PinnedCharacter` 与命名参数 `pinnedCharacters` 不存在。

- [ ] **Step 3: 实现引擎改动**

`lib/services/book_engine_service.dart` 的 import 区在 `import '../models/book.dart';` 之后加：

```dart
import '../models/character_card.dart';
```

在 `class _ImageReference` 之前加：

```dart
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
```

`createStoryboardDraft` 的签名改为：

```dart
  Future<StoryboardDraft> createStoryboardDraft({
    required AppSettings settings,
    required String title,
    required String storyText,
    List<PinnedCharacter> pinnedCharacters = const [],
  }) async {
    if (pinnedCharacters.length > kMaxCharacterCardsPerBook) {
      throw ArgumentError('最多只能选择 $kMaxCharacterCardsPerBook 张角色卡');
    }
```

原来的 `final systemPrompt = '''` … `''';` 保持不变。紧接其后加一行，并把下面 `_callLlm(...)` 调用里的 `systemPrompt: systemPrompt` 改为 `systemPrompt: fullSystemPrompt`（用插值而不是 `+`，避免触发 `prefer_interpolation_to_compose_strings`）：

```dart
    final fullSystemPrompt = pinnedCharacters.isEmpty
        ? systemPrompt
        : '$systemPrompt${_pinnedPromptBlock(pinnedCharacters)}';
```

方法末尾原来的 `return StoryboardDraft(characters: characters, pages: pages);` 改为：

```dart
    _reconcilePinned(
      characters: characters,
      pages: pages,
      pinned: pinnedCharacters,
    );
    return StoryboardDraft(characters: characters, pages: pages);
```

在 `createStoryboardDraft` 方法之后、`buildDefaultPrompt` 之前加两个私有方法：

```dart
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
    return '''

【固定角色，必须原样使用】
以下角色已经存在，必须使用给定的 id、名字、物种、外貌与默认服装，不得改名、不得重新设计外貌、不得更换物种：
$lines
要求：
1. characters 中必须包含上述每个角色，id 原样输出（例如 ${pinned.first.card.id}）；可以另外新增配角（用 c1、c2 编号）。
2. 故事需要主角时优先使用上述角色；每个固定角色至少出现在一个镜头的 characterIds 中。
3. 口头禅要自然地出现在该角色至少一页的 text 里；性格要体现在 action 与 emotion 的描写中。
''';
  }

  /// 卡片是唯一真相源：覆盖同 id 条目 → 合并大模型另造的同名角色 → 按名字补漏 → 无出场则报错。
  void _reconcilePinned({
    required List<BookCharacter> characters,
    required List<BookPageItem> pages,
    required List<PinnedCharacter> pinned,
  }) {
    if (pinned.isEmpty) return;
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
          .where((c) => c.id != card.id && c.name.trim() == name)
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
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/book_engine_pinned_test.dart test/character_consistency_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "book_engine" || echo "analyze: no lines for touched files"`

Expected: 7 + 原有用例全部通过；grep 无输出。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/services/book_engine_service.dart test/book_engine_pinned_test.dart && git commit -m "feat(character-card): pin character cards into storyboard generation and reconcile the result

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: 分镜审核页：卡片来源角色、定妆照写回、使用时间

**Files:**
- Modify: `lib/screens/storyboard_review_screen.dart`（构造参数 `:13-31`；state 字段与 `initState` `:33-58`；`_currentDraft` `:67-76`；`_editCharacter` `:78-156`；`_prepareCharacterReferences` `:174-232`；`_startDrawIllustrations` 首次落盘 `:485-487`；角色卡片名字 `:795-800`）
- Test: `test/storyboard_review_pinned_test.dart`（新建）

**Interfaces:**
- Consumes: `PinnedCharacter`（Task 3）、`PictureBook.characterCardIds`（Task 1）、`CharacterStorageService.saveAnchor / imageFile / touchLastUsed`（P0 与 Task 2）、`BookStorageService(booksDirectory:)`
- Produces:
  - `StoryboardReviewScreen({..., List<PinnedCharacter> pinnedCharacters = const [], List<String> characterCardIds = const [], CharacterStorageService? characterStorage, BookEngineService? engine, BookStorageService? bookStorage})`
  - 草稿 `PictureBook.characterCardIds` 为传入列表的副本；卡片角色定妆照生成后写回 `saveAnchor(cardId, style.id, image)` 并 `FileImage.evict()`；首次落盘后 `touchLastUsed(characterCardIds)` 恰好一次。
  - 卡片来源角色在角色卡片上显示「角色卡」标签；编辑对话框标题带「（来自角色卡）」，正文第一行「此处修改仅影响本书，不会改动角色卡。」。

说明：`pinnedCharacters` 本任务只接收并保存（P3 拍照阶段用它取照片），当前不读取其内容；用它判断卡片来源统一用 `characterCardIds`。审核页目前没有「删除角色」功能，spec 6.5 关于删除时同步移除 id 的要求无需实现。

- [ ] **Step 1: 写失败的测试**

创建 `test/storyboard_review_pinned_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/storyboard_review_screen.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:bookbuddy/services/book_storage_service.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在真实事件循环里执行会产生文件 IO / 网络的操作，然后交替「让出真实时间片」与
/// 「冲刷一次 FakeAsync 微任务队列」，直到 [until] 成立或达到 [maxRounds]。
/// 必须交替两个独立调用而不能嵌套在同一个 runAsync 里：每一跳 IO 完成后的延续
/// 都排在测试时钟的微任务队列上，只有 pump 一次才会被取出执行。
Future<void> runIo(
  WidgetTester tester,
  Future<void> Function() body, {
  bool Function()? until,
  int maxRounds = 60,
}) async {
  await tester.runAsync(body);
  for (var i = 0; i < maxRounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    if (until != null && until()) break;
  }
  await tester.pumpAndSettle();
}

const watercolor = BookStyle(
  id: 'watercolor',
  name: '水彩童话',
  desc: '',
  prefix: '水彩',
  negative: '',
);

CharacterCard dino() => CharacterCard(
      id: 'card_dino1',
      name: '豆豆',
      kind: CharacterKind.animal,
      species: '毛绒恐龙',
      appearance: '绿色毛绒恐龙',
      defaultOutfit: '红色小围巾',
    );

Dio fakeGeminiImageDio(String base64Png) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response(
          requestOptions: options,
          data: {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'inlineData': {'mimeType': 'image/png', 'data': base64Png},
                    },
                  ],
                },
              },
            ],
          },
        ),
      ),
    ),
  );

void main() {
  late Directory charDir;
  late Directory bookDir;
  late CharacterStorageService charStorage;
  late BookStorageService bookStorage;
  final pngBase64 = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'bookbuddy_books_migrated_to_files': true,
    });
    charDir = Directory.systemTemp.createTempSync('bookbuddy-review-chars-');
    bookDir = Directory.systemTemp.createTempSync('bookbuddy-review-books-');
    charStorage = CharacterStorageService(directory: charDir);
    bookStorage = BookStorageService(booksDirectory: bookDir);
  });

  tearDown(() {
    for (final dir in [charDir, bookDir]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  Future<void> pumpReview(
    WidgetTester tester, {
    required AppSettings settings,
    BookEngineService? engine,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: StoryboardReviewScreen(
          title: '豆豆的雨天',
          style: watercolor,
          initialPages: [
            BookPageItem(pageIndex: 0, text: '豆豆出发了。', characterIds: ['card_dino1']),
          ],
          initialCharacters: [dino().toBookCharacter()],
          settings: settings,
          characterCardIds: const ['card_dino1'],
          characterStorage: charStorage,
          bookStorage: bookStorage,
          engine: engine,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('卡片来源角色显示「角色卡」标签，编辑对话框提示只影响本书', (tester) async {
    await pumpReview(tester, settings: AppSettings());
    expect(find.text('角色卡'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑角色设定'));
    await tester.pumpAndSettle();
    expect(find.text('编辑角色：豆豆（来自角色卡）'), findsOneWidget);
    expect(find.text('此处修改仅影响本书，不会改动角色卡。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('重新生成定妆照后写回角色卡并更新使用时间', (tester) async {
    await tester.runAsync(() => charStorage.saveCard(dino()));
    final settings = AppSettings(
      imageType: 'gemini',
      imageApiKey: 'test-key',
      imageModel: 'gemini-2.5-flash-image',
    );
    await pumpReview(
      tester,
      settings: settings,
      engine: BookEngineService(dio: fakeGeminiImageDio(pngBase64)),
    );

    await runIo(
      tester,
      () => tester.tap(find.byTooltip('重新生成定妆照')),
      until: () => find
          .text('定妆照已保存。请检查角色外貌和服装，确认后再开始绘制故事页。')
          .evaluate()
          .isNotEmpty,
    );

    expect(
      File('${charDir.path}/card_dino1/anchor_watercolor.png').existsSync(),
      isTrue,
    );
    final cards =
        jsonDecode(File('${charDir.path}/cards.json').readAsStringSync()) as List;
    final card = cards.single as Map<String, dynamic>;
    expect(card['anchorImagePaths'], {'watercolor': 'card_dino1/anchor_watercolor.png'});
    expect(card['lastUsedAt'], isNotNull);

    final bookFiles = bookDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(bookFiles, hasLength(1));
    final book = jsonDecode(bookFiles.single.readAsStringSync()) as Map<String, dynamic>;
    expect(book['characterCardIds'], ['card_dino1']);
    expect((book['characters'] as List).single['referenceImageBase64'], pngBase64);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/storyboard_review_pinned_test.dart`

Expected: 编译失败，`characterCardIds` / `characterStorage` / `bookStorage` / `engine` 不是 `StoryboardReviewScreen` 的命名参数。

- [ ] **Step 3: 实现审核页改动**

`lib/screens/storyboard_review_screen.dart`：

（a）import 区在 `import '../services/book_storage_service.dart';` 之后加：

```dart
import '../services/character_storage_service.dart';
```

（b）`StoryboardReviewScreen` 字段与构造函数改为：

```dart
class StoryboardReviewScreen extends StatefulWidget {
  final String title;
  final BookStyle style;
  final List<BookPageItem> initialPages;
  final List<BookCharacter> initialCharacters;
  final AppSettings settings;

  /// 从创建页带来的固定角色（含卡片本体）；P1 只保存，P3 拍照阶段用它取照片。
  final List<PinnedCharacter> pinnedCharacters;

  /// 本书使用的角色卡 id；用来判断哪些书内角色来自角色卡。
  final List<String> characterCardIds;
  final CharacterStorageService? characterStorage;
  final BookEngineService? engine;
  final BookStorageService? bookStorage;

  const StoryboardReviewScreen({
    super.key,
    required this.title,
    required this.style,
    required this.initialPages,
    this.initialCharacters = const [],
    required this.settings,
    this.pinnedCharacters = const [],
    this.characterCardIds = const [],
    this.characterStorage,
    this.engine,
    this.bookStorage,
  });
```

（c）State 里把

```dart
  final BookEngineService _engine = BookEngineService();
  final BookStorageService _storage = BookStorageService();
```

改为：

```dart
  late final BookEngineService _engine;
  late final BookStorageService _storage;
  late final CharacterStorageService _characterStorage;
  late final List<String> _characterCardIds;
  bool _touchedCards = false;
```

`initState` 在 `super.initState();` 之后加：

```dart
    _engine = widget.engine ?? BookEngineService();
    _storage = widget.bookStorage ?? BookStorageService();
    _characterStorage = widget.characterStorage ?? CharacterStorageService();
    _characterCardIds = List.of(widget.characterCardIds);
```

（d）`_currentDraft()` 在 `protagonistRefImage: _protagonistRef,` 之后加一行：

```dart
    characterCardIds: _characterCardIds,
```

（e）在 `_currentDraft()` 之后加三个辅助方法：

```dart
  bool _isCardCharacter(BookCharacter character) =>
      _characterCardIds.contains(character.id);

  /// 首次落盘后把所用角色卡标记为「刚用过」；失败不影响绘本生成。
  Future<void> _touchCardsOnce() async {
    if (_touchedCards || _characterCardIds.isEmpty) return;
    _touchedCards = true;
    try {
      await _characterStorage.touchLastUsed(_characterCardIds);
    } catch (_) {}
  }

  /// 把新定妆照按当前画风写回角色卡并清掉图片缓存；失败只提示，不阻断。
  Future<void> _writeBackAnchor(String cardId, String image) async {
    try {
      final path = await _characterStorage.saveAnchor(
        cardId,
        widget.style.id,
        image,
      );
      await FileImage(await _characterStorage.imageFile(path)).evict();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('定妆照已生成，但写回角色卡失败：$e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Widget _cardBadge() => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFD8A24A).withValues(alpha: 0.6),
          ),
        ),
        child: const Text(
          '角色卡',
          style: TextStyle(fontSize: 10, color: Color(0xFFD8A24A)),
        ),
      );
```

（f）`_editCharacter`：把 `title: Text('编辑角色：${character.name}'),` 改为

```dart
          title: Text(
            _isCardCharacter(character)
                ? '编辑角色：${character.name}（来自角色卡）'
                : '编辑角色：${character.name}',
          ),
```

并在对话框 `Column` 的 `children: [` 第一项（`TextField(controller: nameCtrl, ...)` 之前）插入：

```dart
                  if (_isCardCharacter(character))
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        '此处修改仅影响本书，不会改动角色卡。',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
```

（g）`_prepareCharacterReferences` 中

```dart
        character.referenceImageBase64 = image;
        await _storage.saveBook(_currentDraft());
```

改为：

```dart
        character.referenceImageBase64 = image;
        await _storage.saveBook(_currentDraft());
        await _touchCardsOnce();
        if (_isCardCharacter(character)) {
          await _writeBackAnchor(character.id, image);
        }
```

（h）`_startDrawIllustrations` 中

```dart
      var currentBook = _currentDraft();
      await _storage.saveBook(currentBook);
```

改为：

```dart
      var currentBook = _currentDraft();
      await _storage.saveBook(currentBook);
      await _touchCardsOnce();
```

（i）角色卡片里的名字（`build` 内 `for (final character in _characters)` 的 `Column` 第一项）

```dart
                                              Text(
                                                character.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
```

改为：

```dart
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      character.name,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  if (_isCardCharacter(
                                                    character,
                                                  ))
                                                    _cardBadge(),
                                                ],
                                              ),
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/storyboard_review_pinned_test.dart test/character_consistency_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "storyboard_review" || echo "analyze: no lines for touched files"`

Expected: 2 + 原有用例通过（连续跑 3 次确认写回用例稳定）；grep 无输出。若写回用例超时，先确认 `until` 文案与 `_prepareCharacterReferences` 成功 SnackBar 文案一致，再考虑把 `maxRounds` 提到 120。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/screens/storyboard_review_screen.dart test/storyboard_review_pinned_test.dart && git commit -m "feat(character-card): mark card characters in review and write regenerated portraits back to cards

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: 创建页：选择角色卡并注入分镜

**Files:**
- Modify: `lib/screens/create_book_screen.dart`（整体替换）
- Test: `test/create_book_screen_test.dart`（新建）

**Interfaces:**
- Consumes: `CharacterStorageService.loadCards / readImageBase64 / cardsChangedNotifier`、`PinnedCharacter`、`createStoryboardDraft(pinnedCharacters:)`（Task 3）、`StoryboardReviewScreen(pinnedCharacters:, characterCardIds:)`（Task 4）、`CharacterLibraryScreen`、`kMaxCharacterCardsPerBook`
- Produces: `CreateBookScreen({initialTitle, initialSynopsis, initialStyleId, CharacterStorageService? characterStorage, BookEngineService? engine, Future<AppSettings> Function()? loadSettings})`；选卡区文案「👥 选择角色卡（可选，最多 3 张）」、超限提示「每本绘本最多选择 3 张角色卡」、空库入口「去创建角色」、画风提示「进入审核后会先为 X 绘制该画风的定妆照」、故事提示「在故事里直接用名字称呼他们」。

- [ ] **Step 1: 写失败的测试**

创建 `test/create_book_screen_test.dart`：

```dart
import 'dart:io';

import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/create_book_screen.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在真实事件循环里执行会产生文件 IO 的操作，然后交替「让出真实时间片」与
/// 「冲刷一次 FakeAsync 微任务队列」，直到 [until] 成立或达到 [maxRounds]。
Future<void> runIo(
  WidgetTester tester,
  Future<void> Function() body, {
  bool Function()? until,
  int maxRounds = 60,
}) async {
  await tester.runAsync(body);
  for (var i = 0; i < maxRounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    if (until != null && until()) break;
  }
  await tester.pumpAndSettle();
}

CharacterCard card(String id, String name, {Map<String, String>? anchors}) =>
    CharacterCard(
      id: id,
      name: name,
      appearance: '外貌 $name',
      catchphrase: '$name 来啦',
      anchorImagePaths: anchors,
    );

void main() {
  late Directory dir;
  late CharacterStorageService storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bookbuddy-create-test-');
    storage = CharacterStorageService(directory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpCreate(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await runIo(
      tester,
      () => tester.pumpWidget(
        MaterialApp(home: CreateBookScreen(characterStorage: storage)),
      ),
      until: () => find.text('👥 选择角色卡（可选，最多 3 张）').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
  }

  testWidgets('角色库为空时显示去创建角色入口', (tester) async {
    await pumpCreate(tester);
    expect(find.text('去创建角色'), findsOneWidget);
  });

  testWidgets('最多选择三张角色卡，第四张被拒绝并提示', (tester) async {
    await tester.runAsync(() async {
      for (final c in [
        card('card_a', '豆豆', anchors: {'watercolor': 'card_a/anchor_watercolor.png'}),
        card('card_b', '小满'),
        card('card_c', '阿福'),
        card('card_d', '毛毛'),
      ]) {
        await storage.saveCard(c);
      }
    });
    await pumpCreate(tester);

    for (final name in ['豆豆', '小满', '阿福']) {
      await tester.tap(find.widgetWithText(FilterChip, name));
      await tester.pumpAndSettle();
    }
    expect(find.text('豆豆 · 豆豆 来啦'), findsOneWidget);
    expect(find.text('在故事里直接用名字称呼他们'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '毛毛'));
    await tester.pumpAndSettle();
    expect(find.text('每本绘本最多选择 3 张角色卡'), findsOneWidget);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '毛毛')).selected, isFalse);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '豆豆')).selected, isTrue);

    // 小满、阿福没有水彩定妆图，豆豆有。
    expect(find.text('进入审核后会先为 小满、阿福 绘制该画风的定妆照'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '豆豆'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '豆豆')).selected, isFalse);
    expect(find.text('豆豆 · 豆豆 来啦'), findsNothing);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/create_book_screen_test.dart`

Expected: 编译失败，`characterStorage` 不是 `CreateBookScreen` 的命名参数。

- [ ] **Step 3: 整体替换创建页**

把 `lib/screens/create_book_screen.dart` 整体替换为：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/character_card.dart';
import '../models/fairy_tale_catalog.dart';
import '../models/style_catalog.dart';
import '../services/book_engine_service.dart';
import '../services/character_storage_service.dart';
import '../services/settings_service.dart';
import 'character_library_screen.dart';
import 'storyboard_review_screen.dart';
import 'tale_recommendation_dialog.dart';

class CreateBookScreen extends StatefulWidget {
  final String? initialTitle;
  final String? initialSynopsis;
  final String? initialStyleId;
  final CharacterStorageService? characterStorage;
  final BookEngineService? engine;
  final Future<AppSettings> Function()? loadSettings;

  const CreateBookScreen({
    super.key,
    this.initialTitle,
    this.initialSynopsis,
    this.initialStyleId,
    this.characterStorage,
    this.engine,
    this.loadSettings,
  });

  @override
  State<CreateBookScreen> createState() => _CreateBookScreenState();
}

class _CreateBookScreenState extends State<CreateBookScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _textCtrl;
  late String _selectedStyleId;

  bool _isProcessing = false;
  String _statusText = '';

  late final BookEngineService _engine;
  late final Future<AppSettings> Function() _loadSettings;
  late final CharacterStorageService _characterStorage;

  List<CharacterCard> _cards = [];
  bool _cardsLoading = true;
  final List<String> _selectedCardIds = [];

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle ?? '');
    _textCtrl = TextEditingController(text: widget.initialSynopsis ?? '');
    _selectedStyleId = widget.initialStyleId ?? 'watercolor';
    _engine = widget.engine ?? BookEngineService();
    _loadSettings = widget.loadSettings ?? SettingsService().loadSettings;
    _characterStorage = widget.characterStorage ?? CharacterStorageService();
    _loadCards();
    CharacterStorageService.cardsChangedNotifier.addListener(_loadCards);
  }

  @override
  void dispose() {
    CharacterStorageService.cardsChangedNotifier.removeListener(_loadCards);
    _titleCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    try {
      final cards = await _characterStorage.loadCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _selectedCardIds.removeWhere((id) => !cards.any((c) => c.id == id));
        _cardsLoading = false;
      });
    } catch (_) {
      // 角色库读不出来不影响写故事，只是没有卡可选。
      if (mounted) setState(() => _cardsLoading = false);
    }
  }

  void _toggleCard(CharacterCard card) {
    if (_selectedCardIds.contains(card.id)) {
      setState(() => _selectedCardIds.remove(card.id));
      return;
    }
    if (_selectedCardIds.length >= kMaxCharacterCardsPerBook) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('每本绘本最多选择 $kMaxCharacterCardsPerBook 张角色卡')),
      );
      return;
    }
    setState(() => _selectedCardIds.add(card.id));
  }

  List<CharacterCard> get _selectedCards => [
        for (final id in _selectedCardIds) _cards.firstWhere((c) => c.id == id),
      ];

  /// 已选卡片里缺少当前画风定妆图的名字，用于提示「进入审核后会先补画」。
  List<String> get _cardsMissingAnchor => [
        for (final card in _selectedCards)
          if (!card.anchorImagePaths.containsKey(_selectedStyleId)) card.name,
      ];

  Future<List<PinnedCharacter>> _buildPinned() async {
    final pinned = <PinnedCharacter>[];
    for (final card in _selectedCards) {
      final path = card.anchorImagePaths[_selectedStyleId];
      final anchor =
          path == null ? null : await _characterStorage.readImageBase64(path);
      pinned.add(PinnedCharacter(card: card, anchorBase64: anchor));
    }
    return pinned;
  }

  Future<void> _startGenerate() async {
    final title = _titleCtrl.text.trim();
    final text = _textCtrl.text.trim();

    if (title.isEmpty && text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入故事标题或故事正文')));
      return;
    }

    final settings = await _loadSettings();
    if (!mounted) return;
    if (settings.llmApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ 请先点击右上角设置图标，填写 LLM API Key！'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusText = '正在分析故事并重构绘本分镜镜头...';
    });

    try {
      final finalTitle = title.isNotEmpty
          ? title
          : (text.length > 20 ? text.substring(0, 20) : text);
      final pinned = await _buildPinned();
      final draft = await _engine.createStoryboardDraft(
        settings: settings,
        title: finalTitle,
        storyText: text.isNotEmpty ? text : finalTitle,
        pinnedCharacters: pinned,
      );

      if (draft.pages.isEmpty) {
        throw Exception('大模型未能成功生成绘本分镜，请重试');
      }

      final style = StyleCatalog.styles.firstWhere(
        (s) => s.id == _selectedStyleId,
      );

      if (!mounted) return;
      // 成功获得分镜后，进入分镜审核确认页面（支持编辑正文、画面动作、微表情和开关插画）
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoryboardReviewScreen(
            title: finalTitle,
            style: style,
            initialPages: draft.pages,
            initialCharacters: draft.characters,
            settings: settings,
            pinnedCharacters: pinned,
            characterCardIds: List.of(_selectedCardIds),
          ),
        ),
      );
    } on StateError catch (e) {
      // 对账失败：角色卡没有出场等，原文提示，停留在创建页。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildCardPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '👥 选择角色卡（可选，最多 $kMaxCharacterCardsPerBook 张）',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_cardsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_cards.isEmpty)
          Row(
            children: [
              const Text(
                '还没有角色卡。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CharacterLibraryScreen(
                        storage: _characterStorage,
                      ),
                    ),
                  );
                },
                child: const Text('去创建角色'),
              ),
            ],
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final card in _cards)
                FilterChip(
                  label: Text(card.name),
                  avatar: const Icon(Icons.face_retouching_natural, size: 16),
                  selected: _selectedCardIds.contains(card.id),
                  onSelected: (_) => _toggleCard(card),
                ),
            ],
          ),
          if (_selectedCardIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final card in _selectedCards)
              Text(
                card.catchphrase.trim().isEmpty
                    ? card.name
                    : '${card.name} · ${card.catchphrase}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFD8A24A)),
              ),
            const SizedBox(height: 4),
            const Text(
              '在故事里直接用名字称呼他们',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final missingAnchor = _cardsMissingAnchor;
    return Scaffold(
      appBar: AppBar(
        title: const Text('✨ 新建绘本作品'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD8A24A),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            icon: const Text('🌟', style: TextStyle(fontSize: 16)),
            label: const Text(
              '挑选经典童话',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              final selected = await showDialog<FairyTaleItem?>(
                context: context,
                builder: (_) => const TaleRecommendationDialog(),
              );
              if (selected != null && mounted) {
                setState(() {
                  _titleCtrl.text = selected.title;
                  _textCtrl.text = selected.synopsis;
                  _selectedStyleId = selected.recommendedStyle;
                });
              }
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: _isProcessing
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      Text(_statusText, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text(
                        '正在智能分镜与镜头场景重构中，完成后将进入分镜审核确认页面',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: '故事标题（如：小红帽的故事、三只小猪）',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildCardPicker(),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📖 故事正文：',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.paste_rounded, size: 16),
                              label: const Text(
                                '从剪贴板粘贴',
                                style: TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                final data = await Clipboard.getData(
                                  Clipboard.kTextPlain,
                                );
                                if (data != null &&
                                    data.text != null &&
                                    data.text!.isNotEmpty) {
                                  setState(() {
                                    _textCtrl.text = data.text!.trim();
                                  });
                                }
                              },
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.clear, size: 16),
                              label: const Text(
                                '清空',
                                style: TextStyle(fontSize: 12),
                              ),
                              onPressed: () => _textCtrl.clear(),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _textCtrl,
                      maxLines: 6,
                      enableInteractiveSelection: true,
                      decoration: const InputDecoration(
                        hintText: '可直接粘贴故事全文；若留空仅填书名，AI 将自动构思并续写完整童话...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '🎨 选择绘本画风',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: StyleCatalog.styles.map((st) {
                        final isSel = st.id == _selectedStyleId;
                        return ChoiceChip(
                          label: Text(st.name),
                          selected: isSel,
                          onSelected: (_) =>
                              setState(() => _selectedStyleId = st.id),
                        );
                      }).toList(),
                    ),
                    if (missingAnchor.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '进入审核后会先为 ${missingAnchor.join('、')} 绘制该画风的定妆照',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                    const SizedBox(height: 36),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _startGenerate,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text(
                        '🎬 分析故事并生成分镜 (进入审核)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/create_book_screen_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "create_book_screen" || echo "analyze: no lines for touched files"`

Expected: 2 tests passed（连续跑 3 次）；grep 无输出。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/screens/create_book_screen.dart test/create_book_screen_test.dart && git commit -m "feat(character-card): pick up to three character cards when creating a book

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: 角色库「出演 N 本」、书架角标、阅读器标签、文档与全量验证

**Files:**
- Modify: `lib/screens/character_library_screen.dart`（构造参数、`_load`、副标题）
- Modify: `lib/main.dart:337-345`（书架条目标题行）
- Modify: `lib/screens/book_reader_screen.dart:439-445`（角色对话框名字）
- Modify: `AGENTS.md`（§2.1 功能全景）
- Test: `test/character_library_screen_test.dart`（更新两处断言，新增一条）

**Interfaces:**
- Consumes: `PictureBook.characterCardIds`（Task 1）、`BookStorageService(booksDirectory:)`、`SharedPreferences.setMockInitialValues`
- Produces: `CharacterLibraryScreen({storage, BookStorageService? bookStorage})`；副标题格式 `<类型> · 定妆图 N 张 · 出演 M 本`。

- [ ] **Step 1: 更新并追加角色库测试**

`test/character_library_screen_test.dart`：

（a）import 区加入：

```dart
import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/services/book_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
```

（b）`setUp` / `tearDown` 与 `pumpLibrary` 改为：

```dart
  late Directory dir;
  late Directory bookDir;
  late CharacterStorageService storage;
  late BookStorageService bookStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'bookbuddy_books_migrated_to_files': true,
    });
    dir = Directory.systemTemp.createTempSync('bookbuddy-library-test-');
    bookDir = Directory.systemTemp.createTempSync('bookbuddy-library-books-');
    storage = CharacterStorageService(directory: dir);
    bookStorage = BookStorageService(booksDirectory: bookDir);
  });

  tearDown(() {
    for (final d in [dir, bookDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<void> pumpLibrary(WidgetTester tester) => runIo(
        tester,
        () => tester.pumpWidget(
          MaterialApp(
            home: CharacterLibraryScreen(
              storage: storage,
              bookStorage: bookStorage,
            ),
          ),
        ),
        until: () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
```

（c）「显示已保存的卡片、类型与定妆图数量」用例里的两处断言改为：

```dart
    expect(find.text('动物 · 定妆图 1 张 · 出演 0 本'), findsOneWidget);
    ...
    expect(find.text('物件 · 定妆图 0 张 · 出演 0 本'), findsOneWidget);
```

（d）在 `main()` 收尾 `}` 之前追加：

```dart
  testWidgets('出演次数按绘本的 characterCardIds 统计', (tester) async {
    await tester.runAsync(() async {
      await storage.saveCard(
        CharacterCard(id: 'card_a', name: '豆豆', appearance: '绿色'),
      );
      for (final id in ['book-1', 'book-2']) {
        await bookStorage.saveBook(
          PictureBook(
            id: id,
            title: '书 $id',
            styleId: 'watercolor',
            styleName: '水彩童话',
            pages: [BookPageItem(pageIndex: 0, text: '豆豆出发。')],
            createdAt: DateTime.utc(2026, 9, 30),
            characterCardIds: ['card_a'],
          ),
        );
      }
    });
    await pumpLibrary(tester);
    expect(find.text('动物 · 定妆图 0 张 · 出演 2 本'), findsOneWidget);
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_library_screen_test.dart`

Expected: 编译失败，`bookStorage` 不是 `CharacterLibraryScreen` 的命名参数。

- [ ] **Step 3: 实现角色库、书架、阅读器与文档改动**

`lib/screens/character_library_screen.dart`：

（a）import 区加入 `import '../services/book_storage_service.dart';`。

（b）widget 改为：

```dart
class CharacterLibraryScreen extends StatefulWidget {
  final CharacterStorageService? storage;
  final BookStorageService? bookStorage;

  const CharacterLibraryScreen({super.key, this.storage, this.bookStorage});
```

（c）State 字段加：

```dart
  late final BookStorageService _bookStorage;
  Map<String, int> _bookCounts = {};
```

`initState` 中 `_storage = ...` 之后加 `_bookStorage = widget.bookStorage ?? BookStorageService();`。

（d）`_load()` 的 `try` 块改为：

```dart
    try {
      final cards = await _storage.loadCards();
      final counts = <String, int>{};
      try {
        for (final book in await _bookStorage.loadBooks()) {
          for (final id in book.characterCardIds) {
            counts[id] = (counts[id] ?? 0) + 1;
          }
        }
      } catch (_) {
        // 书架读不出来只影响「出演 N 本」，不影响角色库本身。
      }
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _bookCounts = counts;
        _loading = false;
        _errorMessage = null;
      });
    } catch (e) {
```

（e）副标题改为：

```dart
                          Text(
                            '${_kindLabel(card.kind)} · 定妆图 ${card.anchorImagePaths.length} 张 · 出演 ${_bookCounts[card.id] ?? 0} 本',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
```

`lib/main.dart` 书架条目标题行：在

```dart
                                          Expanded(
                                            child: Text(
                                              b.title,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
```

之后、`if (hasUnfinished) ...[` 之前插入：

```dart
                                          if (b.characterCardIds.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            const Tooltip(
                                              message: '使用了角色卡',
                                              child: Icon(
                                                Icons.face_retouching_natural,
                                                size: 16,
                                                color: Color(0xFFD8A24A),
                                              ),
                                            ),
                                          ],
```

`lib/screens/book_reader_screen.dart` 角色对话框里的名字（`_showCharacterReferences` 内 `Row` 的第一项）

```dart
                                    Text(
                                      character.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
```

改为：

```dart
                                    Row(
                                      children: [
                                        Text(
                                          character.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (_book.characterCardIds.contains(character.id))
                                          Container(
                                            margin: const EdgeInsets.only(left: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFD8A24A).withValues(alpha: 0.6)),
                                            ),
                                            child: const Text(
                                              '角色卡',
                                              style: TextStyle(fontSize: 10, color: Color(0xFFD8A24A)),
                                            ),
                                          ),
                                      ],
                                    ),
```

`AGENTS.md` §2.1 功能全景，在 `│    ├── 灵感推荐：...` 之前插入一行：

```
 │    ├── 角色卡：角色库创建可复用主角，选卡注入分镜并沿用定妆图 (CharacterCard / PinnedCharacter)
```

- [ ] **Step 4: 运行相关测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_library_screen_test.dart test/widget_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "character_library|lib/main.dart:(3[0-9]{2}|4[0-9]{2})|book_reader" || echo "analyze: no new lines (main.dart pre-existing withOpacity infos live after the insertion and are not ours)"`

Expected: 5 + 3 tests passed。若 `grep` 命中 `lib/main.dart` 的行，逐条确认它们是原有的 `withOpacity` 弃用提示（行号因插入下移），不是新问题。

- [ ] **Step 5: 全量验证**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter analyze | tail -1 && $HOME/development/flutter/bin/flutter test`

Expected: analyze 总数与 `main` 上一致（39 条，全是原有 `withOpacity` 提示）；全部测试通过（P0 时 63 条 + 本期新增 15 条左右）。若默认并发出现重试噪音，再跑 `$HOME/development/flutter/bin/flutter test --concurrency=1` 并以它为准。

- [ ] **Step 6: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/screens/character_library_screen.dart lib/main.dart lib/screens/book_reader_screen.dart AGENTS.md test/character_library_screen_test.dart && git commit -m "feat(character-card): show card usage in the library, shelf and reader

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

- [ ] **Step 7: 手动验收（用户执行，不在实施者范围内）**

按 spec §10 P1：同一张卡分别用于两本自定义故事，两本书的主角外貌一致；第二本若选了新画风，审核页先补画定妆图并写回卡片（角色库里该卡「定妆图」数量加一，缩略图立即更新）；编辑卡片外貌后，两本旧书不变；创建页选第四张卡被拒绝；故事里没写到所选角色时，创建页红色提示并停留。

```bash
$HOME/development/flutter/bin/flutter run -d macos
```

---

## 自检记录

**Spec 覆盖（P1 范围）**

| Spec 条目 | 任务 |
|---|---|
| 3.2 `PictureBook.characterCardIds` | Task 1 |
| 3.3 `PinnedCharacter` | Task 3 |
| 5.4 上限、提示词注入、对账四规则、定妆图赋值 | Task 3 |
| 6.1 书架角标 | Task 6 |
| 6.2「出演 N 本」 | Task 6 |
| 6.4 选卡区（≤3）、已选列表与提示、画风不匹配提示、组装 `PinnedCharacter`、对账错误原文、传参 | Task 5 |
| 6.5 参数、草稿写 id、写回 + evict、`lastUsedAt`、来自角色卡标签与编辑提示 | Task 4（删除角色功能不存在，无需实现） |
| 6.6 阅读器标签 | Task 6 |
| 8 对账失败 SnackBar | Task 5 |
| 9 `book_engine_pinned_test`、`characterCardIds` 往返、创建页选满 3 张 | Task 3、1、5 |
| 10 P1 验收 | Task 6 Step 7（用户） |
| 终审建议：空服装投影、`touchLastUsed` 不整卡覆盖、写回后 evict | Task 1、2、4 |

**类型一致性**：`PinnedCharacter({required card, anchorBase64, photoBase64})` 在 Task 3 定义，Task 4/5 使用相同命名参数；`createStoryboardDraft(pinnedCharacters:)` 与 `StoryboardReviewScreen(pinnedCharacters:, characterCardIds:)` 名称一致；`touchLastUsed(Iterable<String>)` 在 Task 2 定义，Task 4 传 `List<String>`；`saveAnchor` 返回相对路径供 `imageFile` 使用（P0 已定）。

**占位扫描**：无 TBD / TODO；每个代码步骤都给出了完整代码或精确的替换前后片段。
