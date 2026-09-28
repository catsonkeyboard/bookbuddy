# 角色卡 P0：手动角色卡 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户在独立页面里手动创建、编辑、删除可复用的角色卡，并按画风生成、缓存定妆图，重启后仍在。

**Architecture:** 新增一个独立于绘本的角色库子系统：`CharacterCard` 模型（含性格、口头禅、按画风索引的定妆图路径）+ `CharacterStorageService`（元数据 JSON 与图片文件分离落盘，原子写照抄绘本存储）+ 两个页面（角色库网格、角色卡编辑器）。定妆图生成复用现有 `BookEngineService.generateCharacterReference`，生成前用 `supportsCharacterReference` 做通道前置检查。不改动任何绘本模型与生图管线。

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4，`path_provider`、`uuid`、`wakelock_plus`（均为已有依赖），`flutter_test`。本期**不新增任何依赖**。

**Spec:** `docs/superpowers/specs/2026-09-28-character-card-design.md`（第 1、3、4、6.1、6.2、6.3、8、9 节与第 10 节 P0）

## Global Constraints

- Flutter SDK 绝对路径 `$HOME/development/flutter/bin/flutter`；任何 `pub get` 前必须 `export PUB_HOSTED_URL="https://pub.flutter-io.cn" && export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"`（本期无需 pub get）。
- 每个任务结束前运行 `$HOME/development/flutter/bin/flutter analyze` 与对应测试文件，全部通过才能提交。
- 模型字段增删必须同步构造函数、`toJson()`、`fromJson()` 与单元测试（AGENTS.md 铁律）。
- 不得硬编码任何 API Key。
- 角色库目录固定为 `<appDocuments>/bookbuddy_characters/`；`cards.json` 只存元数据，**图片绝不以 base64 写入 JSON**。
- 常量 `kMaxCharacterCardsPerBook = 3`；`CharacterKind` 未知值回退 `human`，`CharacterCardSource` 未知值回退 `manual`。
- 物件角色（`kind == object`）且默认服装为空时，投影到 `BookCharacter` 的外貌末尾追加 `（非生物物件拟人化角色，不添加人类服饰和鞋靴）`。
- 修改 `kind / species / appearance / defaultOutfit` 任一项并保存时，必须先弹确认再清空全部定妆图。
- 界面文案使用简体中文，风格与现有页面一致（emoji 标题、金色 `Color(0xFFD8A24A)` 主色）。
- 提交信息遵循 Conventional Commits，末尾附 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`。
- 本期的角色库页显示「定妆图 N 张」；「出演 N 本」依赖 P1 的 `PictureBook.characterCardIds`，P1 再替换。空状态与首页引导文案不提「拍照」，P3 再改。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `lib/models/character_card.dart`（新建） | 角色卡数据模型、枚举、常量、投影到 `BookCharacter`、JSON 对称序列化、ID 生成 |
| `lib/services/character_storage_service.dart`（新建） | 角色库落盘：`cards.json` 原子写 + `.bak` 恢复、图片文件读写、定妆图落盘与映射维护、变更通知 |
| `lib/screens/character_library_screen.dart`（新建） | 角色库网格、空状态、删除确认、进入编辑器 |
| `lib/screens/character_card_editor_screen.dart`（新建） | 新建 / 编辑表单、画风选择、定妆图生成（含通道前置检查）、外貌变更失效确认 |
| `lib/main.dart`（修改） | AppBar「我的角色」入口 + 第二张引导卡 |
| `AGENTS.md`（修改） | 目录结构表补充新文件 |
| `test/character_card_test.dart`（新建） | 模型测试 |
| `test/character_storage_service_test.dart`（新建） | 存储测试 |
| `test/character_library_screen_test.dart`（新建） | 角色库页 widget 测试 |
| `test/character_card_editor_screen_test.dart`（新建） | 编辑页 widget 测试 |
| `test/widget_test.dart`（修改） | 首页入口导航测试 |

### 关于 widget 测试与文件 IO

`testWidgets` 的测试体运行在 FakeAsync 时钟里，**真实文件 IO 与 Dio 拦截器的 Future 不会自动完成**。规则：

- 所有会触发文件 IO 或网络 Future 的交互（`pumpWidget` 含 `initState` 读盘、点击保存 / 生成）都包在 `tester.runAsync(...)` 里，并在其中等待一小段真实时间，再 `pumpAndSettle()` 刷新界面。
- 断言优先用同步文件 API（`File(...).existsSync()`、`readAsStringSync()`），避免再进 runAsync。
- 若某条断言因 IO 未完成而偶发失败，把等待时间从 300ms 加到 600ms，而不是删断言。

两个测试文件共用的辅助函数（各文件内各写一份，测试文件之间不互相 import）：

```dart
/// 在真实事件循环里执行会产生文件 IO / 网络的操作，随后回到测试时钟刷新界面。
Future<void> runIo(WidgetTester tester, Future<void> Function() body) async {
  await tester.runAsync(() async {
    await body();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
}
```

---

### Task 0: 建立功能分支

**Files:** 无

- [ ] **Step 1: 确认工作区干净并建分支**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git status --short && git checkout -b feat/character-cards-p0
```

Expected: 只有 `?? docs/` 未跟踪；分支切换到 `feat/character-cards-p0`。

- [ ] **Step 2: 提交 spec 与本计划**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add docs/superpowers && git commit -m "docs: add character card design spec and P0 implementation plan

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 1: `CharacterCard` 模型

**Files:**
- Create: `lib/models/character_card.dart`
- Test: `test/character_card_test.dart`

**Interfaces:**
- Consumes: `BookCharacter`（`lib/models/book.dart:78`，构造函数 `BookCharacter({required id, required name, species, isAnimal, required appearance, required defaultOutfit, referenceImageBase64})`）
- Produces:
  - `const int kMaxCharacterCardsPerBook = 3`
  - `const String kObjectAppearanceSuffix`
  - `enum CharacterCardSource { manual, photo }`
  - `enum CharacterKind { human, animal, object }`
  - `class CharacterCard` 字段：`String id; CharacterCardSource source; String name; CharacterKind kind; String species; String appearance; String defaultOutfit; String personality; String catchphrase; Map<String,String> anchorImagePaths; String? photoPath; DateTime createdAt; DateTime? lastUsedAt`
  - `bool get isAnimal`
  - `BookCharacter toBookCharacter({String? referenceImageBase64})`
  - `Map<String,dynamic> toJson()` / `factory CharacterCard.fromJson(Map<String,dynamic>)`
  - `static String newId()` → `'card_' + 8 位十六进制`

- [ ] **Step 1: 写失败的测试**

创建 `test/character_card_test.dart`：

```dart
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_card_test.dart`

Expected: 编译失败，提示 `package:bookbuddy/models/character_card.dart` 不存在。

- [ ] **Step 3: 实现模型**

创建 `lib/models/character_card.dart`：

```dart
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
  BookCharacter toBookCharacter({String? referenceImageBase64}) {
    var projectedAppearance = appearance;
    if (kind == CharacterKind.object && defaultOutfit.trim().isEmpty) {
      projectedAppearance = '$appearance$kObjectAppearanceSuffix';
    }
    return BookCharacter(
      id: id,
      name: name,
      species: species,
      isAnimal: isAnimal,
      appearance: projectedAppearance,
      defaultOutfit: defaultOutfit,
      referenceImageBase64: referenceImageBase64,
    );
  }

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
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_card_test.dart && $HOME/development/flutter/bin/flutter analyze`

Expected: 7 tests passed；analyze 无新增问题。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/models/character_card.dart test/character_card_test.dart && git commit -m "feat(character-card): add CharacterCard model with BookCharacter projection

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `CharacterStorageService` 元数据读写

**Files:**
- Create: `lib/services/character_storage_service.dart`
- Test: `test/character_storage_service_test.dart`

**Interfaces:**
- Consumes: `CharacterCard`（Task 1）
- Produces（本任务实现的部分）:
  - `CharacterStorageService({Directory? directory})`
  - `static final ValueNotifier<int> cardsChangedNotifier`
  - `Future<List<CharacterCard>> loadCards()` — 按 `lastUsedAt ?? createdAt` 倒序
  - `Future<void> saveCard(CharacterCard card)` — upsert
  - `Future<void> deleteCard(String id)` — 删元数据并删除 `card_xxx/` 目录（目录删除的测试放在 Task 3）

- [ ] **Step 1: 写失败的测试**

创建 `test/character_storage_service_test.dart`：

```dart
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_storage_service_test.dart`

Expected: 编译失败，`character_storage_service.dart` 不存在。

- [ ] **Step 3: 实现元数据部分**

创建 `lib/services/character_storage_service.dart`（Task 3 会在同一文件追加图片方法）：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/character_card.dart';

/// 角色库落盘。目录结构：
/// bookbuddy_characters/
/// ├── cards.json（仅元数据，附 .bak / .tmp 双保险）
/// └── card_xxx/（该卡片的图片文件）
class CharacterStorageService {
  static const _cardsFileName = 'cards.json';

  /// 所有写操作串行化，保证 cards.json 不被并发写坏。
  static Future<void>? _pendingSave;

  /// 新建 / 更新 / 删除卡片后 +1，供列表页刷新。
  static final ValueNotifier<int> cardsChangedNotifier = ValueNotifier<int>(0);

  final Directory? _directory;

  CharacterStorageService({Directory? directory}) : _directory = directory;

  Future<Directory> _root() async {
    final dir = _directory ??
        Directory(
          '${(await getApplicationDocumentsDirectory()).path}/bookbuddy_characters',
        );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _cardsFile() async =>
      File('${(await _root()).path}/$_cardsFileName');

  List<CharacterCard>? _parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((m) => CharacterCard.fromJson(Map<String, dynamic>.from(m)))
          .where((c) => c.id.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<CharacterCard>> _readAll() async {
    final file = await _cardsFile();
    final backup = File('${file.path}.bak');
    for (final candidate in [file, backup]) {
      if (await candidate.exists()) {
        final cards = _parse(await candidate.readAsString());
        if (cards != null) return cards;
      }
    }
    return [];
  }

  /// 按最近使用时间（没有则按创建时间）倒序。
  Future<List<CharacterCard>> loadCards() async {
    final cards = await _readAll();
    cards.sort(
      (a, b) => (b.lastUsedAt ?? b.createdAt)
          .compareTo(a.lastUsedAt ?? a.createdAt),
    );
    return cards;
  }

  Future<void> saveCard(CharacterCard card) async {
    if (card.id.isEmpty) throw ArgumentError('Card id must not be empty');
    await _mutate((cards) {
      final index = cards.indexWhere((c) => c.id == card.id);
      if (index >= 0) {
        cards[index] = card;
      } else {
        cards.add(card);
      }
    });
  }

  Future<void> deleteCard(String id) async {
    await _mutate((cards) => cards.removeWhere((c) => c.id == id));
    final dir = Directory('${(await _root()).path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 读 → 改 → 原子写，排队执行；成功后触发通知。
  Future<void> _mutate(void Function(List<CharacterCard> cards) change) async {
    final previous = _pendingSave;
    final save = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // 上一次失败不应阻塞本次。
        }
      }
      final cards = await _readAll();
      change(cards);
      await _writeAll(cards);
    }();
    _pendingSave = save;
    try {
      await save;
      cardsChangedNotifier.value++;
    } finally {
      if (identical(_pendingSave, save)) _pendingSave = null;
    }
  }

  /// tmp 落盘 → 旧文件可解析则改名 .bak（否则改名 .corrupt.*）→ tmp 改名正式。
  Future<void> _writeAll(List<CharacterCard> cards) async {
    final file = await _cardsFile();
    final backup = File('${file.path}.bak');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(cards.map((c) => c.toJson()).toList()),
      flush: true,
    );
    try {
      if (await file.exists()) {
        if (_parse(await file.readAsString()) != null) {
          if (await backup.exists()) await backup.delete();
          await file.rename(backup.path);
        } else {
          await file.rename(
            '${file.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}',
          );
        }
      }
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_storage_service_test.dart && $HOME/development/flutter/bin/flutter analyze`

Expected: 7 tests passed；analyze 无新增问题。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/services/character_storage_service.dart test/character_storage_service_test.dart && git commit -m "feat(character-card): add CharacterStorageService with atomic cards.json writes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `CharacterStorageService` 图片与定妆图

**Files:**
- Modify: `lib/services/character_storage_service.dart`
- Test: `test/character_storage_service_test.dart`（追加用例）

**Interfaces:**
- Produces:
  - `Future<String> writeImage(String cardId, String fileName, Uint8List bytes)` → 相对路径 `'$cardId/$fileName'`
  - `Future<File> imageFile(String relativePath)`
  - `Future<String?> readImageBase64(String relativePath)`
  - `Future<String> saveAnchor(String cardId, String styleId, String base64Image)` → 相对路径；接受裸 base64 或 `data:` URL；按字节头选 `.png` / `.jpg`；卡片不存在抛 `StateError` 并清理已写文件；同画风换扩展名时删除旧文件
  - `Future<void> clearAnchors(String cardId)`
  - `deleteCard` 连带删除 `card_xxx/` 目录（Task 2 已实现，本任务用测试验证）

- [ ] **Step 1: 追加失败的测试**

在 `test/character_storage_service_test.dart` 的 import 区加入 `import 'dart:typed_data';`（放在 `dart:io` 之后），并把文件末尾 `main()` 的收尾 `}` 替换为以下片段（片段末尾已包含收尾的 `}`）：

```dart
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
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_storage_service_test.dart`

Expected: 编译失败，`writeImage` / `readImageBase64` / `imageFile` / `saveAnchor` / `clearAnchors` 未定义。

- [ ] **Step 3: 实现图片方法**

在 `lib/services/character_storage_service.dart` 顶部 import 区加入：

```dart
import 'dart:typed_data';
```

在类内 `deleteCard` 之后追加：

```dart
  /// 写入卡片目录下的图片文件，返回相对角色库根目录的路径。
  Future<String> writeImage(
    String cardId,
    String fileName,
    Uint8List bytes,
  ) async {
    final dir = Directory('${(await _root()).path}/$cardId');
    if (!await dir.exists()) await dir.create(recursive: true);
    await File('${dir.path}/$fileName').writeAsBytes(bytes, flush: true);
    return '$cardId/$fileName';
  }

  Future<File> imageFile(String relativePath) async =>
      File('${(await _root()).path}/$relativePath');

  Future<String?> readImageBase64(String relativePath) async {
    final file = await imageFile(relativePath);
    if (!await file.exists()) return null;
    return base64Encode(await file.readAsBytes());
  }

  /// 落盘定妆图并更新卡片映射。扩展名按字节头判断（PNG 签名 → png，否则 jpg）。
  Future<String> saveAnchor(
    String cardId,
    String styleId,
    String base64Image,
  ) async {
    final raw = base64Image.startsWith('data:')
        ? base64Image.substring(base64Image.indexOf(',') + 1)
        : base64Image;
    final bytes = base64Decode(raw);
    final ext = _isPng(bytes) ? 'png' : 'jpg';
    final relative = await writeImage(cardId, 'anchor_$styleId.$ext', bytes);
    final root = await _root();
    try {
      await _mutate((cards) {
        final index = cards.indexWhere((c) => c.id == cardId);
        if (index < 0) {
          throw StateError('角色卡 $cardId 不存在，无法保存定妆图');
        }
        final old = cards[index].anchorImagePaths[styleId];
        if (old != null && old != relative) {
          final oldFile = File('${root.path}/$old');
          if (oldFile.existsSync()) oldFile.deleteSync();
        }
        cards[index].anchorImagePaths[styleId] = relative;
      });
    } catch (_) {
      final written = File('${root.path}/$relative');
      if (await written.exists()) await written.delete();
      rethrow;
    }
    return relative;
  }

  /// 删除卡片全部定妆图文件并清空映射（外貌设定变更时调用）。
  Future<void> clearAnchors(String cardId) async {
    final root = await _root();
    await _mutate((cards) {
      final index = cards.indexWhere((c) => c.id == cardId);
      if (index < 0) return;
      for (final path in cards[index].anchorImagePaths.values) {
        final file = File('${root.path}/$path');
        if (file.existsSync()) file.deleteSync();
      }
      cards[index].anchorImagePaths.clear();
    });
  }

  static bool _isPng(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47;
```

- [ ] **Step 4: 运行全部存储测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_storage_service_test.dart && $HOME/development/flutter/bin/flutter analyze`

Expected: 13 tests passed；analyze 无新增问题。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/services/character_storage_service.dart test/character_storage_service_test.dart && git commit -m "feat(character-card): store anchor images as files and track them per style

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: 角色库页 `CharacterLibraryScreen`

**Files:**
- Create: `lib/screens/character_library_screen.dart`
- Create: `lib/screens/character_card_editor_screen.dart`（**仅占位**：本任务需要能跳转到编辑页才能编译；先放一个最小可编译版本，Task 5 再替换为完整实现）
- Test: `test/character_library_screen_test.dart`

**Interfaces:**
- Consumes: `CharacterStorageService.loadCards / deleteCard / imageFile / cardsChangedNotifier`（Task 2、3）；`CharacterCard`、`CharacterKind`（Task 1）
- Produces:
  - `class CharacterLibraryScreen extends StatefulWidget { const CharacterLibraryScreen({super.key, CharacterStorageService? storage}); }`
  - 占位 `class CharacterCardEditorScreen extends StatefulWidget { const CharacterCardEditorScreen({super.key, CharacterCard? card, CharacterStorageService? storage, BookEngineService? engine, Future<AppSettings> Function()? loadSettings}); }`（签名即 Task 5 的最终签名）

- [ ] **Step 1: 写失败的测试**

创建 `test/character_library_screen_test.dart`：

```dart
import 'dart:io';

import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/character_library_screen.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在真实事件循环里执行会产生文件 IO / 网络的操作，随后回到测试时钟刷新界面。
Future<void> runIo(WidgetTester tester, Future<void> Function() body) async {
  await tester.runAsync(() async {
    await body();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;
  late CharacterStorageService storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bookbuddy-library-test-');
    storage = CharacterStorageService(directory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpLibrary(WidgetTester tester) => runIo(
        tester,
        () => tester.pumpWidget(
          MaterialApp(home: CharacterLibraryScreen(storage: storage)),
        ),
      );

  testWidgets('没有卡片时显示空状态', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('还没有角色'), findsOneWidget);
    expect(find.text('创建第一个角色'), findsOneWidget);
  });

  testWidgets('显示已保存的卡片、类型与定妆图数量', (tester) async {
    await tester.runAsync(() async {
      await storage.saveCard(
        CharacterCard(
          id: 'card_a',
          name: '豆豆',
          kind: CharacterKind.animal,
          appearance: '绿色毛绒恐龙',
          anchorImagePaths: {'watercolor': 'card_a/anchor_watercolor.png'},
        ),
      );
      await storage.saveCard(
        CharacterCard(
          id: 'card_b',
          name: '小满',
          kind: CharacterKind.object,
          appearance: '灰色鹅卵石',
        ),
      );
    });
    await pumpLibrary(tester);
    expect(find.text('豆豆'), findsOneWidget);
    expect(find.text('动物 · 定妆图 1 张'), findsOneWidget);
    expect(find.text('小满'), findsOneWidget);
    expect(find.text('物件 · 定妆图 0 张'), findsOneWidget);
    expect(find.text('还没有角色'), findsNothing);
  });

  testWidgets('删除需要确认，确认后卡片消失', (tester) async {
    await tester.runAsync(
      () => storage.saveCard(
        CharacterCard(id: 'card_a', name: '豆豆', appearance: '绿色'),
      ),
    );
    await pumpLibrary(tester);

    await tester.tap(find.byTooltip('删除角色'));
    await tester.pumpAndSettle();
    expect(find.text('删除角色「豆豆」'), findsOneWidget);
    expect(find.text('角色卡和它的定妆图将被删除。已生成的绘本不受影响。'), findsOneWidget);

    await runIo(tester, () => tester.tap(find.text('删除')));
    expect(find.text('豆豆'), findsNothing);
    expect(find.text('还没有角色'), findsOneWidget);
    expect(File('${dir.path}/cards.json').readAsStringSync(), '[]');
  });

  testWidgets('取消删除不改变数据', (tester) async {
    await tester.runAsync(
      () => storage.saveCard(
        CharacterCard(id: 'card_a', name: '豆豆', appearance: '绿色'),
      ),
    );
    await pumpLibrary(tester);
    await tester.tap(find.byTooltip('删除角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('豆豆'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_library_screen_test.dart`

Expected: 编译失败，`character_library_screen.dart` 不存在。

- [ ] **Step 3: 创建编辑页占位**

创建 `lib/screens/character_card_editor_screen.dart`（最小可编译，Task 5 整体替换）：

```dart
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/character_card.dart';
import '../services/book_engine_service.dart';
import '../services/character_storage_service.dart';

class CharacterCardEditorScreen extends StatefulWidget {
  final CharacterCard? card;
  final CharacterStorageService? storage;
  final BookEngineService? engine;
  final Future<AppSettings> Function()? loadSettings;

  const CharacterCardEditorScreen({
    super.key,
    this.card,
    this.storage,
    this.engine,
    this.loadSettings,
  });

  @override
  State<CharacterCardEditorScreen> createState() =>
      _CharacterCardEditorScreenState();
}

class _CharacterCardEditorScreenState extends State<CharacterCardEditorScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.card == null ? '新建角色' : '编辑角色')),
      body: const Center(child: Text('编辑页将在下一任务实现')),
    );
  }
}
```

- [ ] **Step 4: 实现角色库页**

创建 `lib/screens/character_library_screen.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/character_card.dart';
import '../services/character_storage_service.dart';
import 'character_card_editor_screen.dart';

class CharacterLibraryScreen extends StatefulWidget {
  final CharacterStorageService? storage;

  const CharacterLibraryScreen({super.key, this.storage});

  @override
  State<CharacterLibraryScreen> createState() => _CharacterLibraryScreenState();
}

class _CharacterLibraryScreenState extends State<CharacterLibraryScreen> {
  late final CharacterStorageService _storage;
  List<CharacterCard> _cards = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? CharacterStorageService();
    _load();
    CharacterStorageService.cardsChangedNotifier.addListener(_load);
  }

  @override
  void dispose() {
    CharacterStorageService.cardsChangedNotifier.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cards = await _storage.loadCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '加载角色库失败: $e';
      });
    }
  }

  Future<void> _openEditor([CharacterCard? card]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterCardEditorScreen(card: card, storage: _storage),
      ),
    );
  }

  Future<void> _confirmDelete(CharacterCard card) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除角色「${card.name}」'),
        content: const Text('角色卡和它的定妆图将被删除。已生成的绘本不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _storage.deleteCard(card.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _kindLabel(CharacterKind kind) => switch (kind) {
        CharacterKind.human => '人类',
        CharacterKind.animal => '动物',
        CharacterKind.object => '物件',
      };

  /// 缩略图优先级：默认画风定妆图 → 任意定妆图 → 照片 → 占位图标。
  String? _thumbnailPath(CharacterCard card) {
    if (card.anchorImagePaths.containsKey('watercolor')) {
      return card.anchorImagePaths['watercolor'];
    }
    if (card.anchorImagePaths.isNotEmpty) {
      return card.anchorImagePaths.values.first;
    }
    return card.photoPath;
  }

  Widget _thumbnail(CharacterCard card) {
    final relative = _thumbnailPath(card);
    if (relative == null) {
      return const Center(
        child: Icon(Icons.face_retouching_natural, size: 48, color: Colors.grey),
      );
    }
    return FutureBuilder<File>(
      future: _storage.imageFile(relative),
      builder: (ctx, snap) {
        final file = snap.data;
        if (file == null || !file.existsSync()) {
          return const Center(
            child: Icon(Icons.broken_image_outlined, size: 40, color: Colors.grey),
          );
        }
        return Image.file(file, fit: BoxFit.cover);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('👥 我的角色')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新建角色'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? _buildError()
                  : _cards.isEmpty
                      ? _buildEmpty()
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 200,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: _cards.length,
                          itemBuilder: (ctx, i) => _buildCard(_cards[i]),
                        ),
        ),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.face_retouching_natural, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('还没有角色', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('创建第一个角色'),
            ),
          ],
        ),
      );

  Widget _buildCard(CharacterCard card) => Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          onTap: () => _openEditor(card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _thumbnail(card)),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_kindLabel(card.kind)} · 定妆图 ${card.anchorImagePaths.length} 张',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '删除角色',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: Colors.grey,
                      onPressed: () => _confirmDelete(card),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_library_screen_test.dart && $HOME/development/flutter/bin/flutter analyze`

Expected: 4 tests passed；analyze 无新增问题。若「删除后卡片消失」偶发失败，把 `runIo` 的等待从 300ms 提到 600ms。

- [ ] **Step 6: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/screens/character_library_screen.dart lib/screens/character_card_editor_screen.dart test/character_library_screen_test.dart && git commit -m "feat(character-card): add character library screen with grid and delete confirmation

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: 角色卡编辑页：表单与保存

**Files:**
- Modify: `lib/screens/character_card_editor_screen.dart`（整体替换 Task 4 的占位）
- Test: `test/character_card_editor_screen_test.dart`

**Interfaces:**
- Consumes: `CharacterStorageService.saveCard / clearAnchors / imageFile`（Task 2、3）；`CharacterCard.newId / toJson / fromJson`（Task 1）；`StyleCatalog.styles`（`lib/models/style_catalog.dart`，首项 id `watercolor` 名 `水彩童话`）
- Produces: 完整的 `CharacterCardEditorScreen`（签名同 Task 4 占位）。本任务实现表单、保存、外貌变更失效确认、画风选择与定妆图预览；「生成定妆图」按钮在 Task 6 接上引擎，本任务先让它弹一条「下一任务实现」提示，保证页面可用。

- [ ] **Step 1: 写失败的测试**

创建 `test/character_card_editor_screen_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/character_card_editor_screen.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在真实事件循环里执行会产生文件 IO / 网络的操作，随后回到测试时钟刷新界面。
Future<void> runIo(WidgetTester tester, Future<void> Function() body) async {
  await tester.runAsync(() async {
    await body();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
}

List<Map<String, dynamic>> readCards(Directory dir) =>
    (jsonDecode(File('${dir.path}/cards.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

/// 伪造 Gemini 多模态生图响应，并记录请求体。
Dio fakeGeminiImageDio(String base64Png, List<dynamic> sentBodies) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        sentBodies.add(options.data);
        handler.resolve(
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
        );
      },
    ),
  );

void main() {
  late Directory dir;
  late CharacterStorageService storage;
  final pngBase64 = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bookbuddy-editor-test-');
    storage = CharacterStorageService(directory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    CharacterCard? card,
    BookEngineService? engine,
    AppSettings? settings,
  }) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 从一个占位页 push 进入编辑页，保证「保存后返回」有可返回的路由。
    await runIo(tester, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => CharacterCardEditorScreen(
                        card: card,
                        storage: storage,
                        engine: engine,
                        loadSettings: () async => settings ?? AppSettings(),
                      ),
                    ),
                  ),
                  child: const Text('打开编辑页'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开编辑页'));
    });
  }

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextField, '角色名 *'), '豆豆');
    await tester.enterText(
      find.widgetWithText(TextField, '外貌锚定描述 *（颜色、材质、体型、标志性细节）'),
      '绿色毛绒恐龙，肚皮米白',
    );
    await tester.pump();
  }

  testWidgets('角色名或外貌为空时不能保存', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请填写角色名和外貌'), findsOneWidget);
    expect(File('${dir.path}/cards.json').existsSync(), isFalse);
  });

  testWidgets('填写必填项后保存落盘并返回', (tester) async {
    await pumpEditor(tester);
    await fillRequired(tester);
    await tester.enterText(find.widgetWithText(TextField, '口头禅'), '冲啊！');
    await tester.tap(find.text('物件'));
    await tester.pump();

    await runIo(tester, () => tester.tap(find.text('保存')));

    final saved = readCards(dir).single;
    expect(saved['name'], '豆豆');
    expect(saved['appearance'], '绿色毛绒恐龙，肚皮米白');
    expect(saved['catchphrase'], '冲啊！');
    expect(saved['kind'], 'object');
    expect(saved['source'], 'manual');
    expect((saved['id'] as String).startsWith('card_'), isTrue);
    expect(find.byType(CharacterCardEditorScreen), findsNothing);
    expect(find.text('打开编辑页'), findsOneWidget);
  });

  testWidgets('编辑已有卡片时表单预填且保存为更新', (tester) async {
    final card = CharacterCard(
      id: 'card_a',
      name: '豆豆',
      species: '毛绒恐龙',
      appearance: '绿色',
      personality: '勇敢',
    );
    await tester.runAsync(() => storage.saveCard(card));
    await pumpEditor(tester, card: card);
    expect(find.text('编辑角色：豆豆'), findsOneWidget);
    expect(find.text('毛绒恐龙'), findsOneWidget);
    expect(find.text('勇敢'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '性格'), '勇敢又贪吃');
    await runIo(tester, () => tester.tap(find.text('保存')));
    final cards = readCards(dir);
    expect(cards, hasLength(1));
    expect(cards.single['personality'], '勇敢又贪吃');
  });

  testWidgets('修改外貌后保存需确认，确认后清空定妆图', (tester) async {
    final card = CharacterCard(id: 'card_a', name: '豆豆', appearance: '绿色');
    await tester.runAsync(() async {
      await storage.saveCard(card);
      await storage.saveAnchor('card_a', 'watercolor', pngBase64);
    });
    final reloaded = CharacterCard.fromJson(readCards(dir).single);
    await pumpEditor(tester, card: reloaded);

    await tester.enterText(
      find.widgetWithText(TextField, '外貌锚定描述 *（颜色、材质、体型、标志性细节）'),
      '蓝色',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('外貌设定已修改'), findsOneWidget);
    expect(find.text('已有 1 张定妆图将被清空，下次使用时重新生成。'), findsOneWidget);

    await runIo(tester, () => tester.tap(find.text('清空并保存')));
    final saved = readCards(dir).single;
    expect(saved['appearance'], '蓝色');
    expect(saved['anchorImagePaths'], isEmpty);
    expect(File('${dir.path}/card_a/anchor_watercolor.png').existsSync(), isFalse);
  });

  testWidgets('只改性格不触发定妆图失效确认', (tester) async {
    final card = CharacterCard(id: 'card_a', name: '豆豆', appearance: '绿色');
    await tester.runAsync(() async {
      await storage.saveCard(card);
      await storage.saveAnchor('card_a', 'watercolor', pngBase64);
    });
    await pumpEditor(tester, card: CharacterCard.fromJson(readCards(dir).single));
    await tester.enterText(find.widgetWithText(TextField, '性格'), '温柔');
    await runIo(tester, () => tester.tap(find.text('保存')));
    expect(find.text('外貌设定已修改'), findsNothing);
    final saved = readCards(dir).single;
    expect(saved['personality'], '温柔');
    expect(saved['anchorImagePaths'], {'watercolor': 'card_a/anchor_watercolor.png'});
  });

  // ---- 以下两条属于 Task 6，本任务结束时它们会失败 ----

  testWidgets('Imagen 默认通道点击生成定妆图弹出不支持参考图对话框', (tester) async {
    final settings = AppSettings(imageApiKey: 'test-key');
    await pumpEditor(tester, settings: settings);
    await fillRequired(tester);

    await runIo(tester, () => tester.tap(find.text('生成水彩童话定妆图')));
    expect(find.text('当前生图通道不支持参考图'), findsOneWidget);
    expect(find.text('仍然生成'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final saved = readCards(dir).single;
    expect(saved['name'], '豆豆');
    expect(saved['anchorImagePaths'], isEmpty);
  });

  testWidgets('支持参考图的通道生成定妆图并写回卡片', (tester) async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeGeminiImageDio(pngBase64, sent));
    final settings = AppSettings(
      imageType: 'gemini',
      imageApiKey: 'test-key',
      imageModel: 'gemini-2.5-flash-image',
    );
    await pumpEditor(tester, engine: engine, settings: settings);
    await fillRequired(tester);

    await runIo(tester, () => tester.tap(find.text('生成水彩童话定妆图')));

    expect(find.text('定妆图已保存，请检查外貌是否符合预期'), findsOneWidget);
    final saved = readCards(dir).single;
    final id = saved['id'] as String;
    expect(saved['anchorImagePaths'], {'watercolor': '$id/anchor_watercolor.png'});
    expect(File('${dir.path}/$id/anchor_watercolor.png').existsSync(), isTrue);
    expect(sent, hasLength(1));
    final promptText = jsonEncode(sent.single);
    expect(promptText, contains('豆豆'));
    expect(promptText, contains('绿色毛绒恐龙'));
    expect(find.text('重新生成水彩童话定妆图'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_card_editor_screen_test.dart`

Expected: 前 5 条失败（占位页没有表单）；后 2 条也失败。

- [ ] **Step 3: 实现编辑页（不含引擎调用）**

整体替换 `lib/screens/character_card_editor_screen.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/character_card.dart';
import '../models/style_catalog.dart';
import '../services/book_engine_service.dart';
import '../services/character_storage_service.dart';
import '../services/settings_service.dart';

/// 角色卡新建 / 编辑页。card 为空表示新建。
class CharacterCardEditorScreen extends StatefulWidget {
  final CharacterCard? card;
  final CharacterStorageService? storage;
  final BookEngineService? engine;
  final Future<AppSettings> Function()? loadSettings;

  const CharacterCardEditorScreen({
    super.key,
    this.card,
    this.storage,
    this.engine,
    this.loadSettings,
  });

  @override
  State<CharacterCardEditorScreen> createState() =>
      _CharacterCardEditorScreenState();
}

class _CharacterCardEditorScreenState extends State<CharacterCardEditorScreen> {
  late final CharacterStorageService _storage;
  late final BookEngineService _engine;
  late final Future<AppSettings> Function() _loadSettings;

  /// 工作副本：编辑模式下是传入卡片的深拷贝，保存前不影响原对象。
  late CharacterCard _card;
  late bool _isNew;

  /// 上次保存时的外貌相关字段快照，用来判断是否需要清空定妆图。
  late String _savedLook;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _speciesCtrl;
  late final TextEditingController _appearanceCtrl;
  late final TextEditingController _outfitCtrl;
  late final TextEditingController _personalityCtrl;
  late final TextEditingController _catchphraseCtrl;
  CharacterKind _kind = CharacterKind.animal;
  String _styleId = 'watercolor';

  bool _busy = false;
  String _busyText = '';

  /// 本次会话刚生成的定妆图字节，优先于磁盘文件显示，避免图片缓存显示旧图。
  final Map<String, Uint8List> _freshAnchors = {};

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? CharacterStorageService();
    _engine = widget.engine ?? BookEngineService();
    _loadSettings = widget.loadSettings ?? SettingsService().loadSettings;
    _isNew = widget.card == null;
    _card = widget.card == null
        ? CharacterCard(id: CharacterCard.newId(), name: '', appearance: '')
        : CharacterCard.fromJson(widget.card!.toJson());
    _kind = _card.kind;
    _nameCtrl = TextEditingController(text: _card.name);
    _speciesCtrl = TextEditingController(text: _card.species);
    _appearanceCtrl = TextEditingController(text: _card.appearance);
    _outfitCtrl = TextEditingController(text: _card.defaultOutfit);
    _personalityCtrl = TextEditingController(text: _card.personality);
    _catchphraseCtrl = TextEditingController(text: _card.catchphrase);
    _savedLook = _lookOf(_card);
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _speciesCtrl,
      _appearanceCtrl,
      _outfitCtrl,
      _personalityCtrl,
      _catchphraseCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _lookOf(CharacterCard c) =>
      '${c.kind.name}|${c.species}|${c.appearance}|${c.defaultOutfit}';

  /// 把表单写回工作副本；返回校验错误文案，null 表示通过。
  String? _applyForm() {
    _card
      ..name = _nameCtrl.text.trim()
      ..kind = _kind
      ..species = _speciesCtrl.text.trim()
      ..appearance = _appearanceCtrl.text.trim()
      ..defaultOutfit = _outfitCtrl.text.trim()
      ..personality = _personalityCtrl.text.trim()
      ..catchphrase = _catchphraseCtrl.text.trim();
    if (_card.name.isEmpty || _card.appearance.isEmpty) {
      return '请填写角色名和外貌';
    }
    return null;
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  /// 校验 → 外貌变更时确认清空定妆图 → 落盘。返回是否成功。
  Future<bool> _save() async {
    final error = _applyForm();
    if (error != null) {
      _toast(error, error: true);
      return false;
    }
    final lookChanged = _lookOf(_card) != _savedLook;
    if (lookChanged && _card.anchorImagePaths.isNotEmpty) {
      final count = _card.anchorImagePaths.length;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('外貌设定已修改'),
          content: Text('已有 $count 张定妆图将被清空，下次使用时重新生成。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空并保存'),
            ),
          ],
        ),
      );
      if (confirm != true) return false;
      try {
        await _storage.clearAnchors(_card.id);
      } catch (e) {
        _toast('清空定妆图失败: $e', error: true);
        return false;
      }
      _card.anchorImagePaths.clear();
      _freshAnchors.clear();
    }
    try {
      await _storage.saveCard(_card);
    } catch (e) {
      _toast('保存失败: $e', error: true);
      return false;
    }
    _isNew = false;
    _savedLook = _lookOf(_card);
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _saveAndClose() async {
    if (await _save() && mounted) {
      Navigator.pop(context, _card);
    }
  }

  Future<void> _generateAnchor() async {
    _toast('定妆图生成将在下一任务实现');
  }

  @override
  Widget build(BuildContext context) {
    final style = StyleCatalog.styles.firstWhere((s) => s.id == _styleId);
    final anchorPath = _card.anchorImagePaths[_styleId];
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建角色' : '编辑角色：${_card.name}'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _saveAndClose,
            icon: const Icon(Icons.check),
            label: const Text('保存'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  _busyText,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
              ],
              _sectionTitle('🧸 基本设定'),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '角色名 *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<CharacterKind>(
                segments: const [
                  ButtonSegment(
                    value: CharacterKind.human,
                    label: Text('人类'),
                    icon: Icon(Icons.person_outline),
                  ),
                  ButtonSegment(
                    value: CharacterKind.animal,
                    label: Text('动物'),
                    icon: Icon(Icons.pets),
                  ),
                  ButtonSegment(
                    value: CharacterKind.object,
                    label: Text('物件'),
                    icon: Icon(Icons.toys_outlined),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: _busy
                    ? null
                    : (selection) => setState(() => _kind = selection.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _speciesCtrl,
                decoration: const InputDecoration(
                  labelText: '物种或物件名（如：毛绒恐龙、石头、小猫）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _appearanceCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '外貌锚定描述 *（颜色、材质、体型、标志性细节）',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _outfitCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '默认服装（可留空）',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle('💬 性格与口头禅'),
              TextField(
                controller: _personalityCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '性格',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _catchphraseCtrl,
                decoration: const InputDecoration(
                  labelText: '口头禅',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle('🎨 定妆图画风'),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: StyleCatalog.styles
                    .map(
                      (s) => ChoiceChip(
                        label: Text(s.name),
                        selected: s.id == _styleId,
                        avatar: _card.anchorImagePaths.containsKey(s.id)
                            ? const Icon(Icons.check_circle, size: 16)
                            : null,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _styleId = s.id),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              _buildAnchorPreview(anchorPath),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _generateAnchor,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  anchorPath == null
                      ? '生成${style.name}定妆图'
                      : '重新生成${style.name}定妆图',
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                '修改角色卡只影响之后新建的绘本。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      );

  Widget _buildAnchorPreview(String? anchorPath) {
    final fresh = _freshAnchors[_styleId];
    final Widget child;
    if (fresh != null) {
      child = Image.memory(fresh, fit: BoxFit.contain);
    } else if (anchorPath == null) {
      child = const Center(
        child: Text('还没有这个画风的定妆图', style: TextStyle(color: Colors.grey)),
      );
    } else {
      child = FutureBuilder<File>(
        future: _storage.imageFile(anchorPath),
        builder: (ctx, snap) {
          final file = snap.data;
          if (file == null || !file.existsSync()) {
            return const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.grey),
            );
          }
          return Image.file(file, fit: BoxFit.contain);
        },
      );
    }
    return Container(
      height: 260,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: child,
    );
  }
}
```

- [ ] **Step 4: 运行前 5 条测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_card_editor_screen_test.dart --name "不能保存|落盘并返回|预填|确认后清空|只改性格" && $HOME/development/flutter/bin/flutter analyze`

Expected: 5 tests passed；analyze 无新增问题（`_engine` 与 `_loadSettings` 暂未使用会有 `unused_field` 提示，Task 6 会用到；若 analyze 把它算作 warning 导致失败，临时在两个字段声明上方加 `// ignore: unused_field`，Task 6 删除）。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/screens/character_card_editor_screen.dart test/character_card_editor_screen_test.dart && git commit -m "feat(character-card): add card editor form with save and anchor invalidation confirm

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: 编辑页：生成定妆图（含通道前置检查）

**Files:**
- Modify: `lib/screens/character_card_editor_screen.dart`（替换 `_generateAnchor`，补 import）
- Test: `test/character_card_editor_screen_test.dart`（Task 5 中最后两条用例）

**Interfaces:**
- Consumes:
  - `BookEngineService.supportsCharacterReference({required String type, required String baseUrl, required String model}) → bool`（`lib/services/book_engine_service.dart:292`）
  - `BookEngineService.generateCharacterReference({required AppSettings settings, required BookStyle style, required BookCharacter character}) → Future<String?>`（`:303`）
  - `AppSettings.imageApiKey / imageType / imageBaseUrl / imageModel` getters
  - `CharacterStorageService.saveAnchor`（Task 3）
  - `SettingsScreen()`（`lib/screens/settings_screen.dart`，const 构造）
  - `WakelockPlus.enable() / disable()`
- Produces: 完整的 `_generateAnchor` 流程

- [ ] **Step 1: 运行两条目标测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_card_editor_screen_test.dart --name "Imagen|写回卡片"`

Expected: 2 failed（点击后只出现「定妆图生成将在下一任务实现」）。

- [ ] **Step 2: 实现生成流程**

在 `lib/screens/character_card_editor_screen.dart` 的 import 区加入：

```dart
import 'dart:convert';

import 'package:wakelock_plus/wakelock_plus.dart';

import 'settings_screen.dart';
```

（保持现有 import 顺序：dart 库 → package → 相对路径。）删除 Task 5 可能加的 `// ignore: unused_field`。把 `_generateAnchor` 整体替换为：

```dart
  /// 校验并保存 → 读设置 → 通道前置检查 → 生成 → 落盘并写回卡片映射。
  Future<void> _generateAnchor() async {
    if (!await _save()) return;

    final AppSettings settings;
    try {
      settings = await _loadSettings();
    } catch (e) {
      _toast('读取设置失败: $e', error: true);
      return;
    }
    if (settings.imageApiKey.isEmpty) {
      _toast('请先在设置中配置生图 API Key', error: true);
      return;
    }

    final supportsReference = _engine.supportsCharacterReference(
      type: settings.imageType,
      baseUrl: settings.imageBaseUrl,
      model: settings.imageModel,
    );
    if (!supportsReference) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('当前生图通道不支持参考图'),
          content: const Text(
            '定妆图只能按文字生成，后续绘本每页可能出现外貌不一致。'
            '建议切换到 Gemini 图像模型（如 gemini-2.5-flash-image）或腾讯混元。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'settings'),
              child: const Text('去设置'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'proceed'),
              child: const Text('仍然生成'),
            ),
          ],
        ),
      );
      if (choice == 'settings' && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        return;
      }
      if (choice != 'proceed') return;
    }

    final style = StyleCatalog.styles.firstWhere((s) => s.id == _styleId);
    final styleId = _styleId;
    setState(() {
      _busy = true;
      _busyText = '正在绘制 ${_card.name} 的${style.name}定妆图...';
    });
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // 桌面 / 测试环境可能没有插件实现。
    }
    try {
      final image = await _engine.generateCharacterReference(
        settings: settings,
        style: style,
        character: _card.toBookCharacter(),
      );
      if (image == null || image.isEmpty) {
        throw StateError('生图接口未返回图片');
      }
      final path = await _storage.saveAnchor(_card.id, styleId, image);
      _card.anchorImagePaths[styleId] = path;
      _freshAnchors[styleId] = base64Decode(
        image.startsWith('data:')
            ? image.substring(image.indexOf(',') + 1)
            : image,
      );
      _toast('定妆图已保存，请检查外貌是否符合预期');
    } catch (e) {
      _toast('定妆图生成失败: $e', error: true);
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }
```

- [ ] **Step 3: 运行全部编辑页测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_card_editor_screen_test.dart && $HOME/development/flutter/bin/flutter analyze`

Expected: 7 tests passed；analyze 无新增问题。若「写回卡片」用例因 IO 未完成偶发失败，把 `runIo` 的等待提到 600ms。

- [ ] **Step 4: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/screens/character_card_editor_screen.dart test/character_card_editor_screen_test.dart && git commit -m "feat(character-card): generate per-style anchor portraits with channel precheck

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: 首页入口、文档与全量验证

**Files:**
- Modify: `lib/main.dart`（import 区 `:1-9`；AppBar actions `:157-168`；引导卡之后 `:258`）
- Modify: `AGENTS.md`（第 4 节目录结构）
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `CharacterLibraryScreen`（Task 4）、`CharacterCardEditorScreen`（Task 5/6）

- [ ] **Step 1: 写失败的测试**

把 `test/widget_test.dart` 整体替换为：

```dart
import 'package:bookbuddy/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App load smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BookBuddyApp());
    expect(find.text('📖 BookBuddy 绘本工坊'), findsOneWidget);
  });

  testWidgets('首页显示角色引导卡与「我的角色」入口', (tester) async {
    await tester.pumpWidget(const BookBuddyApp());
    await tester.pumpAndSettle();
    expect(find.byTooltip('我的角色'), findsOneWidget);
    expect(find.text('给孩子做一个专属主角'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '我的角色'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '新建角色'), findsOneWidget);
  });

  testWidgets('点击「我的角色」进入角色库页', (tester) async {
    await tester.pumpWidget(const BookBuddyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('我的角色'));
    await tester.pumpAndSettle();
    expect(find.text('👥 我的角色'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/widget_test.dart`

Expected: 后 2 条失败（找不到 tooltip / 文案）。

说明：测试环境没有 path_provider 与 shared_preferences 插件，首页和角色库页都会走进各自的错误提示分支，加载指示器随之消失，所以 `pumpAndSettle` 能正常结束。若它超时，把该处改为连续两次 `await tester.pump();`。

- [ ] **Step 3: 修改首页**

`lib/main.dart` import 区（`:3-9`）新增两行，按字母序放在 `screens/book_reader_screen.dart` 之后：

```dart
import 'screens/character_card_editor_screen.dart';
import 'screens/character_library_screen.dart';
```

AppBar `actions`（`:157-168`）在设置图标**之前**插入：

```dart
          IconButton(
            tooltip: '我的角色',
            icon: const Icon(Icons.face_retouching_natural),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CharacterLibraryScreen()),
              );
            },
          ),
```

在第一张引导卡的 `Card(...)` 结束（`:258` 的 `),`）之后、`if (_errorMessage != null) ...[` 之前插入第二张引导卡：

```dart
                      const SizedBox(height: 12),
                      // 角色卡引导
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        color: const Color(0xFF23201B),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          child: Row(
                            children: [
                              const Icon(Icons.face_retouching_natural, size: 54, color: Color(0xFFD8A24A)),
                              const SizedBox(width: 20),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '给孩子做一个专属主角',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '创建可复用的角色卡，之后每本绘本都能请他出场',
                                      style: TextStyle(fontSize: 13, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFD8A24A),
                                      side: const BorderSide(color: Color(0xFFD8A24A)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    ),
                                    icon: const Icon(Icons.people_outline, size: 18),
                                    label: const Text('我的角色', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const CharacterLibraryScreen()),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD8A24A),
                                      foregroundColor: Colors.black87,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                    ),
                                    icon: const Icon(Icons.add),
                                    label: const Text('新建角色', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const CharacterCardEditorScreen()),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
```

- [ ] **Step 4: 更新 AGENTS.md 目录结构**

在 `AGENTS.md` 第 4 节的目录树里，`models/` 下 `book.dart` 之后加：

```
│   ├── character_card.dart            # 角色卡模型 (跨书复用主角：性格/口头禅/按画风缓存的定妆图路径)
```

`services/` 下 `book_storage_service.dart` 之后加：

```
│   ├── character_storage_service.dart # 角色库落盘 (bookbuddy_characters/：cards.json 元数据 + 图片文件)
```

`screens/` 下 `book_reader_screen.dart` 之后加：

```
    ├── character_library_screen.dart  # 角色库网格页
    ├── character_card_editor_screen.dart # 角色卡新建/编辑与定妆图生成页
```

- [ ] **Step 5: 全量验证**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter analyze && $HOME/development/flutter/bin/flutter test`

Expected: analyze 无新增问题；所有测试通过（原有 6 个测试文件 + 新增 4 个）。

- [ ] **Step 6: 手动验收（macOS）**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter run -d macos`

按 spec 第 10 节 P0 验收：首页点「新建角色」→ 填名字与外貌 → 生成水彩定妆图（需已配置支持参考图的生图通道；用 Imagen 时应先弹前置对话框）→ 切换到「日系动漫」再生成一张 → 返回角色库看到「定妆图 2 张」→ 完全退出 App 重开，卡片与两张定妆图仍在 → 编辑外貌并保存，弹出清空确认，确认后「定妆图 0 张」。

- [ ] **Step 7: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/main.dart AGENTS.md test/widget_test.dart && git commit -m "feat(character-card): add home entry points to the character library

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## 自检记录

**Spec 覆盖（P0 范围）**

| Spec 条目 | 任务 |
|---|---|
| 3.1 模型、`toBookCharacter`、物件后缀、未知值回退 | Task 1 |
| 4.1 目录结构、4.2 接口（含 `saveAnchor` 扩展名判断、串行写、`.bak` 恢复、删除连带目录） | Task 2、3 |
| 6.1 首页 AppBar 入口 + 第二张引导卡 | Task 7 |
| 6.2 网格、空状态、删除确认、通知刷新 | Task 4 |
| 6.3 表单、类型分段按钮、画风 chips、定妆图预览、生成/重生成、前置检查对话框、外貌变更失效确认、页脚提示 | Task 5、6 |
| 8 错误处理：无 Key、通道不支持、生成失败保留旧图、存储失败不清表单 | Task 6（`_toast` 分支）、Task 5（`_save` 失败返回 false） |
| 9 测试：模型 / 存储 / 编辑页 / 角色库 / 首页 | Task 1–7 |
| 10 P0 验收 | Task 7 Step 6 |

未纳入 P0（按 spec 明确推后）：3.2 `PictureBook.characterCardIds` 与「出演 N 本」（P1）；6.3 照片区、识别按钮、照片相关页脚文案（P3）；6.2 空状态「拍一张玩具」文案（P3）。

**类型一致性**：`saveAnchor` 返回 `Future<String>`（Task 3 定义，Task 6 使用返回值写入 `_card.anchorImagePaths`）；`imageFile` 返回 `Future<File>`（Task 3 定义，Task 4/5 的 `FutureBuilder<File>` 使用）；编辑页构造签名在 Task 4 占位与 Task 5 实现中一致。
