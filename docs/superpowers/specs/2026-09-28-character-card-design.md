# 角色卡系统设计：拍照 / 手动创建可复用主角，注入自定义绘本

> 状态：待用户评审 · 日期：2026-09-28 · 代码基线：`lib/` 14 个 dart 文件，`main` 分支 `f49691b`
> 本文取代并合并了此前的两份草稿 `docs/toy-character-feasibility.md` 与 `docs/character-card-design.md`。

---

## 0. 目标与非目标

**目标**

- 家长或孩子在独立页面里，拍一张玩具 / 宠物 / 石头的照片，或者手动描述，生成一张可保存、可编辑、可复用的**角色卡**（名字、类型、外貌、服装、性格、口头禅、定妆图）。
- 新建绘本时可以选择最多 3 张角色卡作为主角，并在自己写的故事里直接用名字称呼它们；大模型分镜时必须原样使用这些角色，生图时用定妆图锁定外貌。
- 角色卡是留存资产：可以重复出现在任意多本绘本中，跨书不换脸。
- 选好角色卡后，用一句简单描述让 AI 写出一篇儿童卡通故事；故事可以手动修改，也可以提出建议和补充让 AI 按新要求重写；满意后回填创建页，进入现有的分镜与生图流程。

**非目标（本轮不做，见第 11 节）**

- 多角色拼成一张分区参考图。
- 跨书连载记忆（上一本的摘要注入下一本）。
- 从已有绘本中反向提取角色卡。
- 桌面端调用摄像头拍照（桌面只支持选图）。

---

## 1. 已确定的产品决策

| # | 决策 | 结论 |
|---|---|---|
| 1 | 每本绘本最多几张角色卡 | **硬限 3 张**，以常量 `kMaxCharacterCardsPerBook = 3` 实现，实测后可调。配角由大模型生成，不占额度 |
| 2 | 编辑卡片后旧绘本是否变化 | **不变**。生成绘本时把卡片字段与定妆图**复制**为书内 `BookCharacter` 快照 |
| 3 | 定妆图与画风 | 定妆图**绑定画风**。卡片按 `styleId` 缓存多张定妆图；新书画风已有缓存直接用，没有则在审核页生成一次并**写回卡片** |
| 4 | 照片如何参与生成 | 照片是**身份来源**：识图时上传一次得到文字描述；每次为某个画风生成定妆图时，把照片作为参考图再上传一次，使定妆图贴近真实玩具。**故事页只带定妆图，永不带原照** |
| 5 | 参考图形态 | 每个角色一张定妆图、逐张文字标注（沿用现状）。不做多角色拼图 |
| 6 | 故事创作方式 | 独立的故事助手页：角色卡 + 一句描述 → 生成故事；可手改，可用反馈让 AI 重写（以编辑框现文本为基础，只改反馈涉及的部分）；「用这个故事」回填创建页，后续流程不变 |

---

## 2. 现状与复用点

| 现有能力 | 位置 | 本次用法 |
|---|---|---|
| `BookCharacter`（书内角色：名字 / 物种 / isAnimal / 外貌 / 默认服装 / 定妆图 base64） | `lib/models/book.dart:78` | 作为角色卡在书内的**快照载体**，字段不改 |
| `createStoryboardDraft` 从故事文本反推 `characters` + 每页 `characterIds` | `lib/services/book_engine_service.dart:50` | 新增"固定角色"入参与解析后对账 |
| `generateCharacterReference` 文生定妆图 | `book_engine_service.dart:303` | 新增可选照片参考入参 |
| `generateIllustration` 逐张注入出场角色参考图 + 缺图强校验 | `book_engine_service.dart:353` | 不改。卡片快照进入 `characters` 后自动生效 |
| `supportsCharacterReference` 通道能力探测 | `book_engine_service.dart:292` | 角色卡编辑页与创建页的前置检查 |
| `_callImageApi` 接受 `references` 列表（TokenHub / Gemini generateContent / OpenAI chat 降级） | `book_engine_service.dart:593` | 照片参考复用同一入口，仅改标注文字 |
| `_callLlm` 三协议文本调用 | `book_engine_service.dart:499` | 新增图片入参 |
| 分镜审核页：编辑角色、批量绘定妆图、缺图先补画再开始 | `lib/screens/storyboard_review_screen.dart:174,456` | 不改流程，新增"写回卡片"钩子 |
| `BookStorageService` 原子写（tmp → bak → rename）、变更通知、按目录注入便于测试 | `lib/services/book_storage_service.dart` | 角色库存储服务照抄结构 |
| `StyleCatalog` | `lib/models/style_catalog.dart` | 定妆图按 `styleId` 缓存 |

已确认的现状事实：

