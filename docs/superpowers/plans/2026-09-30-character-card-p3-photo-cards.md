# 角色卡 P3：拍照生成角色卡 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在角色卡编辑页拍一张玩具 / 宠物 / 小物件的照片（桌面端从相册选图），照片压缩去元数据后存本机；「让 AI 认识它」用多模态模型识别并填好表单；生成定妆图时把照片作为参考图，让角色更像真实玩具；角色卡用于绘本时，审核页补画定妆照也带上照片，而故事分镜与故事页请求始终不含照片。

**Architecture:** 新增两个小服务：`PhotoPickerService`（包 `image_picker`，可在测试中替换）与 `preprocessPhoto`（`image` 包：解码 → 按 EXIF 摆正 → 长边 1024 → 清空 EXIF → JPEG 85，放在后台 isolate 跑）。引擎的 `_callLlm` 增加图片入参（三协议），新增 `describeCharacterFromPhoto`；`generateCharacterReference` 可带照片参考，三条生图分支按 `isPhoto` 切换参考图说明；`_extractJson` 改为不抛原始解析异常。编辑页加照片区、识别按钮与照片感知的定妆图生成；创建页 `_buildPinned` 读卡片照片、审核页定妆照生成时附带（仅当书内外貌未改）。

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4；**新增依赖** `image_picker: ^1.2.3`、`image: ^4.10.1`；已有 `dio`、`path_provider`、`shared_preferences`、`wakelock_plus`；`flutter_test`。

**Spec:** `docs/superpowers/specs/2026-09-28-character-card-design.md`（第 5.1 图片输入、5.2、5.3、6.3 第 1、2、5、8 条、6.5 照片参考、第 7 节、第 8 节、第 10 节 P3，以及第 13 节规则 5、8、9）。P0–P2 已合并到 `main`（836331d 及之前），本计划从 `main` 分支。

## Global Constraints

- Flutter SDK 绝对路径 `$HOME/development/flutter/bin/flutter`；**任何 `pub` 命令前必须** `export PUB_HOSTED_URL="https://pub.flutter-io.cn" && export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"`。
- 本期只新增 `image_picker` 与 `image` 两个依赖，不加其它包。
- 每个任务结束前运行 `$HOME/development/flutter/bin/flutter analyze` 与对应测试文件；analyze 按文件核对：涉及的 `lib/` 与 `test/` 文件不得出现任何新行（`book_engine_service.dart` 原有 5 条 `curly_braces_in_flow_control_structures` 与其它文件原有弃用提示不算）。
- 照片：长边 ≤ 1024 的 JPEG（质量 85），**先按 EXIF 方向摆正、再清空 EXIF**；卡片目录内固定文件名 `photo.jpg`；只在识图与生成定妆图时上传，**故事分镜请求与故事页生图请求不得包含照片**。
- 「拍照」按钮只在 Android / iOS（非 Web）显示；「从相册选择」全平台显示；桌面不申请摄像头权限。
- 识图：`name`、`kind`、`appearance` 必填，缺失或为空抛 `FormatException('识图结果格式不正确')`；其余字段缺失为空字符串；未知 `kind` 取 `animal`。激活模型不支持图片时上游错误原样抛出，页面提示切换多模态模型。
- 照片参考说明文字（三条生图分支一致的核心句）：「请按照片中的外形、颜色、材质和标志性细节绘制这个角色，并转换为当前绘本画风；忽略照片的背景、光线和拍摄角度。」
- 编辑页页脚固定文案：「照片只保存在本机；识别和生成定妆图时会各上传一次，故事页不会上传照片。修改角色卡只影响之后新建的绘本。」
- 新测试文件统一 `import 'support/run_io.dart';` 使用共享的 `runIo`（本期新建）；已有测试文件里的 `runIo` 副本不动。
- 工作区里有用户本机运行 App 产生的未提交 ios/macos CocoaPods 文件（`ios/Flutter/*.xcconfig`、`macos/Flutter/*.xcconfig`、`macos/Runner.xcodeproj/project.pbxproj`、`macos/Runner.xcworkspace/contents.xcworkspacedata`、`ios/Podfile`、`macos/Podfile`、`macos/Podfile.lock`）：**一律不暂存**，每个任务只 `git add` 自己的文件。
- 提交信息遵循 Conventional Commits，末尾附 `Co-Authored-By: Claude <模型名> <noreply@anthropic.com>`（任意 Claude 型号均可）。
- 手动验收（spec §10 P3，真机拍照）留给用户。

---

## 文件结构

| 文件 | 改动 |
|---|---|
| `pubspec.yaml`、`pubspec.lock` | 新增 `image_picker`、`image` |
| `macos/Flutter/GeneratedPluginRegistrant.swift`、`linux/flutter/*`、`windows/flutter/*` | `pub get` 自动生成的插件注册 |
| `ios/Runner/Info.plist` | 相机、相册用途说明 |
| `macos/Runner/DebugProfile.entitlements`、`Release.entitlements` | 读取用户所选文件 |
| `lib/services/photo_preprocessor.dart`（新建） | `preprocessPhoto` |
| `lib/services/photo_picker_service.dart`（新建） | `PhotoSource`、`PhotoPickerService` |
| `lib/services/character_storage_service.dart` | `deleteImage` |
| `lib/services/book_engine_service.dart` | `_extractJson` 不抛；`LlmImageInput`、`CharacterCardDraft`；`_callLlm(images:)`；`describeCharacterFromPhoto`；`_ImageReference.isPhoto`；`generateCharacterReference(photoReferenceBase64:)` |
| `lib/screens/character_card_editor_screen.dart` | 照片区、识别、照片参考生成、页脚 |
| `lib/screens/create_book_screen.dart` | `_buildPinned` 读照片 |
| `lib/screens/storyboard_review_screen.dart` | 卡片角色定妆照附带照片 |
| `lib/main.dart`、`lib/screens/character_library_screen.dart` | 引导与空状态文案 |
| `README.md`、`AGENTS.md` | 功能说明与目录树 |
| `test/support/run_io.dart`（新建） | 共享 `runIo` |
| `test/photo_preprocessor_test.dart`（新建） | 预处理 |
| `test/character_storage_service_test.dart` | `deleteImage` |
| `test/character_vision_test.dart`（新建） | 图片输入三协议、识图、照片参考、解析 |
| `test/character_card_editor_photo_test.dart`（新建） | 编辑页照片流程 |
| `test/photo_privacy_test.dart`（新建） | 分镜与故事页不含照片 |
| `test/storyboard_review_pinned_test.dart`、`test/create_book_screen_test.dart`、`test/widget_test.dart`、`test/character_library_screen_test.dart` | 照片传递与文案 |

---

### Task 0: 建立功能分支

**Files:** 无（controller 执行：建分支、提交 spec 第 13 节回填与本计划）

- [ ] **Step 1**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git checkout main && git checkout -b feat/character-cards-p3 && git add docs/superpowers/specs/2026-09-28-character-card-design.md docs/superpowers/plans/2026-09-30-character-card-p3-photo-cards.md && git commit -m "docs: record settled character card rules and add the P3 photo plan

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: 依赖、平台配置、照片预处理与取图服务

**Files:**
- Modify: `pubspec.yaml`、`pubspec.lock`（`flutter pub add` 生成）、插件注册生成文件
- Modify: `ios/Runner/Info.plist`、`macos/Runner/DebugProfile.entitlements`、`macos/Runner/Release.entitlements`
- Create: `lib/services/photo_preprocessor.dart`、`lib/services/photo_picker_service.dart`
- Modify: `lib/services/character_storage_service.dart`（`clearAnchors` 之后加 `deleteImage`）
- Create: `test/support/run_io.dart`、`test/photo_preprocessor_test.dart`
- Test: `test/character_storage_service_test.dart`（追加）

**Interfaces:**
- Produces:
  - `const int kPhotoMaxEdge = 1024;` `Uint8List preprocessPhoto(Uint8List bytes)`（顶层函数，可交给 `compute`；无法解码抛 `FormatException('无法读取这张图片')`）
  - `enum PhotoSource { camera, gallery }`
  - `class PhotoPickerService { PhotoPickerService({ImagePicker? picker}); bool get supportsCamera; Future<Uint8List?> pick(PhotoSource source); Future<Uint8List?> retrieveLost(); }`
  - `CharacterStorageService.deleteImage(String relativePath) → Future<void>`（沿用 `imageFile` 的路径穿越防护；文件不存在时不报错）
  - `test/support/run_io.dart` 里的 `Future<void> runIo(WidgetTester tester, Future<void> Function() body, {bool Function()? until, int maxRounds = 60})`

