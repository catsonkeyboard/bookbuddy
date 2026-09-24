# 🤖 AGENTS.md — BookBuddy 开发者与智能体开发指南

> 本文档面向协同开发人员与接手本项目的 AI Agent，详细记录了本项目的**本地开发环境配置、工程约束、核心业务架构、各功能模块实现及最佳实践**。后续 Agent 接手维护或拓展功能时，请严格遵守本规范。

---

## 🛠️ 1. 本地开发环境规范 (Development Environment)

### 1.1 基础环境与 SDK 路径
* **操作系统**：macOS (Darwin arm64)
* **Shell**：`/bin/zsh`
* **Flutter SDK 绝对路径**：`$HOME/development/flutter/bin/flutter`
* **Flutter 版本**：`Flutter 3.47.5 • channel stable`
* **Dart SDK 版本**：`Dart 3.13.4 • DevTools 2.60.0`

### 1.2 环境变量要求 (必须配置国内镜像)
由于国内网络环境直连官方 `pub.dev` 极易出现握手超时或网络挂起，执行任何 Flutter 命令前**必须确保注入以下环境变量**：

```bash
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
export PATH="$HOME/development/flutter/bin:$PATH"
```

### 1.3 常用工程命令
* **拉取依赖**：
  ```bash
  export PUB_HOSTED_URL="https://pub.flutter-io.cn" && export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn" && $HOME/development/flutter/bin/flutter pub get
  ```
* **静态代码分析**：
  ```bash
  $HOME/development/flutter/bin/flutter analyze
  ```
* **运行单元测试**：
  ```bash
  $HOME/development/flutter/bin/flutter test
  ```
* **本地调试运行**：
  ```bash
  # macOS 桌面端直接运行
  $HOME/development/flutter/bin/flutter run -d macos
  # Android 模拟器/真机
  $HOME/development/flutter/bin/flutter run -d android
  ```
* **一键打包 Android APK**：
  ```bash
  ./build_apk.sh           # Debug 版本
  ./build_apk.sh release   # Release 正式版本
  ```

### 1.4 Agent 执行命令注意事项
* **后台进程防滞留**：如果执行 `flutter pub get` 超时或被取消，Dart 可能会在后台残留孤儿进程 (`dartvm ... pub get`) 持续占用 CPU 和端口。排查与清理指令：
  ```bash
  pgrep -fl "flutter|dart"
  kill -9 <PID>
  ```

---

## 📖 2. 项目功能与核心业务架构 (Features & Architecture)

**BookBuddy (绘本工坊)** 是一套基于大语言模型 (LLM)、生图模型 (Diffusion/Autoregressive) 与神经拟人语音大模型 (MiniMax TTS) 深度整合的跨平台儿童绘本创作与阅读客户端。

### 2.1 功能模块全景

```
BookBuddy (绘本工坊)
 ├── 🎨 创作阶段 (Creation Pipeline)
 │    ├── 灵感推荐：精选世界经典童话、主题寓意与角色设定 (FairyTaleCatalog)
 │    ├── 风格选择：水彩、3D皮克斯、日系动漫、复古绘本等艺术画风 (StyleCatalog)
 │    ├── 分镜创作：LLM 镜头重构算法，将故事提炼为 8~12 幕分镜剧本 (BookEngineService)
 │    ├── 剧本审核：支持分镜文字修改、提示词微调、插画开关 (StoryboardReviewScreen)
 │    ├── 主角定妆：首幕生成基准参考图 (protagonistRefImage)，锁定角色外貌防漂移
 │    └── 插画生成：多模态并发生图，支持通道故障转移 (Failover)
 ├── 🎙️ 语音阶段 (Neural TTS Engine)
 │    ├── MiniMax T2A v2 接入：专为儿童故事定制的睡前温柔人声 (TtsService)
 │    ├── 慢速呼吸感调优：默认 0.85x 慢速，自然换气停顿与微表情
 │    ├── 本地持久化缓存：按页独立落盘存储 (`audio_p{pageIndex}.mp3`)，一次合成终身免流
 │    └── 智能连读机制：支持当前页播完自动平滑翻页 (Auto-Flip Continuation)
 ├── 📚 阅读阶段 (Reader & Regeneration)
 │    ├── 跨页绘本翻页阅读：大图沉浸式画幅展示 (BookReaderScreen)
 │    ├── 局部插画重绘：单页独立提示词提取、自由修改并重新生成插画
 │    └── 局部音频重录：单页声音单独重新合成并覆盖本地缓存
 └── ⚙️ 系统设置与存储 (Settings & Storage)
      ├── 多厂商 LLM 支持：Google Gemini、OpenAI 兼容规范、Anthropic Claude
      ├── 双通道生图路由：主通道 (Imagen 3 / DALL-E 3) + 备用降级通道
      └── 安全本地存储：BYOK 本地沙盒持久化，不硬编码任何凭据
```

---