- `BookPageItem.imagePath` 全项目无人写入，插画以 base64 直接写进绘本 JSON。角色库**不能**沿用此做法。
- `pubspec.yaml` 无任何图像依赖；Android 仅声明 `INTERNET`；iOS `Info.plist` 无相机 / 相册说明；macOS entitlements 只有沙箱与网络，无文件读取权限。
- 默认生图配置 `img_gemini_default` 是 Imagen 3，`supportsCharacterReference` 对其返回 false。OpenAI `/images/generations` 请求体只有 `model + prompt(+size)`。这两类通道下**不报错但每页换脸**。

---

## 3. 数据模型

### 3.1 新增 `lib/models/character_card.dart`

```dart
const int kMaxCharacterCardsPerBook = 3;

enum CharacterCardSource { manual, photo }

/// 人类 / 动物 / 非生物物件（玩具、石头等拟人角色）
enum CharacterKind { human, animal, object }

class CharacterCard {
  final String id;                       // 'card_' + uuid 前 8 位，与书内 'c1/c2' 不冲突
  CharacterCardSource source;
  String name;
  CharacterKind kind;
  String species;                        // 动物：物种；物件：物件名（毛绒恐龙、石头）；人类可空
  String appearance;                     // 外貌锚定描述，生图文字约束的唯一来源
  String defaultOutfit;                  // 可空（石头人等）
  String personality;
  String catchphrase;
  Map<String, String> anchorImagePaths;  // styleId -> 相对角色库目录的文件路径
  String? photoPath;                     // 相对路径；仅 photo 来源
  DateTime createdAt;
  DateTime? lastUsedAt;

  bool get isAnimal => kind == CharacterKind.animal;

  /// 投影为书内快照。referenceImageBase64 由调用方按画风读文件后传入。
  BookCharacter toBookCharacter({String? referenceImageBase64});

  Map<String, dynamic> toJson();
  factory CharacterCard.fromJson(Map<String, dynamic> json);
}
```

- JSON 键与字段同名；`kind` / `source` 以字符串存储（`'human' | 'animal' | 'object'`，`'manual' | 'photo'`），未知值回退为 `human` / `manual`。
- `toBookCharacter` 规则：`id` 原样；`isAnimal = kind == animal`；`kind == object` 且 `defaultOutfit` 为空时，`appearance` 末尾追加固定后缀 `（非生物物件拟人化角色，不添加人类服饰和鞋靴）`，以规避现有提示词把非动物角色当人类穿衣的倾向。`BookCharacter` 模型不改。

### 3.2 `PictureBook` 新增一个字段

```dart
List<String> characterCardIds;   // 本书使用的角色卡 ID，默认 []
```

`toJson` / `fromJson` 对称；旧 JSON 缺此键时为空列表。用途：角色库页统计"出演过 N 本"、书架卡片角标、卡片删除前提示。

### 3.3 引擎侧辅助类型（`book_engine_service.dart` 内）

```dart
class PinnedCharacter {
  final CharacterCard card;
  final String? anchorBase64;   // 当前画风的定妆图，可能为空
  final String? photoBase64;    // 原照，仅用于生成定妆图
}

class CharacterCardDraft {      // 识图结果
  final String name, species, appearance, defaultOutfit, personality, catchphrase;
  final CharacterKind kind;
}

class LlmImageInput { final String base64; final String mimeType; }

class StoryDraftResult { final String title; final String story; }   // 故事助手输出
```

`StoryboardDraft` 不变。

---

## 4. 存储：`lib/services/character_storage_service.dart`

### 4.1 目录结构

```
<appDocuments>/bookbuddy_characters/
├── cards.json                      # 全部卡片元数据，不含任何图像数据
├── cards.json.bak / .tmp           # 与绘本存储相同的双保险
└── card_ab12cd34/
    ├── photo.jpg                   # 预处理后的原照（仅 photo 来源）
    ├── anchor_watercolor.png       # 按画风命名的定妆图
    └── anchor_pixar3d.png
```

### 4.2 接口

```dart
class CharacterStorageService {
  CharacterStorageService({Directory? directory});          // 测试注入临时目录
  static final ValueNotifier<int> cardsChangedNotifier;

  Future<List<CharacterCard>> loadCards();                  // 按 lastUsedAt ?? createdAt 倒序
  Future<void> saveCard(CharacterCard card);                // upsert，写 cards.json
  Future<void> deleteCard(String id);                       // 删元数据 + 整个 card_xxx 目录
  Future<String> writeImage(String cardId, String fileName, Uint8List bytes); // 返回相对路径
  Future<String?> readImageBase64(String relativePath);     // 不存在返回 null
  Future<void> saveAnchor(String cardId, String styleId, String base64Image); // 落盘并更新卡片映射
}
```