- [ ] **Step 1: 添加依赖**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && export PUB_HOSTED_URL="https://pub.flutter-io.cn" && export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn" && $HOME/development/flutter/bin/flutter pub add image_picker:^1.2.3 image:^4.10.1 && git status --short | grep -v "ios/Flutter\|macos/Flutter/Flutter-\|Runner.xcodeproj\|Runner.xcworkspace\|Podfile"
```

Expected: `pubspec.yaml`、`pubspec.lock` 变更；`macos/Flutter/GeneratedPluginRegistrant.swift`、`linux/flutter/…`、`windows/flutter/…` 可能变更（插件注册）。若 `pub add` 卡住超过 3 分钟，按 AGENTS.md §1.4 清理残留 `dart` 进程后重试一次。

- [ ] **Step 2: 平台配置**

`ios/Runner/Info.plist`：在 `<key>LSRequiresIPhoneOS</key>` 与其后的值（`<true/>`）这一对之后插入：

```xml
	<key>NSCameraUsageDescription</key>
	<string>拍一张玩具或宠物的照片，用来创建专属的绘本角色。</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>从相册选一张玩具或宠物的照片，用来创建专属的绘本角色。</string>
```

`macos/Runner/DebugProfile.entitlements` 与 `macos/Runner/Release.entitlements`：各自在末尾 `</dict>` 之前插入：

```xml
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
```

- [ ] **Step 3: 写失败的测试**

创建 `test/support/run_io.dart`（非 `_test.dart` 结尾，不会被当作测试运行）：

```dart
import 'package:flutter_test/flutter_test.dart';

/// 在真实事件循环里执行会产生文件 / 网络 / isolate Future 的操作，然后交替「让出真实时间片」与
/// 「冲刷一次 FakeAsync 微任务队列」，直到 [until] 成立或达到 [maxRounds]。
/// 必须交替两个独立调用而不能嵌套在同一个 runAsync 里：每一跳完成后的延续
/// 排在测试时钟的微任务队列上，只有 pump 一次才会被取出执行。
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
```

创建 `test/photo_preprocessor_test.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:bookbuddy/services/photo_preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

bool containsAscii(Uint8List bytes, String marker) {
  final pattern = ascii.encode(marker);
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    var hit = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return true;
  }
  return false;
}

void main() {
  test('大图按 EXIF 方向摆正、长边缩到 1024，输出不含 EXIF 的 JPEG', () {
    final src = img.Image(width: 2000, height: 1500);
    img.fill(src, color: img.ColorRgb8(40, 160, 90));
    src.exif.imageIfd.orientation = 6; // 需要顺时针转 90° 才是正的
    src.exif.imageIfd['Make'] = img.IfdValueAscii('TestCam');
    final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));
    expect(containsAscii(input, 'Exif'), isTrue, reason: '测试输入应当带 EXIF');

    final output = preprocessPhoto(input);

    expect(output[0], 0xFF);
    expect(output[1], 0xD8); // JPEG 文件头
    expect(containsAscii(output, 'Exif'), isFalse);
    expect(containsAscii(output, 'TestCam'), isFalse);
    final decoded = img.decodeJpg(output)!;
    expect(decoded.width, 768);
    expect(decoded.height, 1024);
  });

  test('小图不放大，只重编码为 JPEG', () {
    final src = img.Image(width: 300, height: 200);
    img.fill(src, color: img.ColorRgb8(200, 100, 50));
    final output = preprocessPhoto(Uint8List.fromList(img.encodePng(src)));
    final decoded = img.decodeJpg(output)!;
    expect(decoded.width, 300);
    expect(decoded.height, 200);
  });

  test('无法解码的字节抛出约定的 FormatException', () {
    expect(
      () => preprocessPhoto(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(
        isA<FormatException>().having((e) => e.message, 'message', '无法读取这张图片'),
      ),
    );
  });
}
```

若 `image` 包的 EXIF API 与上面写法不同（例如 `imageIfd['Make']` 不接受字符串标签），用等价写法（如 `src.exif.imageIfd[0x010F] = img.IfdValueAscii('TestCam')`，0x010F 即 Make）并在报告里说明。若第一个断言 `containsAscii(input, 'Exif')` 失败（说明编码器不写 EXIF），把该测试的方向断言改为 `1024 × 768`、去掉 sanity 断言，并在报告里写明——这会改变第 13 节规则 8 的前提，controller 需要知道。

在 `test/character_storage_service_test.dart` 的 `main()` 收尾 `}` 之前追加：

```dart
  test('deleteImage 删除卡片目录里的图片，文件不存在时不报错', () async {
    final relative =
        await storage.writeImage('card_a', 'photo.jpg', Uint8List.fromList([1, 2]));
    expect(await File('${dir.path}/card_a/photo.jpg').exists(), isTrue);
    await storage.deleteImage(relative);
    expect(await File('${dir.path}/card_a/photo.jpg').exists(), isFalse);
    await storage.deleteImage(relative);
  });

  test('deleteImage 拒绝逃出角色库目录的路径', () async {
    await expectLater(storage.deleteImage('../x.jpg'), throwsArgumentError);
  });
```

- [ ] **Step 4: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/photo_preprocessor_test.dart test/character_storage_service_test.dart`

Expected: 编译失败（`photo_preprocessor.dart` 不存在、`deleteImage` 未定义）。

- [ ] **Step 5: 实现**

创建 `lib/services/photo_preprocessor.dart`：

```dart
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 角色照片的长边上限（像素）。
const int kPhotoMaxEdge = 1024;

/// 解码 → 按 EXIF 方向摆正 → 长边缩到 [kPhotoMaxEdge] → 清空 EXIF → 质量 85 的 JPEG。
/// 顶层函数，可以直接交给 `compute` 在后台 isolate 里跑。
Uint8List preprocessPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('无法读取这张图片');
  }
  // 手机照片常把方向写在 EXIF 里：先摆正再丢掉 EXIF，否则图会歪。
  var image = img.bakeOrientation(decoded);
  final longEdge = image.width > image.height ? image.width : image.height;
  if (longEdge > kPhotoMaxEdge) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: kPhotoMaxEdge,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: kPhotoMaxEdge,
            interpolation: img.Interpolation.average,
          );
  }
  // 位置、机型等元数据一律不带出本机。
  image.exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}
```

（若 `Image.exif` 没有 setter，改用 `image.exif.clear()` 并在报告里说明。）

创建 `lib/services/photo_picker_service.dart`：

```dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

/// 取图的薄封装：页面只依赖这个类，测试里可以换成假实现。
class PhotoPickerService {
  PhotoPickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// 只有手机能直接拍照；桌面与 Web 只提供从相册 / 文件选图。
  bool get supportsCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 返回原始图片字节；用户取消时返回 null。先让系统把超大图缩一轮，后续还会统一预处理。
  Future<Uint8List?> pick(PhotoSource source) async {
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  /// Android 上拍照时进程可能被系统回收；重新进入编辑页时找回那张照片。其他平台返回 null。
  Future<Uint8List?> retrieveLost() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty) return null;
      final files = response.files;
      final file = response.file ??
          (files != null && files.isNotEmpty ? files.first : null);
      return file?.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
```

（若 `LostDataResponse` 在当前 `image_picker` 版本里没有 `file` 或 `files` 之一，按实际 API 取第一张并说明。）

在 `lib/services/character_storage_service.dart` 的 `clearAnchors` 方法之后追加：

```dart
  /// 删除卡片目录下的一张图片（如移除照片）；文件不存在时什么也不做。
  Future<void> deleteImage(String relativePath) async {
    final file = await imageFile(relativePath); // 沿用路径穿越防护
    if (await file.exists()) await file.delete();
  }
```

