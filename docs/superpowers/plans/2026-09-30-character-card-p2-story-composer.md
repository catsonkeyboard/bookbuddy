# 角色卡 P2：故事创作助手 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户选好角色卡后，用一句描述让 AI 写出一篇 400 到 700 字的儿童卡通故事；故事可手动修改，也可以提出建议让 AI 在现文本基础上重写；满意后一键回填创建页的标题与正文，之后走现有的分镜与生图流程。

**Architecture:** 引擎新增 `composeStory`（复用 `_callLlm`，新增可选 `temperature`，故事用 0.8、分镜保持 0.3），输出 `StoryDraftResult(title, story)`；首次生成与修改模式共用一个系统提示词，修改模式把编辑框里的现文本与反馈放进用户消息并要求「只改反馈涉及的部分」。新增独立页面 `StoryComposerScreen`：角色条、描述框与灵感芯片、故事编辑区、反馈框、页面内版本栈、单键 SharedPreferences 草稿自动保存与恢复；「用这个故事」通过 `Navigator.pop` 返回结果。创建页在「故事正文」标题行加入口按钮，结果回填标题与正文（正文非空先确认覆盖）。

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4，`dio`、`shared_preferences`（已有依赖），`flutter_test`。本期**不新增任何依赖**。

**Spec:** `docs/superpowers/specs/2026-09-28-character-card-design.md`（第 1 节决策 6、3.3 `StoryDraftResult`、5.1 `temperature` 段、5.5、6.4 入口按钮、6.7、第 8 节故事助手两行、第 9 节 `story_composer_test` 与 widget 补充、第 10 节 P2）。P0、P1 已合并到 `main`（7b8a237 及之前），本计划从 `main` 分支。

## Global Constraints

- Flutter SDK 绝对路径 `$HOME/development/flutter/bin/flutter`；本期无需 `pub get`，不新增依赖。
- 每个任务结束前运行 `$HOME/development/flutter/bin/flutter analyze` 与对应测试文件；analyze 的标准是**按文件核对**：涉及的 `lib/` 与 `test/` 文件不得出现任何新行（`book_engine_service.dart` 原有 5 条 `curly_braces_in_flow_control_structures`、`main.dart` 等文件原有的弃用提示不算）。
- `_callLlm` 新增 `double? temperature`：Gemini 写入 `temperature ?? 0.3`；OpenAI / Anthropic 仅在非空时写入 `temperature` 键。分镜生成不传，故事助手传 `0.8`。**没有传温度时三种协议的请求体必须与改动前完全一致**。
- `composeStory` 上限用 `kMaxCharacterCardsPerBook`；超出或描述为空在发请求前抛 `ArgumentError`；结果缺 `story` 抛 `FormatException('故事生成结果格式不正确')`；`title` 缺失取正文首句前 12 个字。
- 修改模式以调用方传入的 `currentStory`（编辑框现文本）为基础，提示词要求「只修改反馈涉及的部分，其余保持原文不动；若反馈明确要求整体重写则可以重写」。
- 界面文案（简体中文，与现有页面一致）固定：描述框提示「你想讲一个什么样的故事？比如：豆豆和小满在雨天迷路了，最后学会互相帮助」；灵感芯片「它从哪里来」「它今天遇到了什么」「它和朋友的一天」「它学会了一件事」「它的一个小秘密」；按钮「生成故事」「按建议重写」「回到上一版」「用这个故事」；无角色提示「未选择角色卡，AI 会自行设计角色」；反馈框提示「想改哪里？比如：结局再温暖一点 / 加一段他们吵架又和好」；草稿条「恢复上次未完成的故事」与「恢复」「丢弃」；创建页入口「✨ 让 AI 按角色写故事」；覆盖确认「用生成的故事替换当前正文？」。
- 草稿键 `bookbuddy_story_composer_draft`，内容 JSON `{brief, title, story, cardIds}`，内容变化后延迟 1 秒写入；「用这个故事」或「丢弃」时清除；`dispose` 必须取消未触发的定时器。
- 版本栈只在页面生命周期内保存；每次生成或重写**成功前**压入当前标题与正文；「回到上一版」栈空时禁用。
- 故事生成失败时编辑框内容与版本栈保持不变。
- widget 测试里由控件回调触发的 Dio / 文件 Future 用 `runIo(tester, body, until:)`（交替 `runAsync` / `pump`，见 `test/character_library_screen_test.dart:21-36`）；SharedPreferences 用 `setMockInitialValues`。
- 提交信息遵循 Conventional Commits，末尾附 `Co-Authored-By: Claude <模型名> <noreply@anthropic.com>`（任意 Claude 型号均可）。
- 手动验收（spec §10 P2）留给用户。

---

## 文件结构

| 文件 | 改动 |
|---|---|
| `lib/services/book_engine_service.dart` | `StoryDraftResult`；`_callLlm(temperature:)`；`composeStory`；`_storyCastBlock` |
| `lib/screens/story_composer_screen.dart`（新建） | 故事助手页：角色条、描述与芯片、生成、故事编辑、反馈重写、版本栈、草稿自动保存与恢复、「用这个故事」 |
| `lib/screens/create_book_screen.dart` | 「✨ 让 AI 按角色写故事」入口与回填 |
| `README.md`、`AGENTS.md` | 功能说明与目录树各加一行 |
| `test/story_composer_test.dart`（新建） | 引擎：提示词、温度、修改模式、解析、上限 |
| `test/story_composer_screen_test.dart`（新建） | 助手页 widget 测试（含草稿） |
| `test/create_book_screen_test.dart` | 入口与回填 |

---

### Task 0: 建立功能分支

**Files:** 无