- `saveAnchor` 按字节头判断 PNG / JPEG 决定扩展名（复用 `_referenceMimeType` 的判断逻辑），文件名形如 `anchor_<styleId>.png` 或 `.jpg`；`anchorImagePaths` 存实际写入的相对路径。

- `cards.json` 是单文件，所有写操作串行化到一个待处理队列（照抄 `BookStorageService._pendingSaves` 思路，但只需一个 key）。
- 写入流程照抄 `_saveBookUnlocked`：tmp 落盘 → 校验旧文件可解析后改名 `.bak` → tmp 改名正式；读取时主文件坏则读 `.bak`。
- 删除卡片**不**触碰任何绘本文件；已生成的书持有自己的快照。
- 图像文件读取只在两个时刻发生：列表页渲染缩略图（`Image.file`），以及创建绘本时把当前画风的定妆图读成 base64 注入快照。

---

## 5. 引擎改造（`lib/services/book_engine_service.dart`）

### 5.1 `_callLlm` 支持图片输入

新增 `List<LlmImageInput> images = const []`。三种协议分别：

| 协议 | 变化 |
|---|---|
| Gemini | `parts` 里在文本之前追加 `{'inlineData': {'mimeType', 'data'}}` |
| OpenAI 兼容 | user `content` 由字符串变为数组：`{'type':'image_url','image_url':{'url':'data:<mime>;base64,<data>'}}` + `{'type':'text','text': userPrompt}`。无图片时保持字符串，避免影响现有网关 |
| Anthropic | user `content` 变为数组：`{'type':'image','source':{'type':'base64','media_type','data'}}` + `{'type':'text','text'}` |

激活模型不支持视觉时（如 `deepseek-chat`），上游错误原样抛出，由页面展示。不做能力猜测。

同时新增 `double? temperature` 入参：Gemini 分支写入 `temperature ?? 0.3`（保持现状）；OpenAI / Anthropic 分支仅在非空时写入 `temperature` 键，避免改变现有网关行为。分镜生成不传，故事助手传 `0.8`。

### 5.2 新增 `describeCharacterFromPhoto`

```dart
Future<CharacterCardDraft> describeCharacterFromPhoto({
  required AppSettings settings,
  required String photoBase64,
  required String mimeType,
});
```

系统提示词要点：这是一张儿童玩具 / 宠物 / 日常物件的照片，请把它设计成一个适合 3 到 8 岁儿童绘本的拟人角色；输出合法 JSON，键为 `name, kind(human|animal|object), species, appearance, defaultOutfit, personality, catchphrase`；`appearance` 必须是可直接绘制的具体外貌（颜色、材质、体型、标志性细节），不写背景；名字亲切易读，2 到 4 个汉字；口头禅一句、不超过 12 字；`kind` 按实物判断：毛绒动物玩具与真实动物都算 `animal`，石头、机器人、汽车等算 `object`。解析沿用 `_extractJson`，任一必填键缺失即抛 `FormatException('识图结果格式不正确')`。

### 5.3 `generateCharacterReference` 支持照片参考

新增 `String? photoReferenceBase64`。`_ImageReference` 增加 `final bool isPhoto`。当通道 `supportsCharacterReference` 为真且传入了照片，参考列表加入 `_ImageReference(card.name, photo, isPhoto: true)`；三条生图分支里参考图的标注文字按 `isPhoto` 切换：

- 定妆照（现状）："上一张图片是 X 的定妆照。只将其用于此角色的外貌和默认服装，不复制背景、姿势或朝向。"
- 照片（新增）："上一张图片是 X 的真实玩具 / 物件照片。请按照片中的外形、颜色、材质和标志性细节绘制这个角色，并转换为当前绘本画风；忽略照片的背景、光线和拍摄角度。"

通道不支持参考图时忽略照片，只按文字生成；调用方负责事先提示用户。

### 5.4 `createStoryboardDraft` 支持固定角色

新增 `List<PinnedCharacter> pinnedCharacters = const []`，超过 `kMaxCharacterCardsPerBook` 抛 `ArgumentError`。

**提示词注入**：在现有系统提示词末尾追加一段（仅在有固定角色时）：

```
【固定角色，必须原样使用】
以下角色已经存在，必须使用给定的 id、名字、物种、外貌与默认服装，不得改名、不得重新设计外貌、不得更换物种：
- id: card_ab12cd34｜名字：豆豆｜类型：动物｜物种：毛绒恐龙｜外貌：...｜默认服装：...｜性格：...｜口头禅：...
要求：
1. characters 中必须包含上述每个角色，id 原样输出；可以另外新增配角（用 c1、c2 编号）。
2. 故事需要主角时优先使用上述角色；每个固定角色至少出现在一个镜头的 characterIds 中。
3. 口头禅要自然地出现在该角色至少一页的 text 里；性格要体现在 action 与 emotion 的描写中。
```

