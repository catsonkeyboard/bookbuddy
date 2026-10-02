# 📖 BookBuddy (绘本工坊)

> 一款基于大语言模型、图像生成模型与神经语音模型的跨平台儿童绘本创作与阅读客户端。
> 支持在 **macOS**、**Windows** 与 **Android 平板/手机** 上原生运行。

---

## ✨ 核心特性

### 🎨 创作：从一段故事到一本绘本
- **灵感与画风**：内置经典童话灵感库，可一键填入标题与梗概；提供水彩童话、3D 黏土定格、温馨彩铅、复古经典绘本、童趣蜡笔、日系动漫、国风水墨七种画风。
- **分镜镜头重构 (Scene Chunking)**：大模型将完整故事重构为 8~12 幕紧凑连贯的跨页镜头，严格“一页一图、图文对应”，同时产出全书角色档案（名字、物种、固定外貌、默认服装）与每页出场名单。
- **分镜审核页**：生图前可逐页修改正文、画面动作、神态与构图，开关单页插画，增删和编辑角色设定；引擎会先为每个出场角色绘制定妆照，用户确认外貌后再开始绘制故事页。
- **角色外貌跨页锁定**：每页生图时把本页出场角色的定妆照逐张作为参考图注入，配合固定外貌与服装约束，杜绝跨页“换脸”；仅在剧本明确换装时才通过换装覆盖改变服饰。
- **断点续画与逐页落盘**：每生成一页立即写入本地，断网、熄屏或强杀后重开即可从未完成的页面继续。

### 🧸 角色卡：可复用的专属主角（新）
- **独立角色库**：首页「我的角色」进入角色库，拍照或手动描述，创建属于孩子的固定主角：名字、类型（人类 / 动物 / 物件）、物种或物件名、外貌锚定描述、默认服装、性格、口头禅。
- **按画风生成并缓存定妆图**：同一张卡可为不同画风各生成一张定妆图，全部落盘保存，重启后仍在；修改外貌相关设定时会先确认再清空旧定妆图。
- **生图通道前置检查**：当前生图配置不支持参考图（如 Imagen 3、DALL-E 3）时会提前提示并引导切换，避免“不报错但每页换脸”。
- **编辑不回溯旧书**：角色卡的修改只影响之后新建的绘本，已生成的绘本保持原样。
- **选卡写故事**：新建绘本时可选最多 3 张角色卡作为固定主角，在自己写的故事里直接用名字称呼它们；分镜必须原样使用这些角色，生图沿用各自在所选画风下的定妆图；卡片缺这个画风的定妆图时，生成分镜前会询问是现在绘制并写回卡片，还是留到审核页再画；重绘卡片里已有的定妆图时，会先问是只用于本书还是同时更新角色卡。已有定妆图或角色设定时再次点生成、识别，都会先确认，避免误触重复调用模型。
- **AI 帮孩子写故事**：选好角色卡后点「让 AI 按角色写故事」，用一句话描述想讲的故事，AI 写出 400 到 700 字的儿童故事；可以直接修改文字，也可以提出建议让它在现有文本上重写，随时回到上一版；满意后一键回填创建页。
- **拍照生成角色卡**：在角色卡编辑页拍一张玩具、宠物或小物件（桌面端从相册选图），点「让 AI 认识它」自动填好名字、类型、外貌、性格和口头禅；生成定妆图时会参考这张照片，让画出来的角色更像真实的玩具。照片会压缩并去掉位置等元数据，只保存在本机，只在识别和生成定妆图（包括绘本审核页自动补画定妆照）时上传，故事分镜与故事页不会上传照片。

### 🎙️ 语音伴读
- **MiniMax 神经语音**：接入 MiniMax T2A v2，为儿童故事定制的温柔慢速人声（默认 0.85x），自然换气停顿。
- **按页本地缓存**：每页音频独立合成并落盘为 mp3，一次合成后翻页零延迟、离线可听。
- **智能连读**：当前页播完自动平滑翻页；支持单页重新合成并覆盖缓存。

### 📚 阅读与重绘
- **沉浸式翻页阅读**：大图画幅展示，配合朗读控制。
- **单页局部重绘**：查看并修改该页的原生生图提示词，一键定向重绘，不影响其他页面。
- **补画与全书重绘**：未完成或失败的插画可一键补画，也可整本重新生成；过程中保持屏幕常亮并逐页保存。
- **角色定妆照管理**：在阅读器内查看全书角色档案，重绘某个角色的定妆照。