- [ ] **Step 1: 确认在 main 且工作区（除已知的 ios/macos 未跟踪改动外）干净，建分支**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git checkout main && git status --short | grep -v "ios/\|macos/" ; git checkout -b feat/character-cards-p2
```

Expected: 过滤后无输出；切换到 `feat/character-cards-p2`。

- [ ] **Step 2: 提交本计划**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add docs/superpowers/plans/2026-09-30-character-card-p2-story-composer.md && git commit -m "docs: add character card P2 story composer implementation plan

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 1: 引擎：`temperature` 与 `composeStory`

**Files:**
- Modify: `lib/services/book_engine_service.dart`（`:10-15` 类型区；`:651-743` `_callLlm`；在 `createStoryboardDraft` 之前新增方法）
- Test: `test/story_composer_test.dart`（新建）

**Interfaces:**
- Consumes: `_callLlm`、`_extractJson`（`:1285`）、`CharacterCard.toBookCharacter()`、`kMaxCharacterCardsPerBook`
- Produces:
  - `class StoryDraftResult { final String title; final String story; const StoryDraftResult({required this.title, required this.story}); }`
  - `Future<String> _callLlm({required settings, required systemPrompt, required userPrompt, double? temperature})`
  - `Future<StoryDraftResult> composeStory({required AppSettings settings, required List<CharacterCard> cards, required String brief, String? currentStory, String? feedback})`

- [ ] **Step 1: 写失败的测试**

创建 `test/story_composer_test.dart`：

```dart
import 'dart:convert';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 伪造 OpenAI 兼容协议响应（content 为给定字符串），并记录请求体。
Dio fakeOpenAiDio(String content, List<dynamic> sent) => Dio()
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
                  'message': {'content': content},
                },
              ],
            },
          ),
        );
      },
    ),
  );

/// 伪造 Gemini generateContent 文本响应，并记录请求体。
Dio fakeGeminiDio(String content, List<dynamic> sent) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        sent.add(options.data);
        handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': content},
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

AppSettings openAiSettings() => AppSettings(
      llmType: 'openai',
      llmBaseUrl: 'https://example.test',
      llmApiKey: 'test',
      llmModel: 'test',
    );