**解析后对账**（新增私有方法 `_reconcilePinned`，在现有解析之后执行）：

1. **覆盖**：对每个固定角色，`characters` 中同 id 的条目用卡片字段（`toBookCharacter`）整体替换；不存在则插入到列表最前。
2. **合并同名**：若大模型另造了一个 id 不同、`name` 相同（trim 后精确匹配）的角色，删除该条目，并把所有页面 `characterIds`、`outfitOverrides`、`groups` 中对它的引用改写为卡片 id。
3. **补漏**：若某个固定角色不在任何页面的 `characterIds` 中，扫描每页 `text + action + emotion + composition`，包含该角色名字的页面补入其 id。
4. **失败**：补漏后仍无任何页面出场，抛 `StateError('角色卡「豆豆」没有出现在任何分镜中。请在故事里写到它，或取消选择该角色卡。')`。不静默生成新主角。
5. `referenceImageBase64` 赋值为 `PinnedCharacter.anchorBase64`（可能为空，交由审核页补画）。

现有 `validateSceneCast` 的按名字校验对卡片角色同样生效，不改。

### 5.5 新增 `composeStory`（故事创作助手）

```dart
Future<StoryDraftResult> composeStory({
  required AppSettings settings,
  required List<CharacterCard> cards,   // 0 ~ 3 张，超出抛 ArgumentError
  required String brief,                // 用户的简单描述与要求，必填
  String? currentStory,                 // 为空 = 首次生成；非空 = 以此版本为基础修改
  String? feedback,                     // 用户对当前版本的建议与补充
});
```

系统提示词要点：

- 身份：面向 3 到 8 岁儿童的卡通故事作者；语言温暖、有画面感、朗读顺畅；不出现恐怖、暴力、说教或成人话题。
- 角色使用：逐条列出卡片的名字、类型、物种、外貌、性格、口头禅；名字与设定必须原样使用，每个角色的口头禅至少自然出现一次，性格通过行为和对话体现。没有卡片时按描述自行设计角色。
- 结构：开端、一个小冲突或小任务、转折、温暖收尾；正文 400 到 700 字；分 8 到 12 个自然段，每段是一个可以画出来的场景，为后续分镜留好接口。
- 输出：合法 JSON `{"title": "...", "story": "..."}`。
- 修改模式（`currentStory` 非空）：用户消息附上当前故事全文与反馈，要求「只修改反馈涉及的部分，其余保持原文不动；若反馈明确要求整体重写则可以重写」，输出同一 JSON。调用方传入的 `currentStory` 是编辑框中的现文本，因此用户的手动修改自然成为下一轮的基础。
- `temperature` 0.8。

解析：`_extractJson`；缺 `story` 键抛 `FormatException('故事生成结果格式不正确')`；`title` 缺失时取正文首句前 12 个字兜底。

---

## 6. 页面

### 6.1 首页 `lib/main.dart`

- AppBar 在设置图标左侧新增 `IconButton(Icons.face_retouching_natural)`，tooltip「我的角色」，进入角色库页。
- 现有"创作一本全新的精美绘本"引导卡下方新增同款引导卡：「拍一张玩具，做一个专属主角」，点击进入角色卡编辑页（新建模式）。
- 书架卡片：若 `characterCardIds` 非空，在封面角落显示一个小人图标角标。

### 6.2 角色库页 `lib/screens/character_library_screen.dart`

- 网格展示所有卡片：定妆图缩略图（优先当前默认画风 `watercolor`，否则任意一张，否则照片，否则占位图标）、名字、类型标签、「出演 N 本」（按绘本 `characterCardIds` 统计，进入页面时读一次书架）。
- 空状态：插画占位 + 「还没有角色，拍一张玩具试试」按钮。
- 右下 FAB「新建角色」；点击卡片进入编辑页；卡片菜单「删除」需二次确认，文案注明「已生成的绘本不受影响」。
- 监听 `cardsChangedNotifier` 自动刷新。

### 6.3 角色卡编辑页 `lib/screens/character_card_editor_screen.dart`

新建与编辑共用，纵向分区：