### ⚙️ 模型接入与安全存储
- **多套配置随时切换**：文本模型与生图模型均支持保存多套配置（Profile）并一键切换激活。
- **文本模型 (LLM)**：Google Gemini 官方原生协议、OpenAI 兼容协议（GPT-4o、DeepSeek、自建网关）、Anthropic Claude 协议。
- **生图模型 (Image)**：Google Imagen 3、Gemini 多模态图像模型、智谱 GLM 生图、腾讯 TokenHub 混元 3.5、OpenAI DALL-E 3 及兼容网关。其中 Gemini 图像模型与混元 3.5 支持传入角色定妆照作为参考图。
- **双通道故障转移 (Failover)**：主生图通道遇 429 / 503 / 内容过滤时自动降级到备用通道；备用通道不支持参考图时会停止降级并明确提示，而不是悄悄丢掉角色一致性。
- **BYOK 与本地沙盒**：所有 API Key 只存于本地安全存储，不硬编码、不上传；绘本以独立 JSON 文件保存并带备份恢复，音频与角色库图片均为本地文件。

---

## 🚀 快速开始

### 环境要求
- **Flutter 3.47.5**（stable channel）
- **Dart 3.13.4**
- Android 打包需要 Android SDK 与 JDK 17

### 配置国内镜像（必须）
国内网络直连 `pub.dev` 极易超时，执行任何 Flutter 命令前先注入镜像环境变量。

macOS / Linux（可写入 `~/.zshrc` 或 `~/.bashrc`）：

```bash
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
export PATH="$HOME/development/flutter/bin:$PATH"
```

Windows PowerShell：

```powershell
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
```

### 获取依赖并运行

```bash
# 获取依赖
flutter pub get

# macOS 桌面端
flutter run -d macos

# Windows 桌面端
flutter run -d windows

# 已连接的 Android 平板 / 手机 / 模拟器
flutter run -d android
```

### 静态检查与测试

```bash
flutter analyze
flutter test
```

### 📱 Android APK 一键打包

脚本会自动配置国内镜像、清理终端与 Gradle 的代理设置、检测 Flutter 与 Android SDK，并编译 **ARM64** APK。

macOS / Linux / Git Bash（`build_apk.sh`）：

```bash
# Debug 版本（默认，完成后可直接安装到已连接设备）
./build_apk.sh

# Release 正式版本
./build_apk.sh release

# 静默模式（追加 -q）
./build_apk.sh -q
./build_apk.sh release -q
```

Windows PowerShell（`build_apk.ps1`）：

```powershell
# Debug 版本（默认）
.\build_apk.ps1

# Release 版本
.\build_apk.ps1 -Release

# 静默模式 / 只编译不安装
.\build_apk.ps1 -Release -Quiet -NoInstall
```

APK 输出路径：`build/app/outputs/flutter-apk/app-debug.apk` 或 `app-release.apk`。Windows 脚本默认在用户目录下查找 Flutter SDK、Android SDK 与 JDK 17，其他安装位置可通过 `PATH`、`ANDROID_HOME`、`JAVA_HOME` 指定。Release 版本用于正式发布前，请确认 Android 签名配置。

### 🖥️ 桌面端打包

```bash
flutter build macos --release
flutter build windows --release
```

---

## ⚙️ 模型配置说明

启动应用后，点击右上角齿轮图标进入 **「模型与接口配置」**，填入 API Key 即可开始创作：

- **文本模型 (LLM)**：在多套配置中选择并激活一套（Gemini / OpenAI 兼容 / DeepSeek / Claude），填写 Base URL、模型名与 Key。
- **生图模型 (Image)**：同样支持多套配置。若要使用角色卡定妆图和跨页角色一致性，请激活 **Gemini 多模态图像模型** 或 **腾讯混元 3.5**；Imagen 3 与 DALL-E 3 不接收参考图。
- **备用生图接口 (Failover)**：可选，主通道限流或被过滤时自动保底。
- **照片识别**：「让 AI 认识它」使用当前文本模型，需要选择支持图片输入的模型（如 Gemini 2.5 Flash、GPT-4o、Claude）；DeepSeek 等纯文本模型会识别失败。
- **语音伴读 (MiniMax)**：填写 MiniMax API Key 与 Group ID，选择音色（推荐 `audiobook_female_1` / `audiobook_female_2`）与语速。

---

## 📄 开源许可证

本项目基于 MIT License 开源。