AppSettings geminiSettings() => AppSettings(
      llmType: 'gemini',
      llmBaseUrl: 'https://example.test',
      llmApiKey: 'test',
      llmModel: 'gemini-test',
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

final storyJson = jsonEncode({
  'title': '豆豆的雨天',
  'story': '豆豆出门了。\n\n雨下大了，豆豆迷路了。\n\n它大喊：冲啊！',
});

void main() {
  test('首次生成：系统提示词含角色设定，用户消息含描述，温度 0.8', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeOpenAiDio(storyJson, sent));
    final result = await engine.composeStory(
      settings: openAiSettings(),
      cards: [dino()],
      brief: '豆豆在雨天迷路了，最后学会向别人求助。',
    );
    expect(result.title, '豆豆的雨天');
    expect(result.story, contains('冲啊！'));

    final body = sent.single as Map;
    expect(body['temperature'], 0.8);
    final system = body['messages'][0]['content'] as String;
    final user = body['messages'][1]['content'] as String;
    expect(system, contains('3 到 8 岁'));
    expect(system, contains('豆豆'));
    expect(system, contains('冲啊！'));
    expect(system, contains('胆子大、爱冒险'));
    expect(system, contains('红色小围巾'));
    expect(system, contains('400 到 700 字'));
    expect(user, contains('豆豆在雨天迷路了，最后学会向别人求助。'));
    expect(user, isNot(contains('当前故事')));
  });

  test('修改模式：用户消息附上当前故事与反馈，并要求只改涉及部分', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeOpenAiDio(storyJson, sent));
    await engine.composeStory(
      settings: openAiSettings(),
      cards: [dino()],
      brief: '豆豆在雨天迷路了。',
      currentStory: '豆豆出门了。它走丢了。（我手改过的一句）',
      feedback: '结局再温暖一点',
    );
    final user = (sent.single as Map)['messages'][1]['content'] as String;
    expect(user, contains('（我手改过的一句）'));
    expect(user, contains('结局再温暖一点'));
    expect(user, contains('只修改反馈涉及的部分，其余保持原文不动'));
    expect(user, contains('若反馈明确要求整体重写则可以重写'));
  });

  test('没有角色卡时提示大模型自行设计角色', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeOpenAiDio(storyJson, sent));
    await engine.composeStory(
      settings: openAiSettings(),
      cards: const [],
      brief: '一只想飞的小猪。',
    );
    final system = (sent.single as Map)['messages'][0]['content'] as String;
    expect(system, contains('自行设计'));
    expect(system, isNot(contains('必须原样使用')));
  });

  test('结果缺少 story 时抛 FormatException', () async {
    final engine = BookEngineService(
      dio: fakeOpenAiDio(jsonEncode({'title': '只有标题'}), []),
    );
    await expectLater(
      engine.composeStory(
        settings: openAiSettings(),
        cards: [dino()],
        brief: '随便讲一个。',
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          '故事生成结果格式不正确',
        ),
      ),
    );
  });

  test('title 缺失时取正文首句前 12 个字', () async {
    final engine = BookEngineService(
      dio: fakeOpenAiDio(
        jsonEncode({'story': '豆豆在雨天迷路了，它很害怕。后来它遇到了小猫。'}),
        [],
      ),
    );
    final result = await engine.composeStory(
      settings: openAiSettings(),
      cards: [dino()],
      brief: '随便讲一个。',
    );
    expect(result.title, '豆豆在雨天迷路了，它很害');
  });

  test('超过上限或描述为空在请求前被拒绝', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeOpenAiDio(storyJson, sent));
    final tooMany = List.generate(
      kMaxCharacterCardsPerBook + 1,
      (i) => CharacterCard(id: 'card_$i', name: '角色$i', appearance: 'x'),
    );
    await expectLater(
      engine.composeStory(
        settings: openAiSettings(),
        cards: tooMany,
        brief: '随便讲一个。',
      ),
      throwsArgumentError,
    );
    await expectLater(
      engine.composeStory(
        settings: openAiSettings(),
        cards: [dino()],
        brief: '   ',
      ),
      throwsArgumentError,
    );
    expect(sent, isEmpty);
  });

  test('Gemini 分支：故事用 0.8，分镜保持 0.3；OpenAI 分镜不带 temperature', () async {
    final geminiSent = <dynamic>[];
    final geminiEngine = BookEngineService(
      dio: fakeGeminiDio(storyJson, geminiSent),
    );
    await geminiEngine.composeStory(
      settings: geminiSettings(),
      cards: [dino()],
      brief: '随便讲一个。',
    );
    expect(
      (geminiSent.single as Map)['generationConfig']['temperature'],
      0.8,
    );

    final storyboard = jsonEncode({
      'characters': [],
      'groups': {},
      'scenes': [
        {
          'text': '从前有座山。',
          'action': '',
          'emotion': '',
          'composition': '',
          'characterIds': [],
          'outfitOverrides': {},
        },
      ],
    });
    final geminiBoard = <dynamic>[];
    await BookEngineService(dio: fakeGeminiDio(storyboard, geminiBoard))
        .createStoryboardDraft(
      settings: geminiSettings(),
      title: '山',
      storyText: '从前有座山。',
    );
    expect(
      (geminiBoard.single as Map)['generationConfig']['temperature'],
      0.3,
    );

    final openAiBoard = <dynamic>[];
    await BookEngineService(dio: fakeOpenAiDio(storyboard, openAiBoard))
        .createStoryboardDraft(
      settings: openAiSettings(),
      title: '山',
      storyText: '从前有座山。',
    );
    expect((openAiBoard.single as Map).containsKey('temperature'), isFalse);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/story_composer_test.dart`

Expected: 编译失败，`composeStory` / `StoryDraftResult` 不存在。

- [ ] **Step 3: 实现引擎改动**

`lib/services/book_engine_service.dart`：

（a）在 `class StoryboardDraft { ... }` 之后加：

```dart
/// 故事助手的输出：标题 + 正文。
class StoryDraftResult {
  final String title;
  final String story;

  const StoryDraftResult({required this.title, required this.story});
}
```

（b）`_callLlm` 签名加可选温度，三个协议分支按规则写入：

```dart
  Future<String> _callLlm({
    required AppSettings settings,
    required String systemPrompt,
    required String userPrompt,
    double? temperature,
  }) async {
```

Gemini 分支把 `'generationConfig': {'temperature': 0.3},` 改为 `'generationConfig': {'temperature': temperature ?? 0.3},`。

Anthropic 分支的 `data: {` 里，在 `'max_tokens': 4096,` 之后加一行 `if (temperature != null) 'temperature': temperature,`。

OpenAI 分支的 `data: {` 里，在 `'model': settings.llmModel,` 之后加一行 `if (temperature != null) 'temperature': temperature,`。

（c）在 `createStoryboardDraft` 方法**之前**（即 `createStoryboards` 之后）加：

```dart
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
只输出合法 JSON：{"title": "故事标题（不超过 12 个字）", "story": "正文，段落之间用换行分隔"}
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

    final raw = await _callLlm(
      settings: settings,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      temperature: 0.8,
    );
    final parsed = _extractJson(raw);
    final story = parsed is Map ? (parsed['story']?.toString().trim() ?? '') : '';
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
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/story_composer_test.dart test/book_engine_pinned_test.dart test/character_consistency_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "book_engine|story_composer_test" | grep -v curly_braces || echo "analyze: no new lines for touched files"`

Expected: 7 + 9 + 9 tests passed；grep 只剩 `echo` 的提示（原有 5 条 `curly_braces` 已被过滤）。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/services/book_engine_service.dart test/story_composer_test.dart && git commit -m "feat(story): add composeStory with per-call temperature for the story assistant

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: 故事助手页：生成、反馈重写、版本回退、灵感芯片

**Files:**
- Create: `lib/screens/story_composer_screen.dart`
- Test: `test/story_composer_screen_test.dart`（新建）

**Interfaces:**
- Consumes: `BookEngineService.composeStory`、`StoryDraftResult`（Task 1）、`CharacterCard`、`SettingsService().loadSettings`
- Produces:
  - `class StoryComposerScreen extends StatefulWidget { const StoryComposerScreen({super.key, this.cards = const [], this.engine, this.loadSettings}); }` — `cards: List<CharacterCard>`，`engine: BookEngineService?`，`loadSettings: Future<AppSettings> Function()?`
  - 「用这个故事」通过 `Navigator.pop(context, StoryDraftResult(...))` 返回；用户直接返回时结果为 `null`
  - 本任务**不含**草稿自动保存（Task 3 加）；但已预留 `_onAnyFieldChanged()` 钩子（本任务为空实现）

- [ ] **Step 1: 写失败的测试**

创建 `test/story_composer_screen_test.dart`：

```dart
import 'dart:convert';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/story_composer_screen.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在真实事件循环里执行会产生网络 / 文件 Future 的操作，然后交替「让出真实时间片」与
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

/// 每次请求按顺序返回 [contents] 里的下一个字符串（超出则重复最后一个），并记录请求体。
Dio sequencedOpenAiDio(List<String> contents, List<dynamic> sent) {
  var calls = 0;
  return Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          sent.add(options.data);
          final content = contents[calls < contents.length ? calls : contents.length - 1];
          calls++;
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'choices': [
                  {
                    'message': {'content': content},
                  },
                ],
              },
            ),
          );
        },
      ),
    );
}

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
      appearance: '绿色毛绒恐龙',
      catchphrase: '冲啊！',
    );