- [ ] **Step 6: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/photo_preprocessor_test.dart test/character_storage_service_test.dart && $HOME/development/flutter/bin/flutter test && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "photo_|character_storage|run_io" || echo "analyze: no lines for touched files"`

Expected: 3 + 20 条通过；全量测试全部通过（新增插件不影响现有测试）；grep 无输出。

- [ ] **Step 7: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add pubspec.yaml pubspec.lock ios/Runner/Info.plist macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements lib/services/photo_preprocessor.dart lib/services/photo_picker_service.dart lib/services/character_storage_service.dart test/support/run_io.dart test/photo_preprocessor_test.dart test/character_storage_service_test.dart && git add -u macos/Flutter/GeneratedPluginRegistrant.swift linux/flutter windows/flutter && git status --short | grep "^[AM]" && git commit -m "feat(photo): add image picker, photo preprocessing and platform permissions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

（`git add -u` 只暂存这些路径下已跟踪文件的改动；确认暂存列表里没有 `ios/Flutter/*.xcconfig`、`macos/Flutter/Flutter-*.xcconfig`、`project.pbxproj`、`contents.xcworkspacedata`、`Podfile*`。）

---

### Task 2: 引擎：图片输入、识图、照片参考、解析不抛

**Files:**
- Modify: `lib/services/book_engine_service.dart`
- Test: `test/character_vision_test.dart`（新建）

**Interfaces:**
- Consumes: `CharacterKind`（`lib/models/character_card.dart`）
- Produces:
  - `class LlmImageInput { final String base64; final String mimeType; const LlmImageInput({required this.base64, required this.mimeType}); }`
  - `class CharacterCardDraft { final String name; final CharacterKind kind; final String species; final String appearance; final String defaultOutfit; final String personality; final String catchphrase; }`
  - `_callLlm({..., double? temperature, List<LlmImageInput> images = const []})`
  - `Future<CharacterCardDraft> describeCharacterFromPhoto({required AppSettings settings, required String photoBase64, required String mimeType})`
  - `Future<String?> generateCharacterReference({required settings, required style, required character, String? photoReferenceBase64})`
  - `_extractJson` 不再抛异常（无法解析返回 `{}`）

- [ ] **Step 1: 写失败的测试**

创建 `test/character_vision_test.dart`：

```dart
import 'dart:convert';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 按顺序对每个请求返回 [responder] 的结果，并记录请求体。
Dio recordingDio(List<dynamic> sent, Map<String, dynamic> Function() responder) =>
    Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent.add(options.data);
            handler.resolve(Response(requestOptions: options, data: responder()));
          },
        ),
      );

Map<String, dynamic> openAiReply(String content) => {
      'choices': [
        {
          'message': {'content': content},
        },
      ],
    };

Map<String, dynamic> geminiReply(String content) => {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': content},
            ],
          },
        },
      ],
    };

Map<String, dynamic> anthropicReply(String content) => {
      'content': [
        {'type': 'text', 'text': content},
      ],
    };

final draftJson = jsonEncode({
  'name': '小满',
  'kind': 'object',
  'species': '鹅卵石',
  'appearance': '圆润的灰色鹅卵石，表面有白色斑点',
  'defaultOutfit': '',
  'personality': '慢吞吞但很可靠',
  'catchphrase': '别急，我在这儿',
});

const photo = '/9j/4AAQSkZJRgABAQAAAQABAAD';

AppSettings llm(String type) => AppSettings(
      llmType: type,
      llmBaseUrl: 'https://example.test',
      llmApiKey: 'test',
      llmModel: 'vision-model',
    );

const style = BookStyle(
  id: 'watercolor',
  name: '水彩童话',
  desc: '',
  prefix: '水彩',
  negative: '',
);

final stone = BookCharacter(
  id: 'card_stone',
  name: '小满',
  species: '鹅卵石',
  appearance: '圆润的灰色鹅卵石',
  defaultOutfit: '无服装，保持物件本来的外观',
);

void main() {
  test('OpenAI 兼容：图片以 data URL 放在文本前，解析出角色草稿', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: recordingDio(sent, () => openAiReply(draftJson)));
    final draft = await engine.describeCharacterFromPhoto(
      settings: llm('openai'),
      photoBase64: photo,
      mimeType: 'image/jpeg',
    );
    expect(draft.name, '小满');
    expect(draft.kind, CharacterKind.object);
    expect(draft.species, '鹅卵石');
    expect(draft.appearance, contains('灰色鹅卵石'));
    expect(draft.defaultOutfit, '');
    expect(draft.catchphrase, '别急，我在这儿');

    final body = sent.single as Map;
    final system = body['messages'][0]['content'] as String;
    expect(system, contains('2 到 4 个汉字'));
    expect(system, contains('不写背景'));
    final content = body['messages'][1]['content'] as List;
    expect(content.first['type'], 'image_url');
    expect(content.first['image_url']['url'], 'data:image/jpeg;base64,$photo');
    expect(content.last['type'], 'text');
    expect(body.containsKey('temperature'), isFalse);
  });

  test('Gemini：inlineData 在文本之前，温度保持默认 0.3', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: recordingDio(sent, () => geminiReply(draftJson)));
    await engine.describeCharacterFromPhoto(
      settings: llm('gemini'),
      photoBase64: photo,
      mimeType: 'image/jpeg',
    );
    final body = sent.single as Map;
    final parts = body['contents'][0]['parts'] as List;
    expect(parts.first['inlineData'], {'mimeType': 'image/jpeg', 'data': photo});
    expect(parts.last['text'], isA<String>());
    expect(body['generationConfig']['temperature'], 0.3);
  });

  test('Anthropic：image source 块在文本之前', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: recordingDio(sent, () => anthropicReply(draftJson)));
    await engine.describeCharacterFromPhoto(
      settings: llm('anthropic'),
      photoBase64: photo,
      mimeType: 'image/jpeg',
    );
    final content = (sent.single as Map)['messages'][0]['content'] as List;
    expect(content.first, {
      'type': 'image',
      'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': photo},
    });
    expect(content.last['type'], 'text');
  });

  test('没有图片时三种协议的用户消息保持原样', () async {
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
    final openAiSent = <dynamic>[];
    await BookEngineService(dio: recordingDio(openAiSent, () => openAiReply(storyboard)))
        .createStoryboardDraft(settings: llm('openai'), title: '山', storyText: '从前有座山。');
    expect((openAiSent.single as Map)['messages'][1]['content'], isA<String>());

    final anthropicSent = <dynamic>[];
    await BookEngineService(dio: recordingDio(anthropicSent, () => anthropicReply(storyboard)))
        .createStoryboardDraft(settings: llm('anthropic'), title: '山', storyText: '从前有座山。');
    expect((anthropicSent.single as Map)['messages'][0]['content'], isA<String>());

    final geminiSent = <dynamic>[];
    await BookEngineService(dio: recordingDio(geminiSent, () => geminiReply(storyboard)))
        .createStoryboardDraft(settings: llm('gemini'), title: '山', storyText: '从前有座山。');
    expect((geminiSent.single as Map)['contents'][0]['parts'], hasLength(1));
  });

  test('缺少必填字段或 JSON 损坏时给出约定的格式错误；未知 kind 取 animal', () async {
    final missing = BookEngineService(
      dio: recordingDio([], () => openAiReply(jsonEncode({'name': '小满', 'kind': 'object'}))),
    );
    await expectLater(
      missing.describeCharacterFromPhoto(settings: llm('openai'), photoBase64: photo, mimeType: 'image/jpeg'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', '识图结果格式不正确')),
    );

    const broken = '{"name": "小满", "kind": "object", "appearance": "第一行\n第二行 "引号""}';
    final corrupt = BookEngineService(dio: recordingDio([], () => openAiReply(broken)));
    await expectLater(
      corrupt.describeCharacterFromPhoto(settings: llm('openai'), photoBase64: photo, mimeType: 'image/jpeg'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', '识图结果格式不正确')),
    );

    final unknownKind = BookEngineService(
      dio: recordingDio([], () => openAiReply(jsonEncode({'name': '豆豆', 'kind': 'dragon', 'appearance': '绿色毛绒'}))),
    );
    final draft = await unknownKind.describeCharacterFromPhoto(
      settings: llm('openai'),
      photoBase64: photo,
      mimeType: 'image/jpeg',
    );
    expect(draft.kind, CharacterKind.animal);
    expect(draft.species, '');
  });

  test('分镜回复是损坏的 JSON 时不再抛出 Dart 原始异常，而是得到空分镜', () async {
    const broken = '{"scenes": [{"text": "第一行\n第二行 "引号""}]}';
    final draft = await BookEngineService(dio: recordingDio([], () => openAiReply(broken)))
        .createStoryboardDraft(settings: llm('openai'), title: '山', storyText: '从前有座山。');
    expect(draft.pages, isEmpty);
  });

  test('支持参考图的通道：定妆照请求带上照片与照片说明', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: recordingDio(sent, () => {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'inlineData': {'data': 'new-image'},
                    },
                  ],
                },
              },
            ],
          }),
    );
    final result = await engine.generateCharacterReference(
      settings: AppSettings(
        imageType: 'gemini',
        imageBaseUrl: 'https://example.test',
        imageModel: 'gemini-2.5-flash-image',
        imageApiKey: 'k',
      ),
      style: style,
      character: stone,
      photoReferenceBase64: photo,
    );
    expect(result, 'new-image');
    final parts = (sent.single as Map)['contents'][0]['parts'] as List;
    expect(parts.first['inlineData']['data'], photo);
    expect(parts[1]['text'], contains('真实玩具或物件照片'));
    expect(parts[1]['text'], contains('忽略照片的背景、光线和拍摄角度'));
    expect(parts.last['text'], contains('单独绘制角色定妆照'));
  });

  test('不支持参考图的通道：照片被忽略，请求里没有照片', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: recordingDio(sent, () => {
            'predictions': [
              {'bytesBase64Encoded': 'new-image'},
            ],
          }),
    );
    await engine.generateCharacterReference(
      settings: AppSettings(
        imageType: 'gemini',
        imageBaseUrl: 'https://example.test',
        imageModel: 'imagen-3.0-generate-002',
        imageApiKey: 'k',
      ),
      style: style,
      character: stone,
      photoReferenceBase64: photo,
    );
    expect(jsonEncode(sent.single), isNot(contains(photo)));
  });

  test('定妆照仍按原文案标注，照片说明只出现在照片参考上', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: recordingDio(sent, () => {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'inlineData': {'data': 'page'},
                    },
                  ],
                },
              },
            ],
          }),
    );
    final anchored = BookCharacter.fromJson(stone.toJson())
      ..referenceImageBase64 = photo;
    await engine.generateIllustration(
      settings: AppSettings(
        imageType: 'gemini',
        imageBaseUrl: 'https://example.test',
        imageModel: 'gemini-2.5-flash-image',
        imageApiKey: 'k',
      ),
      style: style,
      page: BookPageItem(pageIndex: 0, text: '小满在河边。', characterIds: ['card_stone']),
      characters: [anchored],
    );
    final text = jsonEncode(sent.single);
    expect(text, contains('的定妆照'));
    expect(text, isNot(contains('真实玩具或物件照片')));
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_vision_test.dart`

Expected: 编译失败（`describeCharacterFromPhoto`、`photoReferenceBase64` 不存在）。

- [ ] **Step 3: 实现引擎改动**

`lib/services/book_engine_service.dart`（用 `ctx_read(mode="lines:N-M")` 定位后用 Edit 精确修改；不要整文件格式化）：

（a）`class StoryDraftResult { ... }` 之后加：

```dart
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
```

（b）`class _ImageReference` 改为：

```dart
class _ImageReference {
  final String name;
  final String base64;
  final bool isPhoto;
  const _ImageReference(this.name, this.base64, {this.isPhoto = false});
}
```

并在 `BookEngineService` 类体开头（`final Dio _dio;` 之后）加：

```dart
  /// 真实照片作参考图时附在说明里的要求（三条生图分支共用）。
  static const _photoGuidance =
      '请按照片中的外形、颜色、材质和标志性细节绘制这个角色，并转换为当前绘本画风；忽略照片的背景、光线和拍摄角度。';
```

（c）三条生图分支的参考图说明按 `isPhoto` 切换（定妆照文案保持原样）：

- TokenHub 分支（`'以下参考图是${sanitizePrompt(reference.name)}的定妆照，仅参考此角色的外貌与服装，不复制姿势和朝向。'`）改为
  `reference.isPhoto ? '以下参考图是${sanitizePrompt(reference.name)}的真实玩具或物件照片。$_photoGuidance' : '以下参考图是${sanitizePrompt(reference.name)}的定妆照，仅参考此角色的外貌与服装，不复制姿势和朝向。'`
- Gemini 多模态分支（`'上一张图片是…的定妆照。只将其用于此角色的外貌和默认服装，不复制背景、姿势或朝向。'`）改为
  `reference.isPhoto ? '上一张图片是${sanitizePrompt(reference.name)}的真实玩具或物件照片。$_photoGuidance' : '上一张图片是${sanitizePrompt(reference.name)}的定妆照。只将其用于此角色的外貌和默认服装，不复制背景、姿势或朝向。'`
- OpenAI chat 降级分支（`'以下图片是${sanitizePrompt(reference.name)}的定妆照。'`）改为
  `reference.isPhoto ? '以下图片是${sanitizePrompt(reference.name)}的真实玩具或物件照片。$_photoGuidance' : '以下图片是${sanitizePrompt(reference.name)}的定妆照。'`

（d）`generateCharacterReference` 改为（提示词本身不变）：

```dart
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
```

（e）`_callLlm` 签名加 `List<LlmImageInput> images = const [],`（放在 `double? temperature,` 之后），三个分支：

- Gemini：`'parts': [ {'text': userPrompt}, ],` 改为

```dart
              'parts': [
                for (final image in images)
                  {
                    'inlineData': {'mimeType': image.mimeType, 'data': image.base64},
                  },
                {'text': userPrompt},
              ],
```

  （只改 `contents` 里的那个 `parts`，`systemInstruction` 的 `parts` 不动。）
- Anthropic：`{'role': 'user', 'content': userPrompt},` 改为

```dart
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
```

- OpenAI 兼容：`{'role': 'user', 'content': userPrompt},` 改为

```dart
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
```

（f）`_extractJson` 的兜底解析放进 try，失败返回 `{}`：

```dart
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
```

并把 `composeStory` 里包着 `_extractJson(raw)` 的 `try { … } on FormatException { throw const FormatException('故事生成结果格式不正确'); }` 还原为 `final parsed = _extractJson(raw);`（`_extractJson` 不再抛，空结果照样走「故事生成结果格式不正确」）。

（g）在 `_storyCastBlock` 方法之后、`createStoryboardDraft` 之前加：

```dart
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
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_vision_test.dart test/story_composer_test.dart test/book_engine_pinned_test.dart test/character_consistency_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "book_engine|character_vision" | grep -v curly_braces || echo "analyze: no new lines for touched files"`

Expected: 9 + 11 + 9 + 9 条通过；grep 只剩 `echo` 提示。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/services/book_engine_service.dart test/character_vision_test.dart && git commit -m "feat(photo): send photos to vision models, describe characters and reference photos in portraits

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 编辑页：照片区、识别、照片参考生成

**Files:**
- Modify: `lib/screens/character_card_editor_screen.dart`
- Test: `test/character_card_editor_photo_test.dart`（新建）

**Interfaces:**
- Consumes: `PhotoPickerService` / `PhotoSource`、`preprocessPhoto`（Task 1）；`CharacterStorageService.writeImage / imageFile / readImageBase64 / deleteImage / saveCard / deleteCard`；`BookEngineService.describeCharacterFromPhoto / generateCharacterReference(photoReferenceBase64:)`、`CharacterCardDraft`（Task 2）
- Produces: `CharacterCardEditorScreen({card, storage, engine, loadSettings, PhotoPickerService? photoPicker})`

- [ ] **Step 1: 写失败的测试**

创建 `test/character_card_editor_photo_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/character_card_editor_screen.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:bookbuddy/services/photo_picker_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/run_io.dart';

class FakePhotoPicker extends PhotoPickerService {
  FakePhotoPicker({this.photo, this.camera = true});

  final Uint8List? photo;
  final bool camera;
  final List<PhotoSource> requests = [];

  @override
  bool get supportsCamera => camera;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    requests.add(source);
    return photo;
  }

  @override
  Future<Uint8List?> retrieveLost() async => null;
}

Dio recordingDio(List<dynamic> sent, Map<String, dynamic> Function() responder) =>
    Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent.add(options.data);
            handler.resolve(Response(requestOptions: options, data: responder()));
          },
        ),
      );

Uint8List toyPhoto() {
  final src = img.Image(width: 1600, height: 1200);
  img.fill(src, color: img.ColorRgb8(60, 170, 90));
  return Uint8List.fromList(img.encodePng(src));
}

final draftReply = {
  'choices': [
    {
      'message': {
        'content': jsonEncode({
          'name': '豆豆',
          'kind': 'object',
          'species': '毛绒恐龙',
          'appearance': '绿色毛绒恐龙，肚皮米白',
          'defaultOutfit': '',
          'personality': '胆子大',
          'catchphrase': '冲啊！',
        }),
      },
    },
  ],
};

AppSettings visionSettings() => AppSettings(
      llmType: 'openai',
      llmBaseUrl: 'https://example.test',
      llmApiKey: 'k',
      llmModel: 'gpt-4o',
      imageType: 'gemini',
      imageBaseUrl: 'https://example.test',
      imageApiKey: 'k',
      imageModel: 'gemini-2.5-flash-image',
    );

ButtonStyleButton buttonWithText(WidgetTester tester, String text) =>
    tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .first,
    );

List<Directory> cardDirs(Directory root) =>
    root.listSync().whereType<Directory>().toList();

void main() {
  late Directory dir;
  late CharacterStorageService storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bookbuddy-editor-photo-');
    storage = CharacterStorageService(directory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    CharacterCard? card,
    required PhotoPickerService picker,
    BookEngineService? engine,
    AppSettings? settings,
  }) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
                        loadSettings: () async => settings ?? visionSettings(),
                        photoPicker: picker,
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
    }, until: () => find.byType(CharacterCardEditorScreen).evaluate().isNotEmpty);
  }

  Future<void> pickFromGallery(WidgetTester tester) => runIo(
        tester,
        () => tester.tap(find.text('从相册选择')),
        until: () => find.text('移除照片').evaluate().isNotEmpty,
        maxRounds: 120,
      );

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextField, '角色名 *'), '豆豆');
    await tester.enterText(
      find.widgetWithText(TextField, '外貌锚定描述 *（颜色、材质、体型、标志性细节）'),
      '绿色毛绒恐龙',
    );
    await tester.pump();
  }

  testWidgets('选图后照片压缩为 JPEG 落盘，保存后卡片来源为照片', (tester) async {
    await pumpEditor(tester, picker: FakePhotoPicker(photo: toyPhoto()));
    await pickFromGallery(tester);

    final dirs = cardDirs(dir);
    expect(dirs, hasLength(1));
    final file = File('${dirs.single.path}/photo.jpg');
    final saved = file.readAsBytesSync();
    expect(saved[0], 0xFF);
    expect(saved[1], 0xD8);
    final decoded = img.decodeJpg(saved)!;
    expect(decoded.width, 1024);
    expect(decoded.height, 768);

    await fillRequired(tester);
    await runIo(
      tester,
      () => tester.tap(find.text('保存')),
      until: () => find.text('打开编辑页').evaluate().isNotEmpty,
    );
    final card = (jsonDecode(File('${dir.path}/cards.json').readAsStringSync()) as List)
        .single as Map<String, dynamic>;
    expect(card['source'], 'photo');
    expect(card['photoPath'], '${card['id']}/photo.jpg');
  });

  testWidgets('没有照片时识别按钮不可用；不支持拍照的平台不显示拍照', (tester) async {
    await pumpEditor(tester, picker: FakePhotoPicker(camera: false));
    expect(find.text('拍照'), findsNothing);
    expect(find.text('从相册选择'), findsOneWidget);
    expect(buttonWithText(tester, '让 AI 认识它').onPressed, isNull);
  });

  testWidgets('让 AI 认识它：空表单直接填入识别结果', (tester) async {
    final sent = <dynamic>[];
    await pumpEditor(
      tester,
      picker: FakePhotoPicker(photo: toyPhoto()),
      engine: BookEngineService(dio: recordingDio(sent, () => draftReply)),
    );
    await pickFromGallery(tester);
    await runIo(
      tester,
      () => tester.tap(find.text('让 AI 认识它')),
      until: () => find.text('已填入识别结果，请检查后保存').evaluate().isNotEmpty,
    );

    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, '角色名 *')).controller!.text,
      '豆豆',
    );
    expect(find.text('绿色毛绒恐龙，肚皮米白'), findsOneWidget);
    expect(find.text('冲啊！'), findsOneWidget);
    expect(
      tester.widget<SegmentedButton<CharacterKind>>(find.byType(SegmentedButton<CharacterKind>)).selected,
      {CharacterKind.object},
    );
    final content = (sent.single as Map)['messages'][1]['content'] as List;
    expect(content.first['image_url']['url'], startsWith('data:image/jpeg;base64,'));
  });

  testWidgets('已填内容时可以选择只填空白项', (tester) async {
    await pumpEditor(
      tester,
      picker: FakePhotoPicker(photo: toyPhoto()),
      engine: BookEngineService(dio: recordingDio([], () => draftReply)),
    );
    await pickFromGallery(tester);
    await tester.enterText(find.widgetWithText(TextField, '角色名 *'), '小满');
    await tester.pump();

    await runIo(
      tester,
      () => tester.tap(find.text('让 AI 认识它')),
      until: () => find.text('用识别结果填写表单？').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('只填空白项'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, '角色名 *')).controller!.text,
      '小满',
    );
    expect(find.text('绿色毛绒恐龙，肚皮米白'), findsOneWidget);
    expect(
      tester.widget<SegmentedButton<CharacterKind>>(find.byType(SegmentedButton<CharacterKind>)).selected,
      {CharacterKind.animal},
    );
  });

  testWidgets('生成定妆图时把照片作为参考图发出', (tester) async {
    final sent = <dynamic>[];
    final png = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
    await pumpEditor(
      tester,
      picker: FakePhotoPicker(photo: toyPhoto()),
      engine: BookEngineService(
        dio: recordingDio(sent, () => {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'inlineData': {'mimeType': 'image/png', 'data': png},
                      },
                    ],
                  },
                },
              ],
            }),
      ),
    );
    await pickFromGallery(tester);
    await fillRequired(tester);
    await runIo(
      tester,
      () => tester.tap(find.text('生成水彩童话定妆图')),
      until: () => find.text('重新生成水彩童话定妆图').evaluate().isNotEmpty,
      maxRounds: 120,
    );

    final photoOnDisk = base64Encode(
      File('${cardDirs(dir).single.path}/photo.jpg').readAsBytesSync(),
    );
    final parts = (sent.single as Map)['contents'][0]['parts'] as List;
    expect(parts.first['inlineData']['data'], photoOnDisk);
    expect(parts[1]['text'], contains('真实玩具或物件照片'));
  });

  testWidgets('生图通道不支持参考图时，前置对话框说明照片不会被参考', (tester) async {
    await pumpEditor(
      tester,
      picker: FakePhotoPicker(photo: toyPhoto()),
      settings: AppSettings(imageApiKey: 'k'),
    );
    await pickFromGallery(tester);
    await fillRequired(tester);
    await runIo(
      tester,
      () => tester.tap(find.text('生成水彩童话定妆图')),
      until: () => find.text('当前生图通道不支持参考图').evaluate().isNotEmpty,
    );
    expect(find.textContaining('照片不会被参考'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('已保存卡片移除照片后删除文件并更新卡片', (tester) async {
    final photoBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
    late CharacterCard card;
    await tester.runAsync(() async {
      final path = await storage.writeImage('card_toy', 'photo.jpg', photoBytes);
      card = CharacterCard(
        id: 'card_toy',
        source: CharacterCardSource.photo,
        name: '豆豆',
        appearance: '绿色',
        photoPath: path,
      );
      await storage.saveCard(card);
    });
    await pumpEditor(tester, card: card, picker: FakePhotoPicker());
    await runIo(tester, () async {}, until: () => find.text('移除照片').evaluate().isNotEmpty);

    await runIo(
      tester,
      () => tester.tap(find.text('移除照片')),
      until: () => find.text('移除照片').evaluate().isEmpty,
    );
    expect(File('${dir.path}/card_toy/photo.jpg').existsSync(), isFalse);
    final saved = (jsonDecode(File('${dir.path}/cards.json').readAsStringSync()) as List)
        .single as Map<String, dynamic>;
    expect(saved['photoPath'], isNull);
    expect(saved['source'], 'manual');
  });

  testWidgets('新建角色选了照片却没保存就离开时清理照片目录', (tester) async {
    await pumpEditor(tester, picker: FakePhotoPicker(photo: toyPhoto()));
    await pickFromGallery(tester);
    expect(cardDirs(dir), hasLength(1));

    await runIo(
      tester,
      () => tester.pageBack(),
      until: () => cardDirs(dir).isEmpty,
    );
    expect(cardDirs(dir), isEmpty);
  });

  test('真实取图服务只在手机上提供拍照', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(PhotoPickerService().supportsCamera, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(PhotoPickerService().supportsCamera, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(PhotoPickerService().supportsCamera, isTrue);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_card_editor_photo_test.dart`

Expected: 编译失败（`photoPicker` 不是命名参数）。

- [ ] **Step 3: 实现编辑页改动**

`lib/screens/character_card_editor_screen.dart`：

（a）import 区改为（保持 dart → package → 相对路径的顺序）：

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/app_settings.dart';
import '../models/character_card.dart';
import '../models/style_catalog.dart';
import '../services/book_engine_service.dart';
import '../services/character_storage_service.dart';
import '../services/photo_picker_service.dart';
import '../services/photo_preprocessor.dart';
import '../services/settings_service.dart';
import 'settings_screen.dart';
```

（若 analyzer 提示 `dart:typed_data` 与 `package:flutter/foundation.dart` 重复导出造成 `unnecessary_import`，删掉 `dart:typed_data` 这一行。）

（b）widget 加字段与构造参数 `final PhotoPickerService? photoPicker;` / `this.photoPicker,`。

（c）State 加字段：

```dart
  late final PhotoPickerService _photoPicker;

  /// 当前照片（已预处理的 JPEG 字节）；没有照片为 null。
  Uint8List? _photoBytes;
```

`initState` 末尾加：

```dart
    _photoPicker = widget.photoPicker ?? PhotoPickerService();
    _loadPhoto();
    _recoverLostPhoto();
```

`dispose` 开头加：

```dart
    // 新建且从未保存的角色：照片不应留在本机。
    if (_isNew && _card.photoPath != null) {
      unawaited(_storage.deleteCard(_card.id).catchError((_) {}));
    }
```

（d）在 `_saveAndClose` 之后加照片相关方法：

```dart
  Future<void> _loadPhoto() async {
    final path = _card.photoPath;
    if (path == null) return;
    try {
      final b64 = await _storage.readImageBase64(path);
      if (b64 == null || !mounted) return;
      setState(() => _photoBytes = base64Decode(b64));
    } catch (_) {
      // 照片文件丢失或路径异常：当作没有照片。
    }
  }

  Future<void> _recoverLostPhoto() async {
    final bytes = await _photoPicker.retrieveLost();
    if (bytes != null && mounted) await _setPhoto(bytes);
  }

  Future<void> _pickPhoto(PhotoSource source) async {
    if (_busy) return;
    final Uint8List? bytes;
    try {
      bytes = await _photoPicker.pick(source);
    } catch (e) {
      _toast('无法打开相机或相册: $e', error: true);
      return;
    }
    if (bytes == null || !mounted) return;
    await _setPhoto(bytes);
  }

  /// 预处理（后台 isolate）→ 落盘 → 已保存的卡片立即更新元数据。
  Future<void> _setPhoto(Uint8List raw) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyText = '正在处理照片...';
    });
    try {
      final processed = await compute(preprocessPhoto, raw);
      final path = await _storage.writeImage(_card.id, 'photo.jpg', processed);
      await FileImage(await _storage.imageFile(path)).evict();
      _card
        ..photoPath = path
        ..source = CharacterCardSource.photo;
      if (!_isNew) await _storage.saveCard(_card);
      if (mounted) setState(() => _photoBytes = processed);
    } on FormatException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('保存照片失败: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    final path = _card.photoPath;
    if (_busy || path == null) return;
    setState(() {
      _busy = true;
      _busyText = '正在移除照片...';
    });
    try {
      await _storage.deleteImage(path);
      await FileImage(await _storage.imageFile(path)).evict();
      _card
        ..photoPath = null
        ..source = CharacterCardSource.manual;
      if (!_isNew) await _storage.saveCard(_card);
      if (mounted) setState(() => _photoBytes = null);
    } catch (e) {
      _toast('移除照片失败: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recognize() async {
    final photo = _photoBytes;
    if (_busy || photo == null) return;
    setState(() {
      _busy = true;
      _busyText = '正在认识它...';
    });
    CharacterCardDraft? draft;
    try {
      final settings = await _loadSettings();
      if (!mounted) return;
      if (settings.llmApiKey.isEmpty) {
        _toast('⚠️ 请先在设置里填写 LLM API Key', error: true);
        return;
      }
      draft = await _engine.describeCharacterFromPhoto(
        settings: settings,
        photoBase64: base64Encode(photo),
        mimeType: 'image/jpeg',
      );
    } on FormatException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast(
        '识别失败: $e。如果当前文本模型不支持图片输入，请在设置里换成 Gemini、GPT-4o 等多模态模型。',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (draft == null || !mounted) return;
    await _applyDraft(draft);
  }

  /// 把识图结果填进表单；已有输入时让用户选择只补空白还是全部覆盖。
  Future<void> _applyDraft(CharacterCardDraft d) async {
    final fields = <TextEditingController, String>{
      _nameCtrl: d.name,
      _speciesCtrl: d.species,
      _appearanceCtrl: d.appearance,
      _outfitCtrl: d.defaultOutfit,
      _personalityCtrl: d.personality,
      _catchphraseCtrl: d.catchphrase,
    };
    var overwriteAll = true;
    if (fields.keys.any((c) => c.text.trim().isNotEmpty)) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('用识别结果填写表单？'),
          content: const Text('你已经填写了部分内容。可以只补空白项，也可以全部替换成识别结果。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'blank'),
              child: const Text('只填空白项'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: const Text('全部覆盖'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null || choice == 'cancel') return;
      overwriteAll = choice == 'all';
    }
    fields.forEach((ctrl, value) {
      if (overwriteAll || ctrl.text.trim().isEmpty) ctrl.text = value;
    });
    if (overwriteAll) setState(() => _kind = d.kind);
    _toast('已填入识别结果，请检查后保存');
  }
```

（e）`_generateAnchor`：前置检查对话框的 `content` 改为按是否有照片切换：

```dart
          content: Text(
            _photoBytes != null
                ? '定妆图只能按文字生成，照片不会被参考，后续绘本每页可能出现外貌不一致。'
                    '建议切换到 Gemini 图像模型（如 gemini-2.5-flash-image）或腾讯混元。'
                : '定妆图只能按文字生成，后续绘本每页可能出现外貌不一致。'
                    '建议切换到 Gemini 图像模型（如 gemini-2.5-flash-image）或腾讯混元。',
          ),
```

（原来的 `const Text(...)` 因此去掉 `const`。）`generateCharacterReference` 调用加：

```dart
        photoReferenceBase64:
            _photoBytes == null ? null : base64Encode(_photoBytes!),
```

（f）`build` 里 `if (_busy) ...[ … ],` 之后、`_sectionTitle('🧸 基本设定'),` 之前插入照片区：

```dart
              _sectionTitle('📷 照片（可选）'),
              if (_photoBytes != null) ...[
                Container(
                  height: 180,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Image.memory(
                    _photoBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, error, stack) => const Center(
                      child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_photoPicker.supportsCamera)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pickPhoto(PhotoSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('拍照'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickPhoto(PhotoSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('从相册选择'),
                  ),
                  if (_photoBytes != null)
                    TextButton.icon(
                      onPressed: _busy ? null : _removePhoto,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('移除照片'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: (_busy || _photoBytes == null) ? null : _recognize,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('让 AI 认识它'),
              ),
              const SizedBox(height: 24),
```

（g）页脚 `'修改角色卡只影响之后新建的绘本。'` 改为 `'照片只保存在本机；识别和生成定妆图时会各上传一次，故事页不会上传照片。修改角色卡只影响之后新建的绘本。'`。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/character_card_editor_photo_test.dart test/character_card_editor_screen_test.dart test/character_library_screen_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "character_card_editor" || echo "analyze: no lines for touched files"`

Expected: 9 + 7 + 5 条通过（新文件连续跑 3 次）；grep 无输出。P0 的编辑页测试必须仍然全部通过（照片区加在顶部，默认取图服务在测试环境里 `retrieveLost` 会安静地返回 null）。若照片流程的用例因 isolate / 文件 IO 时序失败，先确认 `until` 判定，再把 `maxRounds` 调大，不要删断言。

- [ ] **Step 5: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/screens/character_card_editor_screen.dart test/character_card_editor_photo_test.dart && git commit -m "feat(photo): take or pick a photo in the card editor, recognize it and use it for portraits

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 绘本流程传递照片、隐私断言、文案与文档、全量验证

**Files:**
- Modify: `lib/screens/create_book_screen.dart`（`_buildPinned`）
- Modify: `lib/screens/storyboard_review_screen.dart`（`_prepareCharacterReferences` + 新辅助 `_cardPhotoFor`）
- Modify: `lib/main.dart`（角色引导卡标题与副标题）、`lib/screens/character_library_screen.dart`（空状态提示）
- Modify: `README.md`、`AGENTS.md`
- Create: `test/photo_privacy_test.dart`
- Test: `test/storyboard_review_pinned_test.dart`、`test/create_book_screen_test.dart`、`test/widget_test.dart`、`test/character_library_screen_test.dart`

**Interfaces:**
- Consumes: `PinnedCharacter.photoBase64`（P1 已预留）、`generateCharacterReference(photoReferenceBase64:)`（Task 2）、审核页已有的 `_isCardCharacter` / `_lookMatchesCard`
- Produces: 创建页组装的 `PinnedCharacter` 带照片；审核页只在「卡片来源且书内外貌未改」时把照片交给定妆照生成

- [ ] **Step 1: 写失败的测试**

（a）创建 `test/photo_privacy_test.dart`：

```dart
import 'dart:convert';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Dio recordingDio(List<dynamic> sent, Map<String, dynamic> Function() responder) =>
    Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent.add(options.data);
            handler.resolve(Response(requestOptions: options, data: responder()));
          },
        ),
      );

void main() {
  test('故事分镜与故事页请求都不包含角色卡照片', () async {
    const photo = 'UEhPVE9fTUFSS0VS'; // base64("PHOTO_MARKER")
    final anchor = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
    final card = CharacterCard(
      id: 'card_dino1',
      name: '豆豆',
      kind: CharacterKind.animal,
      species: '毛绒恐龙',
      appearance: '绿色毛绒恐龙',
      photoPath: 'card_dino1/photo.jpg',
    );
    final storyboard = jsonEncode({
      'characters': [
        {
          'id': 'card_dino1',
          'name': '豆豆',
          'species': '毛绒恐龙',
          'isAnimal': true,
          'appearance': '绿色毛绒恐龙',
          'defaultOutfit': '',
        },
      ],
      'groups': {},
      'scenes': [
        {
          'text': '豆豆出门了。',
          'action': '豆豆走出家门',
          'emotion': '',
          'composition': '',
          'characterIds': ['card_dino1'],
          'outfitOverrides': {},
        },
      ],
    });

    final llmSent = <dynamic>[];
    final draft = await BookEngineService(
      dio: recordingDio(llmSent, () => {
            'choices': [
              {
                'message': {'content': storyboard},
              },
            ],
          }),
    ).createStoryboardDraft(
      settings: AppSettings(
        llmType: 'openai',
        llmBaseUrl: 'https://example.test',
        llmApiKey: 'k',
        llmModel: 'm',
      ),
      title: '豆豆的一天',
      storyText: '豆豆出门了。',
      pinnedCharacters: [PinnedCharacter(card: card, anchorBase64: anchor, photoBase64: photo)],
    );
    expect(jsonEncode(llmSent.single), isNot(contains(photo)));

    final imageSent = <dynamic>[];
    await BookEngineService(
      dio: recordingDio(imageSent, () => {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'inlineData': {'data': 'page'},
                    },
                  ],
                },
              },
            ],
          }),
    ).generateIllustration(
      settings: AppSettings(
        imageType: 'gemini',
        imageBaseUrl: 'https://example.test',
        imageModel: 'gemini-2.5-flash-image',
        imageApiKey: 'k',
      ),
      style: const BookStyle(id: 'watercolor', name: '水彩童话', desc: '', prefix: '水彩', negative: ''),
      page: draft.pages.single,
      characters: draft.characters,
    );
    final pageBody = jsonEncode(imageSent.single);
    expect(pageBody, isNot(contains(photo)));
    expect(pageBody, contains(anchor));
  });
}
```

（b）`test/storyboard_review_pinned_test.dart`：把 `fakeGeminiImageDio(String base64Png)` 改为 `fakeGeminiImageDio(String base64Png, [List<dynamic>? sent])`，在 `onRequest` 里 `sent?.add(options.data);`（现有调用不变）。在 `main()` 收尾 `}` 之前追加：

```dart
  testWidgets('卡片角色补画定妆照时附带卡片照片，书内改过外貌则不带', (tester) async {
    const photo = 'UEhPVE9fTUFSS0VS';
    final settings = AppSettings(
      imageType: 'gemini',
      imageApiKey: 'test-key',
      imageModel: 'gemini-2.5-flash-image',
    );

    final sent = <dynamic>[];
    await tester.runAsync(() => charStorage.saveCard(dino()));
    await pumpReview(
      tester,
      settings: settings,
      engine: BookEngineService(dio: fakeGeminiImageDio(pngBase64, sent)),
      pinnedCharacters: [PinnedCharacter(card: dino(), photoBase64: photo)],
    );
    await runIo(
      tester,
      () => tester.tap(find.byTooltip('重新生成定妆照')),
      until: () => find
          .text('定妆照已保存。请检查角色外貌和服装，确认后再开始绘制故事页。')
          .evaluate()
          .isNotEmpty,
      maxRounds: 120,
    );
    final withPhoto = jsonEncode(sent.single);
    expect(withPhoto, contains(photo));
    expect(withPhoto, contains('真实玩具或物件照片'));

    final editedSent = <dynamic>[];
    await pumpReview(
      tester,
      settings: settings,
      engine: BookEngineService(dio: fakeGeminiImageDio(pngBase64, editedSent)),
      initialCharacters: [dino().toBookCharacter()..appearance = '紫色毛绒恐龙'],
      pinnedCharacters: [PinnedCharacter(card: dino(), photoBase64: photo)],
    );
    await runIo(
      tester,
      () => tester.tap(find.byTooltip('重新生成定妆照')),
      until: () => find
          .text('定妆照已保存。请检查角色外貌和服装，确认后再开始绘制故事页。')
          .evaluate()
          .isNotEmpty,
      maxRounds: 120,
    );
    expect(jsonEncode(editedSent.single), isNot(contains(photo)));
  });
```

（第二次 `pumpReview` 会用新的 `MaterialApp` 替换第一次的界面树，两次互不影响；若第二次点击时第一次的 SnackBar 仍在导致 `until` 立即成立，在第二次 `pumpReview` 之前加 `await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();` 让 SnackBar 消失，并在报告里说明。）

（c）`test/create_book_screen_test.dart` 的用例「生成时把已选卡片的定妆图与 id 传给引擎和审核页」：把预置数据改为先写照片再存卡片再存定妆图，并追加断言：

```dart
    final photoBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 9, 9, 9, 9]);
    await tester.runAsync(() async {
      final c = card('card_a', '豆豆')
        ..photoPath = await storage.writeImage('card_a', 'photo.jpg', photoBytes);
      await storage.saveCard(c);
      await storage.saveAnchor('card_a', 'watercolor', png);
    });
```

（替换原来的 `saveCard(card('card_a', '豆豆'))` + `saveAnchor` 两行；文件顶部如缺 `import 'dart:typed_data';` 则补上。）在该用例末尾追加：

```dart
    expect(review.pinnedCharacters.single.photoBase64, base64Encode(photoBytes));
    expect(jsonEncode(sent.single), isNot(contains(base64Encode(photoBytes))));
```

（d）`test/widget_test.dart`：`expect(find.text('给孩子做一个专属主角'), findsOneWidget);` 改为 `expect(find.text('拍一张玩具，做一个专属主角'), findsOneWidget);`。

（e）`test/character_library_screen_test.dart` 的「没有卡片时显示空状态」用例追加 `expect(find.text('拍一张玩具照片或手动描述，都能创建角色'), findsOneWidget);`。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/photo_privacy_test.dart test/storyboard_review_pinned_test.dart test/create_book_screen_test.dart test/widget_test.dart test/character_library_screen_test.dart`

Expected: 隐私测试**通过**（结构上照片本来就不进这两类请求——它是回归保护）；审核页新用例、创建页 `photoBase64` 断言、首页标题、角色库提示失败。

- [ ] **Step 3: 实现**

`lib/screens/create_book_screen.dart` 的 `_buildPinned` 循环体改为：

```dart
      final path = card.anchorImagePaths[_selectedStyleId];
      final anchor =
          path == null ? null : await _characterStorage.readImageBase64(path);
      final photoPath = card.photoPath;
      final photo = photoPath == null
          ? null
          : await _characterStorage.readImageBase64(photoPath);
      pinned.add(
        PinnedCharacter(
          card: card,
          anchorBase64: (anchor == null || anchor.isEmpty) ? null : anchor,
          photoBase64: (photo == null || photo.isEmpty) ? null : photo,
        ),
      );
```

`lib/screens/storyboard_review_screen.dart`：在 `_lookMatchesCard` 之后加：

```dart
  /// 卡片来源且书内外貌未改动的角色，定妆照生成时附带卡片照片；其余返回 null。
  String? _cardPhotoFor(BookCharacter character) {
    if (!_isCardCharacter(character) || !_lookMatchesCard(character)) return null;
    for (final p in widget.pinnedCharacters) {
      if (p.card.id == character.id) return p.photoBase64;
    }
    return null;
  }
```

`_prepareCharacterReferences` 里的 `_engine.generateCharacterReference(...)` 调用加一行 `photoReferenceBase64: _cardPhotoFor(character),`。

`lib/main.dart` 角色引导卡：标题 `'给孩子做一个专属主角'` 改为 `'拍一张玩具，做一个专属主角'`；副标题 `'创建可复用的角色卡，之后每本绘本都能请他出场'` 改为 `'拍照或手动描述，创建可复用的角色卡，之后每本绘本都能请他出场'`。

`lib/screens/character_library_screen.dart` 的 `_buildEmpty`：在 `const Text('还没有角色', …)` 之后插入

```dart
            const SizedBox(height: 4),
            const Text(
              '拍一张玩具照片或手动描述，都能创建角色',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
```

`README.md`：
- 「**选卡写故事**」那条末尾删掉 `“拍玩具照片自动生成角色卡”将在后续版本推出。`
- 在「🧸 角色卡」小节的「**AI 帮孩子写故事**」那条之后加：

```
- **拍照生成角色卡**：在角色卡编辑页拍一张玩具、宠物或小物件（桌面端从相册选图），点「让 AI 认识它」自动填好名字、类型、外貌、性格和口头禅；生成定妆图时会参考这张照片，让画出来的角色更像真实的玩具。照片会压缩并去掉位置等元数据，只保存在本机，只在识别和生成定妆图时各上传一次，故事页不会上传照片。
```

- 「⚙️ 模型配置说明」列表里加一条：

```
- **照片识别**：「让 AI 认识它」使用当前文本模型，需要选择支持图片输入的模型（如 Gemini 2.5 Flash、GPT-4o、Claude）；DeepSeek 等纯文本模型会识别失败。
```

`AGENTS.md`：
- §2.1 在「故事助手：…」一行之后加：` │    ├── 拍照建卡：拍玩具 / 相册选图 → 压缩去 EXIF → 多模态识别填表，照片参与定妆图生成 (PhotoPickerService / describeCharacterFromPhoto)`
- §4 目录树 `services/` 下 `character_storage_service.dart` 之后加两行：

```
│   ├── photo_picker_service.dart      # 取图封装 (拍照/相册，Android 丢失照片找回)
│   ├── photo_preprocessor.dart        # 照片预处理 (摆正、长边 1024、清空 EXIF、JPEG 85)
```

- [ ] **Step 4: 运行相关测试确认通过**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter test test/photo_privacy_test.dart test/storyboard_review_pinned_test.dart test/create_book_screen_test.dart test/widget_test.dart test/character_library_screen_test.dart && $HOME/development/flutter/bin/flutter analyze 2>&1 | grep -E "create_book_screen|storyboard_review|character_library|photo_privacy" | grep -v "withOpacity\|activeColor" || echo "analyze: no new lines for touched files"`

Expected: 全部通过（审核页文件连续跑 3 次）；grep 只剩 `echo` 提示（审核页原有的弃用提示被过滤）。

- [ ] **Step 5: 全量验证**

Run: `cd ~/Code/Github/MyCode/bookbuddy_app && $HOME/development/flutter/bin/flutter analyze | tail -1 && $HOME/development/flutter/bin/flutter test`

Expected: analyze 总数与 `main` 一致（38 条，全为原有提示）；全部测试通过（P2 后 105 条 + 本期新增约 25 条）。若默认并发出现重试噪音，再跑 `--concurrency=1` 并以它为准。

- [ ] **Step 6: 提交**

```bash
cd ~/Code/Github/MyCode/bookbuddy_app && git add lib/screens/create_book_screen.dart lib/screens/storyboard_review_screen.dart lib/main.dart lib/screens/character_library_screen.dart README.md AGENTS.md test/photo_privacy_test.dart test/storyboard_review_pinned_test.dart test/create_book_screen_test.dart test/widget_test.dart test/character_library_screen_test.dart && git commit -m "feat(photo): carry card photos into portrait generation and keep them out of story requests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: 手动验收（用户执行，不在实施者范围内）**

按 spec §10 P3：Android 真机拍一张玩具照片，识别出可编辑的角色字段；生成的定妆图在颜色与外形上可辨识为该玩具；卡片目录中的照片为长边不超过 1024 的 JPEG；用这张卡做一本绘本，确认审核页补画定妆照正常、故事页正常。macOS 上从相册选图同样可用（首次需要授权文件访问）。

```bash
$HOME/development/flutter/bin/flutter run -d android
```

---

## 自检记录

**Spec 覆盖（P3 范围）**

| Spec 条目 | 任务 |
|---|---|
| 5.1 图片输入（三协议、无图保持原样） | Task 2 |
| 5.2 `describeCharacterFromPhoto` + §13 规则 9 | Task 2 |
| 5.3 照片参考 + 三分支说明切换 + 不支持参考图时忽略 | Task 2 |
| §13 规则 5（解析不抛，统一中文错误） | Task 2 |
| 6.3 第 1 条照片区（拍照仅手机、相册全平台、移除照片、预处理落盘） | Task 1（服务）、Task 3（页面） |
| 6.3 第 2 条识别按钮与覆盖确认 | Task 3 |
| 6.3 第 5 条前置检查文案含「照片不会被参考」 | Task 3 |
| 6.3 第 8 条页脚 | Task 3 |
| 6.5 卡片角色定妆照附带照片（结合 §13 规则 2） | Task 4 |
| 6.1 / 6.2 引导与空状态提及拍照 | Task 4 |
| 7 依赖、iOS 用途说明、macOS 文件权限、Android 丢失照片找回、预处理 + §13 规则 8 | Task 1、Task 3 |
| 8 隐私边界（照片只在识图与定妆图时上传） | Task 2（不支持参考图时不带照片）、Task 4（分镜与故事页不含照片） |
| 10 P3 验收 | Task 4 Step 7（用户） |

**类型一致性**：`PhotoPickerService.pick(PhotoSource) → Future<Uint8List?>`、`retrieveLost()`、`supportsCamera` 在 Task 1 定义，Task 3 的页面与测试假实现一致；`preprocessPhoto(Uint8List) → Uint8List` 交给 `compute`；`deleteImage(String)`；`describeCharacterFromPhoto({settings, photoBase64, mimeType}) → CharacterCardDraft`、`generateCharacterReference(..., photoReferenceBase64:)` 在 Task 2 定义，Task 3、Task 4 按同名参数调用；`PinnedCharacter(card:, anchorBase64:, photoBase64:)` 为 P1 既有签名。

**占位扫描**：无 TBD / TODO；每个代码步骤都有完整代码或精确的替换片段；两处第三方 API 不确定点（`image` 的 EXIF 标签写法、`LostDataResponse` 字段）给出了等价替代与报告要求。