1. **照片区**：已有照片则显示；按钮「拍照」（仅 Android / iOS 显示）、「从相册选择」（全平台）、「移除照片」。选图后立即做第 7 节的预处理并落盘到卡片目录。
2. **识别按钮**：有照片时可用，「让 AI 认识它」→ 调 `describeCharacterFromPhoto` → 结果填入表单（已手填的字段弹确认是否覆盖）。
3. **表单**：名字（必填）、类型（人类 / 动物 / 物件 分段按钮）、物种或物件名、外貌（必填，多行）、默认服装、性格、口头禅。
4. **画风**：`StyleCatalog` ChoiceChips，默认 `watercolor`；切换时定妆图区跟随显示该画风的缓存。
5. **定妆图区**：显示当前画风定妆图或空占位；按钮「生成定妆图」/「重新生成」。点击前做**前置检查**：`supportsCharacterReference` 为假时弹对话框「当前生图通道不支持参考图。定妆图只能按文字生成，照片不会被参考，且后续绘本每页可能出现外貌不一致。建议切换到 Gemini 图像模型或腾讯混元。」按钮「仍然生成」「去设置」「取消」。生成期间开启 `WakelockPlus`，成功后 `saveAnchor` 落盘。
6. **保存**：名字与外貌非空即可保存，定妆图非必需（可在创建绘本时补画）。
7. **编辑失效规则**：修改 `kind / species / appearance / defaultOutfit` 任一项并保存时，弹确认「外貌设定已修改，已有 N 张定妆图将被清空，下次使用时重新生成」；确认后删除全部定妆图文件并清空映射。修改名字 / 性格 / 口头禅不影响定妆图。
8. 页面底部固定一行小字：「照片只保存在本机；只在「让 AI 认识它」和生成定妆图时上传给你配置的模型服务，故事分镜和故事页不会上传照片。修改角色卡只影响之后新建的绘本。」

### 6.4 创建绘本页 `lib/screens/create_book_screen.dart`

- 在"故事正文"上方新增区块「👥 选择角色卡（可选，最多 3 张）」：水平滚动头像列表，多选，达上限后其余置灰并提示。角色库为空时显示「去创建角色」链接。
- 已选角色下方列出「名字 · 口头禅」，并提示「在故事里直接用名字称呼他们」。
- 画风切换时，若某张已选卡片没有该画风定妆图，在画风区下方显示一行提示「进入审核后会先为 豆豆 绘制该画风的定妆照」。
- 点击生成：为每张已选卡片读取当前画风定妆图 base64 与照片 base64 组成 `PinnedCharacter`，传入 `createStoryboardDraft`；对账失败的 `StateError` 以 SnackBar 展示原文。
- 跳转审核页时额外传 `pinnedCharacters` 与 `characterCardIds`。
- 「📖 故事正文」标题行新增按钮「✨ 让 AI 按角色写故事」，带着当前已选角色卡进入 6.7 故事助手页；返回结果非空时回填标题与正文（正文已有内容时先弹确认是否覆盖）。

### 6.5 分镜审核页 `lib/screens/storyboard_review_screen.dart`

- 构造参数新增 `List<PinnedCharacter> pinnedCharacters = const []`；`_currentDraft()` 写入 `characterCardIds`。草稿首次落盘时把所有固定角色卡的 `lastUsedAt` 更新为当前时间。
- `_prepareCharacterReferences` 流程不变；对 id 属于卡片的角色，调用 `generateCharacterReference` 时附带 `photoReferenceBase64`；成功后除赋给书内角色外，**写回卡片**：`CharacterStorageService.saveAnchor(cardId, style.id, image)` 并更新 `lastUsedAt`。写回失败只记录日志并提示，不阻断绘本生成。
- 在审核页内编辑卡片来源角色的设定，只改书内快照，不写回卡片；界面在该角色卡片上显示「来自角色卡」标签，编辑对话框提示「此处修改仅影响本书」。
- 用户在审核页删除某个卡片来源角色时，同步从 `characterCardIds` 移除。

### 6.6 阅读器 `lib/screens/book_reader_screen.dart`

- 单页重绘与「重绘定妆照」逻辑不变，均作用于书内快照。
- 角色面板中卡片来源角色显示「角色卡」小标签。无其他改动。

### 6.7 故事创作助手页 `lib/screens/story_composer_screen.dart`

从创建页进入，入参为当前已选的 0 到 3 张角色卡；返回值为 `StoryDraftResult?`（用户放弃时为空）。纵向布局：

1. **角色条**：已选角色头像与名字，只读。没有角色时显示「未选择角色卡，AI 会自行设计角色」。
2. **描述框**：多行输入，提示「你想讲一个什么样的故事？比如：豆豆和小满在雨天迷路了，最后学会互相帮助」。下方一排灵感芯片：「它从哪里来」「它今天遇到了什么」「它和朋友的一天」「它学会了一件事」「它的一个小秘密」，点击把模板句填入描述框，可继续编辑。
3. **「生成故事」按钮**：描述为空时禁用；生成期间禁用全部按钮并显示进度文字。
4. **故事区**（首次生成后出现）：标题输入框 + 故事多行编辑框，用户可以直接修改任何文字。
5. **反馈框**：多行输入，提示「想改哪里？比如：结局再温暖一点 / 加一段他们吵架又和好」；「按建议重写」按钮，反馈为空时禁用。重写时把编辑框中的**现文本**作为 `currentStory` 传入，保证手动修改不丢。
6. **版本回退**：每次生成或重写成功前，把当前标题与正文压入版本栈；「回到上一版」按钮弹出栈顶恢复，栈空时禁用。版本只保存在本页面生命周期内。
7. **「用这个故事」**：正文非空时可用，返回 `StoryDraftResult(title, story)` 并清除草稿。
8. **草稿自动保存**：描述、标题、正文、角色卡 ID 以单键 `bookbuddy_story_composer_draft` 写入 SharedPreferences，每次内容变化后延迟 1 秒写入。再次进入页面且存在草稿时，顶部显示「恢复上次未完成的故事」条，点击恢复；「用这个故事」或用户点击条上的「丢弃」时清除。