String storyJson(String title, String story) =>
    jsonEncode({'title': title, 'story': story});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 从占位页 push 进入助手页，并把返回值记录到 [popped]。
  Future<void> pumpComposer(
    WidgetTester tester, {
    List<CharacterCard> cards = const [],
    BookEngineService? engine,
    required List<StoryDraftResult?> popped,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  final result = await Navigator.push<StoryDraftResult>(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => StoryComposerScreen(
                        cards: cards,
                        engine: engine,
                        loadSettings: () async => openAiSettings(),
                      ),
                    ),
                  );
                  popped.add(result);
                },
                child: const Text('打开助手'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开助手'));
    await tester.pumpAndSettle();
  }

  Finder briefField() => find.widgetWithText(
        TextField,
        '你想讲一个什么样的故事？比如：豆豆和小满在雨天迷路了，最后学会互相帮助',
      );

  testWidgets('没有角色卡时提示 AI 会自行设计角色', (tester) async {
    await pumpComposer(tester, popped: []);
    expect(find.text('未选择角色卡，AI 会自行设计角色'), findsOneWidget);
    expect(find.text('用这个故事'), findsNothing);
  });

  testWidgets('点击灵感芯片把带角色名的模板句填入描述框', (tester) async {
    await pumpComposer(tester, cards: [dino()], popped: []);
    expect(find.text('豆豆'), findsWidgets);
    await tester.tap(find.text('它从哪里来'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(briefField());
    expect(field.controller!.text, contains('豆豆'));
    expect(field.controller!.text, contains('从哪里来'));
  });

  testWidgets('生成故事后可编辑并用这个故事返回结果', (tester) async {
    final popped = <StoryDraftResult?>[];
    final engine = BookEngineService(
      dio: sequencedOpenAiDio([storyJson('豆豆的雨天', '豆豆出门了。\n\n它迷路了。')], []),
    );
    await pumpComposer(tester, cards: [dino()], engine: engine, popped: popped);

    await tester.enterText(briefField(), '豆豆在雨天迷路了。');
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('生成故事')),
      until: () => find.text('用这个故事').evaluate().isNotEmpty,
    );
    expect(find.text('豆豆的雨天'), findsOneWidget);
    expect(find.textContaining('豆豆出门了。'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '故事标题'),
      '豆豆的雨天（手改）',
    );
    await tester.pump();
    await tester.tap(find.text('用这个故事'));
    await tester.pumpAndSettle();

    expect(popped.single!.title, '豆豆的雨天（手改）');
    expect(popped.single!.story, '豆豆出门了。\n\n它迷路了。');
    expect(find.byType(StoryComposerScreen), findsNothing);
  });

  testWidgets('按建议重写以现文本为基础，回到上一版可恢复', (tester) async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: sequencedOpenAiDio([
        storyJson('第一版', '第一版正文。'),
        storyJson('第二版', '第二版正文，结局更温暖。'),
      ], sent),
    );
    await pumpComposer(tester, cards: [dino()], engine: engine, popped: []);
    await tester.enterText(briefField(), '豆豆在雨天迷路了。');
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('生成故事')),
      until: () => find.text('用这个故事').evaluate().isNotEmpty,
    );
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '回到上一版')).onPressed, isNull);

    // 手改正文后再提反馈：重写请求必须带上手改后的文本。
    await tester.enterText(
      find.widgetWithText(TextField, '故事正文'),
      '第一版正文。（我手改了这里）',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '想改哪里？比如：结局再温暖一点 / 加一段他们吵架又和好'),
      '结局再温暖一点',
    );
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('按建议重写')),
      until: () => find.textContaining('第二版正文').evaluate().isNotEmpty,
    );
    final rewriteUser = (sent.last as Map)['messages'][1]['content'] as String;
    expect(rewriteUser, contains('（我手改了这里）'));
    expect(rewriteUser, contains('结局再温暖一点'));
    expect(find.text('第二版'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, '想改哪里？比如：结局再温暖一点 / 加一段他们吵架又和好')).controller!.text,
      isEmpty,
    );

    await tester.tap(find.text('回到上一版'));
    await tester.pumpAndSettle();
    expect(find.text('第一版'), findsOneWidget);
    expect(find.textContaining('（我手改了这里）'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '回到上一版')).onPressed, isNull);
  });

  testWidgets('生成失败时提示原因，描述保留，故事区不出现', (tester) async {
    final engine = BookEngineService(
      dio: sequencedOpenAiDio(['这不是 JSON'], []),
    );
    await pumpComposer(tester, cards: [dino()], engine: engine, popped: []);
    await tester.enterText(briefField(), '豆豆在雨天迷路了。');
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('生成故事')),
      until: () => find.text('故事生成结果格式不正确').evaluate().isNotEmpty,
    );
    expect(find.text('故事生成结果格式不正确'), findsOneWidget);
    expect(tester.widget<TextField>(briefField()).controller!.text, '豆豆在雨天迷路了。');
    expect(find.text('用这个故事'), findsNothing);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/story_composer_screen_test.dart`

Expected: 编译失败，`story_composer_screen.dart` 不存在。

- [ ] **Step 3: 实现助手页**

创建 `lib/screens/story_composer_screen.dart`：

```dart
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/character_card.dart';
import '../services/book_engine_service.dart';
import '../services/settings_service.dart';