## 🧩 3. 核心功能设计细节与关键代码

### 3.1 神经语音伴读与本地沙盒持久化 (`lib/services/tts_service.dart`)
* **痛点**：系统原生 TTS 机械冰冷；若每次翻页都请求云端接口不仅费用高昂且延迟明显，离线不可用。
* **架构设计**：
  1. **按页解耦**：以每页为最小合成单位，避免生成超大单体音频。
  2. **沙盒落盘**：音频保存在 `appDir/bookbuddy_audio/{bookId}/audio_p{pageIndex}.mp3`。
  3. **模型绑定**：`BookPageItem` 保存 `audioPath`，随绘本数据序列化存入 `SharedPreferences`。
  4. **缓存优先 (Cache-Hit)**：翻页触发播放时，先检查 `hasCachedAudio()`。存在即 0 延迟秒播，无需消耗网络与 API Token。
* **MiniMax 接口规范**：
  * URL: `https://api.minimax.chat/v1/t2a_v2?GroupId={groupId}`
  * 编码兼容：自适应处理服务端返回的 Hex 十六进制编码及 Base64 编码。
  * 推荐音色：`audiobook_female_1` (治愈暖心姐姐)、`audiobook_female_2` (温柔小姨/故事妈妈)。

### 3.2 分镜剧本叙事镜头重构 (`lib/services/book_engine_service.dart`)
* 采用 **Scene Chunking** 分镜重构算法，规避长文本直接生硬切片的缺陷。
* 明确输出约束：8~12 幕紧凑连贯的跨页镜头，输出格式严格保证为包含 `text`, `sceneAction`, `sceneEmotion`, `prompt` 的结构化数据。
* 拟人化约束：强制童话动物角色双足站立、服装锁定并带有生动的人类心理微表情。

### 3.3 主角定妆照与角色一致性锁定 (`protagonistRefImage`)
* 绘本生成第一页时，将首张成功的插画 Base64 提取并存储在 `PictureBook.protagonistRefImage`。
* 后续所有页面及单独页面的局部重绘，都会将该基准参考图随提示词一并传入多模态生图接口，防止出现跨页“换脸”或角色风格漂移。

### 3.4 生图通道故障转移 (Failover Strategy)
* 主生图接口配置在 `AppSettings.imageType` (如 Gemini Imagen 3)。
* 备用生图接口配置在 `AppSettings.fallbackImageType` (如 OpenAI DALL-E 3)。
* 当主生图遇到 `429 Too Many Requests`、`503 Service Unavailable` 或触发特定过滤规则时，引擎会自动降级并无缝重试备用通道。

---

## 📂 4. 目录结构与关键文件指引

```
lib/
├── main.dart                          # 应用主入口，主题配置，首页绘本网格展示
├── models/
│   ├── app_settings.dart              # 全局配置模型 (LLM/Image/Fallback/MiniMax TTS)
│   ├── book.dart                      # 绘本模型 (PictureBook, BookPageItem 包含 audioPath)
│   ├── fairy_tale_catalog.dart        # 内置经典童话灵感库
│   └── style_catalog.dart             # 艺术风格预设库 (水彩、皮克斯等)
├── services/
│   ├── book_engine_service.dart       # 分镜大模型与跨接口生图核心引擎
│   ├── book_storage_service.dart      # 绘本本地持久化存取服务
│   ├── settings_service.dart          # 本地加密/持久化配置管理服务
│   └── tts_service.dart               # MiniMax 语音生成、解码与沙盒缓存管理服务
└── screens/
    ├── create_book_screen.dart        # 绘本创作向导页 (故事输入/童话挑选/风格选择)
    ├── storyboard_review_screen.dart  # 分镜大纲预览、修改与批量生图控制页
    ├── book_reader_screen.dart        # 绘本翻页阅读器、单页朗读控制、单页插画重绘页
    ├── settings_screen.dart           # 模型接口、密钥及 TTS 伴读配置中心
    └── tale_recommendation_dialog.dart# 经典童话灵感弹窗
```

---

## ⚠️ 5. 后续 Agent 维护与拓展守则

1. **修改数据模型时必须保持对称序列化**：
   * 在 `BookPageItem` 或 `AppSettings` 增删字段时，务必同步更新构造函数、`toJson()` 和 `fromJson()`，并更新对应单元测试。
2. **所有文件操作遵循离线与沙盒隔离原则**：
   * 生成的插画或音频切勿仅保存在内存中，生成完毕需落盘并通过 `_storage.saveBook()` 及时固化，保证 App 重启后立即可用。
3. **不得硬编码任何个人 API Key 或 Token**：
   * 所有密钥统一在 `AppSettings` 中动态配置并本地安全存储。
4. **运行测试与检查**：
   * 任何改动完成后，务必执行 `$HOME/development/flutter/bin/flutter analyze` 与 `$HOME/development/flutter/bin/flutter test` 确认无回归问题。