不需要屏幕常亮：单次生成通常在一分钟内完成。

---

## 7. 平台、依赖与图片预处理

| 项目 | 改动 |
|---|---|
| `pubspec.yaml` | 新增 `image_picker`（取图）、`image`（纯 Dart 解码 / 缩放 / JPEG 编码） |
| Android | `image_picker` 通过系统相机与相册意图工作，无需新增权限；角色卡编辑页 `initState` 中在 Android 上调用 `ImagePicker().retrieveLostData()`，恢复因内存回收丢失的拍照结果 |
| iOS `ios/Runner/Info.plist` | 新增 `NSCameraUsageDescription`、`NSPhotoLibraryUsageDescription` |
| macOS `DebugProfile.entitlements` / `Release.entitlements` | 新增 `com.apple.security.files.user-selected.read-only`；不申请摄像头权限，桌面不显示「拍照」按钮 |
| 预处理（`lib/services/photo_preprocessor.dart`） | 解码 → 长边缩放到 1024 → 以质量 85 重编码为 JPEG（`image` 包默认不写 EXIF，位置等元数据随之剥离）→ 返回字节。失败抛 `FormatException('无法读取这张图片')` |

---

## 8. 错误处理与隐私

| 场景 | 处理 |
|---|---|
| 未配置 LLM Key | 与创建页现状一致：橙色 SnackBar 引导去设置 |
| 识图接口报错 / 返回非 JSON | SnackBar 显示原因；表单已填内容全部保留 |
| 激活 LLM 不支持视觉 | 上游错误原文透出，附一句「请切换到支持图片输入的模型」 |
| 生图通道不支持参考图 | 6.3 第 5 条前置对话框；用户选择「仍然生成」后按文字生成 |
| 定妆图生成失败 | SnackBar 原因；保留原有定妆图不覆盖 |
| 对账失败（角色未出场） | SnackBar 显示 `StateError` 原文，停留在创建页 |
| 存储写入失败 | SnackBar；内存状态不变，不清空表单 |
| 写回卡片失败 | 仅提示，不影响绘本继续生成 |
| 故事生成 / 重写失败或结果非 JSON | SnackBar 显示原因；编辑框中的标题与正文保持不变，版本栈不变 |

隐私边界：照片只保存在 `bookbuddy_characters/<cardId>/photo.jpg`；照片离开设备只在两类时刻：用户点「让 AI 认识它」时；以及在支持参考图的生图通道上生成定妆图时（编辑页按画风生成、重新生成，以及绘本审核页为书内外貌未改的卡片角色补画定妆照）。故事页请求永不包含照片。删除卡片即删除照片。

---

## 9. 测试

沿用现有测试写法：模型测试参照 `test/app_settings_test.dart`；存储测试参照 `test/book_storage_service_test.dart` 的临时目录注入；引擎测试参照 `test/character_consistency_test.dart` 用 Dio `InterceptorsWrapper` 捕获请求体并伪造响应。

| 文件 | 覆盖点 |
|---|---|
| `test/character_card_test.dart` | `toJson`/`fromJson` 往返；旧 JSON 缺键回退；`kind` 未知值回退；`toBookCharacter` 的 `isAnimal` 映射与物件后缀；`PictureBook.characterCardIds` 往返与旧数据兼容 |
| `test/character_storage_service_test.dart` | 保存后读取；主文件损坏时从 `.bak` 恢复；删除卡片连带删除目录；`writeImage` 返回相对路径且可读回；`saveAnchor` 更新映射 |
| `test/photo_preprocessor_test.dart` | 大图缩到长边 1024；输出为 JPEG；非法字节抛 `FormatException` |
| `test/book_engine_pinned_test.dart` | 通过 `describeCharacterFromPhoto` 触发三协议调用，断言带图片时请求体结构正确；通过 `createStoryboardDraft` 断言无图片时 OpenAI `content` 仍为字符串；`describeCharacterFromPhoto` 解析与缺键报错；有固定角色时系统提示词包含注入段；对账四条规则各一条用例（覆盖 / 合并同名 / 按名字补漏 / 未出场抛错）；超过 3 张抛 `ArgumentError`；`generateCharacterReference` 附照片时 Gemini 请求含照片标注文字 |
| `test/story_composer_test.dart` | `composeStory` 首次生成的系统提示词包含每张卡片的名字与口头禅；修改模式的用户消息包含当前故事与反馈；请求体 `temperature` 为 0.8；结果缺 `story` 抛 `FormatException`；`title` 缺失时兜底；超过 3 张卡抛 `ArgumentError` |
| `test/widget_test.dart` 补充 | 角色库页空状态渲染；创建页选满 3 张后第 4 张不可选；故事助手页点击灵感芯片后描述框被填入模板句 |