/// 故事创作助手：角色卡 + 一句描述 → AI 写故事；可手改，可用反馈让 AI 在现文本上重写。
/// 「用这个故事」通过 Navigator.pop 返回 [StoryDraftResult]。
class StoryComposerScreen extends StatefulWidget {
  final List<CharacterCard> cards;
  final BookEngineService? engine;
  final Future<AppSettings> Function()? loadSettings;

  const StoryComposerScreen({
    super.key,
    this.cards = const [],
    this.engine,
    this.loadSettings,
  });

  @override
  State<StoryComposerScreen> createState() => _StoryComposerScreenState();
}

class _StoryVersion {
  final String title;
  final String story;
  const _StoryVersion(this.title, this.story);
}

class _StoryComposerScreenState extends State<StoryComposerScreen> {
  static const _templates = <String, String>{
    '它从哪里来': '讲一讲{名}是从哪里来的，第一次来到这个家时发生了什么。',
    '它今天遇到了什么': '{名}今天出门遇到了一件意想不到的小事，最后开开心心地回家。',
    '它和朋友的一天': '{名}和好朋友一起度过的一天，中间闹了个小别扭又和好了。',
    '它学会了一件事': '{名}第一次尝试一件不太敢做的事，最后学会了它。',
    '它的一个小秘密': '{名}有一个藏了很久的小秘密，今天终于告诉了最好的朋友。',
  };

  late final BookEngineService _engine;
  late final Future<AppSettings> Function() _loadSettings;

  final _briefCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _storyCtrl = TextEditingController();
  final _feedbackCtrl = TextEditingController();

  bool _hasStory = false;
  bool _busy = false;
  String _busyText = '';
  final List<_StoryVersion> _history = [];

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? BookEngineService();
    _loadSettings = widget.loadSettings ?? SettingsService().loadSettings;
    for (final c in [_briefCtrl, _titleCtrl, _storyCtrl, _feedbackCtrl]) {
      c.addListener(_onAnyFieldChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [_briefCtrl, _titleCtrl, _storyCtrl, _feedbackCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 任一输入变化时触发；按钮可用状态依赖输入内容，草稿保存在下一任务接入。
  void _onAnyFieldChanged() {
    if (mounted) setState(() {});
  }

  String get _protagonistName =>
      widget.cards.isEmpty ? '它' : widget.cards.first.name;

  void _applyTemplate(String template) {
    _briefCtrl.text = template.replaceAll('{名}', _protagonistName);
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

  /// 生成或重写：成功前压入当前版本；失败时编辑框与版本栈都不变。
  Future<void> _run({required bool revise}) async {
    final AppSettings settings;
    try {
      settings = await _loadSettings();
    } catch (e) {
      _toast('读取设置失败: $e', error: true);
      return;
    }
    if (settings.llmApiKey.isEmpty) {
      _toast('⚠️ 请先在设置里填写 LLM API Key', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _busyText = revise ? '正在按你的建议重写故事...' : '正在为你写故事...';
    });
    try {
      final result = await _engine.composeStory(
        settings: settings,
        cards: widget.cards,
        brief: _briefCtrl.text,
        currentStory: revise ? _storyCtrl.text : null,
        feedback: revise ? _feedbackCtrl.text : null,
      );
      if (!mounted) return;
      if (_hasStory) {
        _history.add(_StoryVersion(_titleCtrl.text, _storyCtrl.text));
      }
      // 控制器赋值会触发监听器里的 setState，所以放在 setState 之外，避免嵌套。
      _titleCtrl.text = result.title;
      _storyCtrl.text = result.story;
      if (revise) _feedbackCtrl.clear();
      setState(() => _hasStory = true);
    } on FormatException catch (e) {
      _toast(e.message, error: true);
    } on ArgumentError catch (e) {
      _toast('${e.message}', error: true);
    } catch (e) {
      _toast('故事生成失败: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _undo() {
    if (_history.isEmpty) return;
    final previous = _history.removeLast();
    _titleCtrl.text = previous.title;
    _storyCtrl.text = previous.story;
    setState(() {});
  }

  void _useStory() {
    Navigator.pop(
      context,
      StoryDraftResult(
        title: _titleCtrl.text.trim(),
        story: _storyCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGenerate = !_busy && _briefCtrl.text.trim().isNotEmpty;
    final canRewrite = !_busy && _feedbackCtrl.text.trim().isNotEmpty;
    final canUse = !_busy && _storyCtrl.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('✨ 让 AI 按角色写故事')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(_busyText, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 16),
              ],
              _buildCastBar(),
              const SizedBox(height: 16),
              TextField(
                controller: _briefCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '你想讲一个什么样的故事？比如：豆豆和小满在雨天迷路了，最后学会互相帮助',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in _templates.entries)
                    ActionChip(
                      label: Text(entry.key),
                      onPressed: _busy ? null : () => _applyTemplate(entry.value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canGenerate ? () => _run(revise: false) : null,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('生成故事'),
              ),
              if (_hasStory) ...[
                const SizedBox(height: 24),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '故事标题',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _storyCtrl,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: '故事正文',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _feedbackCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '想改哪里？比如：结局再温暖一点 / 加一段他们吵架又和好',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: canRewrite ? () => _run(revise: true) : null,
                      icon: const Icon(Icons.edit_note),
                      label: const Text('按建议重写'),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: (_busy || _history.isEmpty) ? null : _undo,
                      icon: const Icon(Icons.undo),
                      label: const Text('回到上一版'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: canUse ? _useStory : null,
                  icon: const Icon(Icons.check),
                  label: const Text('用这个故事'),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCastBar() {
    if (widget.cards.isEmpty) {
      return const Text(
        '未选择角色卡，AI 会自行设计角色',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final card in widget.cards)
          Chip(
            avatar: const Icon(Icons.face_retouching_natural, size: 16),
            label: Text(card.name),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/story_composer_screen_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "story_composer" || echo "analyze: no lines for touched files"`

Expected: 5 tests passed（连续跑 3 次）；grep 无输出。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/screens/story_composer_screen.dart test/story_composer_screen_test.dart && git commit -m "feat(story): add story composer screen with feedback rewrite and version undo

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: 助手页：草稿自动保存与恢复

**Files:**
- Modify: `lib/screens/story_composer_screen.dart`
- Test: `test/story_composer_screen_test.dart`（追加）

**Interfaces:**
- Consumes: `SharedPreferences`（已有依赖）
- Produces: 草稿键 `bookbuddy_story_composer_draft`；`_onAnyFieldChanged` 触发 1 秒防抖保存；进入页面时若存在草稿显示「恢复上次未完成的故事」条；「用这个故事」与「丢弃」清除草稿。

- [ ] **Step 1: 追加失败的测试**

在 `test/story_composer_screen_test.dart` 顶部 import 区加 `import 'dart:async';`（本步骤不需要，可省略）——不需要新 import。把 `main()` 收尾的 `}` 替换为：

```dart
  testWidgets('输入 1 秒后自动保存草稿，再次进入可恢复或丢弃', (tester) async {
    await pumpComposer(tester, cards: [dino()], popped: []);
    await tester.enterText(briefField(), '豆豆在雨天迷路了。');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('bookbuddy_story_composer_draft')!)
        as Map<String, dynamic>;
    expect(saved['brief'], '豆豆在雨天迷路了。');
    expect(saved['cardIds'], ['card_dino1']);

    // 再次进入：出现恢复条，恢复后描述回填。
    await pumpComposer(tester, cards: [dino()], popped: []);
    expect(find.text('恢复上次未完成的故事'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(briefField()).controller!.text, '豆豆在雨天迷路了。');
    expect(find.text('恢复上次未完成的故事'), findsNothing);

    // 第三次进入：丢弃后草稿被清除。
    await pumpComposer(tester, cards: [dino()], popped: []);
    await tester.tap(find.text('丢弃'));
    await tester.pumpAndSettle();
    expect(find.text('恢复上次未完成的故事'), findsNothing);
    expect(prefs.getString('bookbuddy_story_composer_draft'), isNull);
  });

  testWidgets('用这个故事时清除草稿，并恢复带正文的草稿时显示故事区', (tester) async {
    SharedPreferences.setMockInitialValues({
      'bookbuddy_story_composer_draft': jsonEncode({
        'brief': '豆豆在雨天迷路了。',
        'title': '草稿标题',
        'story': '草稿正文。',
        'cardIds': ['card_dino1'],
      }),
    });
    final popped = <StoryDraftResult?>[];
    await pumpComposer(tester, cards: [dino()], popped: popped);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.text('草稿标题'), findsOneWidget);
    expect(find.text('用这个故事'), findsOneWidget);

    await tester.tap(find.text('用这个故事'));
    await tester.pumpAndSettle();
    expect(popped.single!.story, '草稿正文。');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bookbuddy_story_composer_draft'), isNull);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/story_composer_screen_test.dart --name "草稿"`

Expected: 2 failed（没有草稿被保存 / 没有恢复条）。

- [ ] **Step 3: 实现草稿保存与恢复**

`lib/screens/story_composer_screen.dart`：

（a）import 区加：

```dart
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
```

（保持顺序：dart 库 → package → 相对路径。）

（b）State 字段加：

```dart
  static const _draftKey = 'bookbuddy_story_composer_draft';
  Timer? _saveTimer;
  Map<String, dynamic>? _pendingDraft; // 进入页面时发现的上次草稿，等待用户恢复或丢弃
```

（c）`initState` 末尾加 `_loadDraft();`；`dispose` 开头加 `_saveTimer?.cancel();`。

（d）把 `_onAnyFieldChanged` 替换为：

```dart
  /// 任一输入变化时触发：刷新按钮可用状态，并在 1 秒后自动保存草稿。
  void _onAnyFieldChanged() {
    if (!mounted) return;
    setState(() {});
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _saveDraft);
  }

  Future<void> _saveDraft() async {
    final brief = _briefCtrl.text;
    final title = _titleCtrl.text;
    final story = _storyCtrl.text;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (brief.trim().isEmpty && story.trim().isEmpty) {
        await prefs.remove(_draftKey);
        return;
      }
      await prefs.setString(
        _draftKey,
        jsonEncode({
          'brief': brief,
          'title': title,
          'story': story,
          'cardIds': widget.cards.map((c) => c.id).toList(),
        }),
      );
    } catch (_) {
      // 草稿只是保险，写不进去不影响创作。
    }
  }

  Future<void> _clearDraft() async {
    _saveTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null) return;
      final draft = jsonDecode(raw);
      if (draft is! Map) return;
      final map = Map<String, dynamic>.from(draft);
      final brief = map['brief']?.toString() ?? '';
      final story = map['story']?.toString() ?? '';
      if (brief.trim().isEmpty && story.trim().isEmpty) return;
      if (!mounted) return;
      setState(() => _pendingDraft = map);
    } catch (_) {}
  }

  void _restoreDraft() {
    final draft = _pendingDraft;
    if (draft == null) return;
    _briefCtrl.text = draft['brief']?.toString() ?? '';
    _titleCtrl.text = draft['title']?.toString() ?? '';
    _storyCtrl.text = draft['story']?.toString() ?? '';
    setState(() {
      _hasStory = _storyCtrl.text.trim().isNotEmpty;
      _pendingDraft = null;
    });
  }

  Future<void> _discardDraft() async {
    setState(() => _pendingDraft = null);
    await _clearDraft();
  }
```

（e）`_useStory` 改为：

```dart
  Future<void> _useStory() async {
    final result = StoryDraftResult(
      title: _titleCtrl.text.trim(),
      story: _storyCtrl.text.trim(),
    );
    await _clearDraft();
    if (!mounted) return;
    Navigator.pop(context, result);
  }
```

（f）`build` 的 `ListView` `children` 最前面（`if (_busy)` 之前）加恢复条：

```dart
              if (_pendingDraft != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8A24A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFD8A24A).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history, size: 18, color: Color(0xFFD8A24A)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '恢复上次未完成的故事',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(onPressed: _discardDraft, child: const Text('丢弃')),
                      FilledButton(onPressed: _restoreDraft, child: const Text('恢复')),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/story_composer_screen_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "story_composer" || echo "analyze: no lines for touched files"`

Expected: 7 tests passed（连续跑 3 次，且没有「A Timer is still pending」类噪音）；grep 无输出。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/screens/story_composer_screen.dart test/story_composer_screen_test.dart && git commit -m "feat(story): autosave and restore the composer draft

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: 创建页入口与回填、文档、全量验证

**Files:**
- Modify: `lib/screens/create_book_screen.dart`（import 区；`_StartGenerate` 之前新增 `_openStoryComposer`；「📖 故事正文：」标题行）
- Modify: `README.md`、`AGENTS.md`
- Test: `test/create_book_screen_test.dart`（追加）

**Interfaces:**
- Consumes: `StoryComposerScreen({cards, engine, loadSettings})`（Task 2/3）、`StoryDraftResult`（Task 1）、创建页现有的 `_selectedCards`、`_engine`、`_loadSettings`、`_titleCtrl`、`_textCtrl`
- Produces: 入口按钮「✨ 让 AI 按角色写故事」；回填逻辑（正文非空先弹「用生成的故事替换当前正文？」）

- [ ] **Step 1: 追加失败的测试**

`test/create_book_screen_test.dart`：import 区加 `import 'package:bookbuddy/screens/story_composer_screen.dart';`。在 `main()` 收尾 `}` 之前追加：

```dart
  testWidgets('入口按钮带着已选角色卡打开故事助手，用这个故事后回填标题与正文', (tester) async {
    await tester.runAsync(() => storage.saveCard(card('card_a', '豆豆')));
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: fakeLlmDio({'title': '豆豆的雨天', 'story': '豆豆出门了。\n\n它迷路了。'}, sent),
    );
    await pumpCreate(
      tester,
      engine: engine,
      settings: AppSettings(
        llmType: 'openai',
        llmBaseUrl: 'https://example.test',
        llmApiKey: 'k',
        llmModel: 'm',
        imageType: 'gemini',
        imageApiKey: 'test-key',
        imageModel: 'gemini-2.5-flash-image',
      ),
    );
    await tester.tap(find.widgetWithText(FilterChip, '豆豆'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('让 AI 按角色写故事'));
    await tester.pumpAndSettle();
    final composer = tester.widget<StoryComposerScreen>(find.byType(StoryComposerScreen));
    expect(composer.cards.single.id, 'card_a');

    await tester.enterText(
      find.widgetWithText(
        TextField,
        '你想讲一个什么样的故事？比如：豆豆和小满在雨天迷路了，最后学会互相帮助',
      ),
      '豆豆在雨天迷路了。',
    );
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('生成故事')),
      until: () => find.text('用这个故事').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('用这个故事'));
    await tester.pumpAndSettle();

    expect(find.byType(StoryComposerScreen), findsNothing);
    final title = tester.widget<TextField>(
      find.widgetWithText(TextField, '故事标题（如：小红帽的故事、三只小猪）'),
    );
    expect(title.controller!.text, '豆豆的雨天');
    expect(find.textContaining('豆豆出门了。'), findsOneWidget);
    expect(sent, hasLength(1));
  });

  testWidgets('正文已有内容时回填前先确认覆盖', (tester) async {
    final engine = BookEngineService(
      dio: fakeLlmDio({'title': '新标题', 'story': '新正文。'}, []),
    );
    await pumpCreate(
      tester,
      engine: engine,
      settings: AppSettings(
        llmType: 'openai',
        llmBaseUrl: 'https://example.test',
        llmApiKey: 'k',
        llmModel: 'm',
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, '可直接粘贴故事全文；若留空仅填书名，AI 将自动构思并续写完整童话...'),
      '我自己写的正文',
    );
    await tester.pump();

    await tester.tap(find.text('让 AI 按角色写故事'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
        TextField,
        '你想讲一个什么样的故事？比如：豆豆和小满在雨天迷路了，最后学会互相帮助',
      ),
      '随便讲一个。',
    );
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('生成故事')),
      until: () => find.text('用这个故事').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('用这个故事'));
    await tester.pumpAndSettle();

    expect(find.text('用生成的故事替换当前正文？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.textContaining('我自己写的正文'), findsOneWidget);
    expect(find.textContaining('新正文'), findsNothing);
  });
```

说明：`fakeLlmDio` 已在该文件中（P1 加入），它把传入的 Map 编码成 `choices[0].message.content`，故事助手用同一伪造即可。`runIo` 也已在文件里。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/create_book_screen_test.dart --name "故事助手|确认覆盖"`

Expected: 2 failed（找不到「让 AI 按角色写故事」按钮）。

- [ ] **Step 3: 实现入口与回填**

`lib/screens/create_book_screen.dart`：

（a）import 区在 `import 'storyboard_review_screen.dart';` 之前加 `import 'story_composer_screen.dart';`（保持字母序：`character_library_screen.dart` → `story_composer_screen.dart` → `storyboard_review_screen.dart`）。

（b）在 `_startGenerate()` 之前加：

```dart
  /// 打开故事助手；返回结果后回填标题与正文，正文已有内容时先确认覆盖。
  Future<void> _openStoryComposer() async {
    final result = await Navigator.push<StoryDraftResult>(
      context,
      MaterialPageRoute(
        builder: (_) => StoryComposerScreen(
          cards: _selectedCards,
          engine: _engine,
          loadSettings: _loadSettings,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (_textCtrl.text.trim().isNotEmpty) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('用生成的故事替换当前正文？'),
          content: const Text('当前故事正文会被覆盖，标题也会更新。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('替换'),
            ),
          ],
        ),
      );
      if (overwrite != true || !mounted) return;
    }
    setState(() {
      _titleCtrl.text = result.title;
      _textCtrl.text = result.story;
    });
  }
```

（c）「📖 故事正文：」标题行的内层 `Row(children: [ ... ])`（包含「从剪贴板粘贴」「清空」两个按钮）改为 `Flexible(child: Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [ ... ]))`，这样加第三个按钮后在窄屏上会换行而不是溢出；然后在「从剪贴板粘贴」按钮**之前**插入：

```dart
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFFD8A24A),
                              ),
                              icon: const Text('✨', style: TextStyle(fontSize: 14)),
                              label: const Text(
                                '让 AI 按角色写故事',
                                style: TextStyle(fontSize: 12),
                              ),
                              onPressed: _isProcessing ? null : _openStoryComposer,
                            ),
```

（d）`README.md` 的「🧸 角色卡」小节，在「**选卡写故事**」那条之后加一条：

```
- **AI 帮孩子写故事**：选好角色卡后点「让 AI 按角色写故事」，用一句话描述想讲的故事，AI 写出 400 到 700 字的儿童故事；可以直接修改文字，也可以提出建议让它在现有文本上重写，随时回到上一版；满意后一键回填创建页。
```

（e）`AGENTS.md` §2.1 功能全景，在「角色卡：…」那行之后加：

```
 │    ├── 故事助手：角色卡 + 一句描述生成儿童故事，可手改与反馈重写，草稿自动保存 (StoryComposerScreen)
```

§4 目录树 `screens/` 下 `character_card_editor_screen.dart` 之后加：

```
    ├── story_composer_screen.dart     # 故事创作助手页 (生成/反馈重写/版本回退/草稿)
```

- [ ] **Step 4: 运行相关测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/create_book_screen_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "create_book_screen|story_composer" || echo "analyze: no lines for touched files"`

Expected: 6 tests passed（连续跑 3 次）；grep 无输出。

- [ ] **Step 5: 全量验证**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter analyze | tail -1 && $HOME/development/flutter/bin/flutter test`

Expected: analyze 总数与 `main` 一致（38 条，全为原有提示）；全部测试通过（P1 后 84 条 + 本期新增约 16 条）。若默认并发出现重试噪音，再跑 `--concurrency=1` 并以它为准。

- [ ] **Step 6: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/screens/create_book_screen.dart README.md AGENTS.md test/create_book_screen_test.dart && git commit -m "feat(story): open the story composer from the create screen and fill the result back

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

- [ ] **Step 7: 手动验收（用户执行，不在实施者范围内）**

按 spec §10 P2：选 2 张卡，输入一句描述，生成 400 到 700 字故事且两个角色的名字与口头禅都出现；手改一句后提交反馈重写，手改内容保留、反馈内容生效；「回到上一版」能恢复；「用这个故事」回填创建页后，走现有分镜流程成书。

```bash
$HOME/development/flutter/bin/flutter run -d macos
```

---

## 自检记录

**Spec 覆盖（P2 范围）**

| Spec 条目 | 任务 |
|---|---|
| 3.3 `StoryDraftResult` | Task 1 |
| 5.1 `temperature` 入参与默认行为不变 | Task 1（含三协议回归测试） |
| 5.5 `composeStory`：身份、角色使用、结构、输出、修改模式、温度、解析与兜底 | Task 1 |
| 6.4 入口按钮与回填（正文非空先确认） | Task 4 |
| 6.7 角色条、描述框与灵感芯片、生成按钮、故事区、反馈框、版本回退、「用这个故事」、草稿自动保存 | Task 2（1–7）、Task 3（8） |
| 8 故事生成失败：SnackBar、编辑框与版本栈不变 | Task 2 |
| 9 `story_composer_test`、widget 芯片填入 | Task 1、Task 2 |
| 10 P2 验收 | Task 4 Step 7（用户） |

**类型一致性**：`StoryDraftResult({required title, required story})` 在 Task 1 定义，Task 2 的 `_useStory` 与 Task 4 的 `Navigator.push<StoryDraftResult>` 一致；`composeStory` 命名参数 `settings / cards / brief / currentStory / feedback` 在 Task 2 的 `_run` 中一致；`StoryComposerScreen({cards, engine, loadSettings})` 在 Task 2 定义、Task 4 使用；`fakeLlmDio(Map, List)` 与 `runIo` 是 `test/create_book_screen_test.dart` 现有辅助。

**占位扫描**：无 TBD / TODO；每个代码步骤都给出了完整代码或精确的替换前后片段。