验收命令（改动完成后必须执行）：

```bash
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
$HOME/development/flutter/bin/flutter analyze && $HOME/development/flutter/bin/flutter test
```

---

## 10. 分期与验收标准

**P0 手动角色卡**（无新依赖）
- 第 3 节模型、第 4 节存储、6.1 首页入口、6.2 角色库页、6.3 编辑页（不含照片区与识别按钮）、复用现有 `generateCharacterReference` 生成定妆图（照片参考留到 P3）、前置检查、第 9 节对应测试。
- 验收：手填一张卡，生成水彩定妆图，重启 App 后卡片与定妆图仍在；切换到皮克斯画风可再生成一张并各自缓存。

**P1 融入绘本**（依赖 P0）
- 5.4 引擎、6.4 创建页、6.5 审核页、6.6 阅读器、`PictureBook.characterCardIds`、对应测试。
- 验收：同一张卡分别用于两本自定义故事，两本书的主角外貌一致；第二本若选了新画风，审核页先补画定妆图并写回卡片；编辑卡片外貌后，两本旧书不变。

**P2 故事创作助手**（依赖 P0；与 P1 一起使用价值最大）
- 5.5 引擎、`_callLlm` 的 `temperature` 入参、6.7 助手页、6.4 入口按钮、对应测试。
- 验收：选 2 张卡，输入一句描述，生成 400 到 700 字故事且两个角色的名字与口头禅都出现；手改一句后提交反馈重写，手改内容保留、反馈内容生效；「回到上一版」能恢复；「用这个故事」回填创建页后，走现有分镜流程成书。

**P3 拍照生成**（依赖 P0）
- 第 7 节依赖与权限、预处理、5.1 图片输入、5.2 识图、5.3 照片参考、6.3 照片区与识别按钮、对应测试。
- 验收：Android 拍一张玩具照片，识别出可编辑的角色字段；生成的定妆图在颜色与外形上可辨识为该玩具；卡片目录中的照片为长边不超过 1024 的 JPEG；故事页请求体中不含照片数据（用拦截器断言）。

---

## 11. 明确推后的事项

- **多角色本地拼图**作为同页超过 3 个角色时的兜底：先用真实通道验证效果再决定。
- **连载记忆**：`PictureBook.summary` 与按 `characterCardIds` 反查历史摘要注入提示词。
- **单角色多视角定妆图**（正 / 侧 / 背）以提升单角色一致性。
- **从已有绘本提取角色卡**（`CharacterCardSource.extracted`）。
- 定妆图为每张卡按画风缓存，若画风目录扩大导致磁盘占用明显，再考虑 LRU 清理。

---

## 12. 文档关系

本文是角色卡功能的唯一设计来源。此前的 `docs/toy-character-feasibility.md` 与 `docs/character-card-design.md` 已合并进本文并删除。实施计划将由 writing-plans 流程另行产出到 `docs/superpowers/plans/`。

---

## 13. 实施中确定的规则（P1–P3 执行时补充，优先于上文对应条目）

以下规则来自各阶段的评审与终审，已在代码中实现；与上文冲突时以本节为准。

1. **同名角色卡不能同时使用**（修正 5.4 规则二）：`createStoryboardDraft` 在发请求前检查固定角色的名字，两张卡 trim 后同名时抛 `ArgumentError('选择的角色卡里有两张都叫「X」，请先在角色库里改名，再一起使用。')`；对账规则二合并重复条目时排除其他固定角色的 id。
2. **书内改过外貌的卡片角色不写回卡片**（补充 6.5）：审核页重绘卡片角色的定妆照后，只有当书内快照的物种、外貌、服装仍与 `card.toBookCharacter()` 一致时才写回卡片；改过的定妆照只留在本书。
3. **创建页提示生图通道能力**（补充 6.4）：已选角色卡且当前生图通道不支持参考图时，画风区显示橙色提示「当前生图通道不支持参考图，角色卡的定妆图不会被使用……」，取代「进入审核后会先为 X 绘制定妆照」。
4. **角色库计数两阶段渲染**（补充 6.2）：先显示卡片，再统计「出演 N 本」；同一本书里重复的 id 只算一次。
5. **大模型 JSON 解析失败统一映射**（补充 5.2、5.5）：`_extractJson` 不再抛出 Dart 原始的 `FormatException`，无法解析时返回空结果，由调用方给出约定的中文错误（故事：「故事生成结果格式不正确」；识图：「识图结果格式不正确」；分镜：「大模型未能成功生成绘本分镜，请重试」）。故事与识图提示词要求字符串内换行写成 `\n`、引号用中文引号。
6. **故事助手 temperature 降级**（补充 5.5）：OpenAI 兼容网关以 400 拒绝 `temperature`（响应里提到 temperature）时，去掉该参数重试一次。
7. **故事助手交互细节**（补充 6.7）：生成 / 重写一进入就置忙并防止重复触发；正文为空时「按建议重写」不可用；恢复草稿前把当前故事压入版本栈，生成成功后隐藏恢复条；「用这个故事」同步返回，草稿清理在后台进行。
8. **照片预处理必须先摆正再清空 EXIF**（修正第 7 节）：`image` 包重编码 JPEG 时会保留源图 EXIF，因此预处理先按 EXIF 方向旋转图像，再显式清空 EXIF，最后编码为质量 85 的 JPEG。
9. **识图必填字段**（明确 5.2）：`name`、`kind`、`appearance` 缺失或为空时抛「识图结果格式不正确」；其余字段缺失按空字符串处理；未知的 `kind` 取 `animal`。
10. **审核页重绘前确认是否覆盖卡片定妆图**（2026-09-30 定）：对外貌未在书内改过的卡片角色单独点「重新生成定妆照」，且角色卡已有本画风定妆图（打开审核页时已有，或本页刚写回过）时，先弹「重新生成定妆照」对话框，选项为「取消 / 只用于本书 / 同时更新角色卡」。取消不发请求；「只用于本书」只更新本书的参考图；「同时更新角色卡」照旧写回。卡片还没有本画风定妆图时不弹框，直接补画并写回；批量补画缺失定妆照也不弹框。
11. **Android 找回的照片**（补充第 7 节）：拍照时进程被系统回收后找回的照片，只在新建角色时自动使用；在已保存的角色上先弹「找回了上次拍的照片 / 要把它用在「X」上吗？」确认，取消则丢弃。
12. **换照片后提示定妆图可能过时**（2026-09-30 定）：更换或移除照片仍不自动清空已生成的定妆图（外貌文字未变时视为同一角色）。成功换上新照片（包括确认使用找回的照片）且卡片已有定妆图时，弹「照片已更新」提示已有 N 张定妆图可能和新照片不一样、建议重新生成；本次编辑会话里，这些画风的定妆图预览下方显示橙色提示，重新生成该画风或因外貌修改清空定妆图后提示消失。移除照片不提示。
13. **建书时缺当前画风定妆照先询问**（2026-10-02 定，修正规则 3 的文案与 6.4）：新建绘本按所选画风自动取每张卡的定妆照。画风区提示改为两行：「将直接使用 X 已有的该画风定妆照」和橙色的「Y 还没有该画风的定妆照，生成分镜前会询问是否现在绘制」。点「生成分镜」时，若有卡片缺该画风定妆照、生图通道支持参考图且已配生图密钥，先弹「缺少「画风」画风的定妆照」，列出这些卡片已有的画风，选项为「取消 / 暂不生成 / 现在生成」。取消停在创建页且不发任何请求；「暂不生成」照旧进入审核页，由「先生成角色定妆照」补画；「现在生成」逐张绘制（卡片有照片则作为参考）并写回角色卡，再带着新定妆照生成分镜进入审核。绘制失败停在创建页，已画好的保留在角色卡里。
14. **已有结果时再次生成先确认**（2026-10-02 定）：防止误触重复调用模型。编辑页当前画风已有定妆图时点生成，弹「重新生成定妆图？」；编辑页本次已识别过或外貌已填写时点「让 AI 认识它」，弹「重新识别这张照片？」；审核页与阅读器角色面板里已有定妆照的角色点重绘，弹「重新生成定妆照？」；阅读器里当前页已有朗读语音时点「重新合成本页语音」，弹「重新合成本页语音？」，确认期间若连读翻了页则不再合成。审核页符合规则 10 的卡片角色仍走规则 10 的三选一，不再叠加这个确认。还没有定妆照、表单为空或本页还没有语音时不弹框。
15. **性能约束**（2026-10-02 定）：绘本 JSON 内嵌每页插画的 base64，一本十几 MB。角色库的「出演 N 本」用 `BookStorageService.loadCharacterCardUsage` 在后台 isolate 统计，不在主线程调 `loadBooks`。阅读器每页插画只解码一次并复用字节对象（`Image.memory` 按字节对象同一性判断是否同一张图），相邻页提前构建。
