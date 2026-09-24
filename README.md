# 📖 BookBuddy (绘本工坊)

> 一款基于 AI 大语言模型与图像生成模型的跨平台沉浸式儿童绘本创作客户端。
> 支持在 **macOS**、**Windows** 与 **Android 平板/手机** 上原生运行。

---

## 🖼️ 应用预览

<div align="center">
  <img src="assets/images/preview.png" alt="BookBuddy 客户端界面" width="800" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.3);" />
</div>

---

## ✨ 核心特性

- **多平台原生支持**：基于 Flutter 3 架构，一套代码覆盖 macOS、Windows、Android 平板、iOS 与 Web。
- **绘本场景镜头重构 (Scene Chunking)**：基于资深分镜叙事算法，告别自然段琐碎切割，将完整童话重构为 8~12 幕紧凑连贯的跨页镜头，实现严格的**“一页一图、图文对应”**。
- **生动的拟人化与人类微表情**：针对童话动物角色锁定双足站立体态与狡黠、坏笑、纯真等丰富人类心理微表情，避免写实动物违和感。
- **全书角色外貌多模态锚定**：首幕自动锁定主角面部容貌、发型、体型，换装脱衣等情节动态服从场景，彻底杜绝角色漂移与三视图设定稿泄露。
- **支持单页局部重绘**：在阅读器内浏览时，支持展示原生生图提示词并可任意修改细节或清空重写，一键单独定向重绘。
- **多接口协议与多通道故障转移 (Failover)**：
  - 支持 **Google Gemini / Imagen 3 官方原生协议**
  - 支持 **OpenAI 兼容协议 (智谱 / DeepSeek / 自建网关)**
  - 支持 **Anthropic Claude 协议**
  - 支持主生图接口遇 429/503/限流时自动无缝降级到备用通道。
- **BYOK 隐私与安全性**：所有 API Key 均在本地安全沙箱存储，不硬编码、不上传外部服务器。

---

## 🚀 快速开始

### 依赖环境
- Flutter SDK >= 3.13.0
- Dart SDK >= 3.1.0

### 运行应用

```bash
# 获取依赖
flutter pub get

# 在 macOS 原生桌面端运行
flutter run -d macos

# 在已连接的 Android 平板或模拟器运行
flutter run -d android
```

### 📱 Android APK 一键打包

项目根目录下提供了自动化打包脚本 `build_apk.sh`：

```bash
# 1. 默认一键打包 Debug APK (适合日常测试，完成后提示直接安装)
./build_apk.sh

# 2. 一键打包 Release 正式版 APK (体积更小，运行更流畅)
./build_apk.sh release
```

---

## ⚙️ 模型配置说明

启动应用后，点击右上角齿轮图标进入 **「模型与接口配置」** 中心，填入你的 API Key 即可开始创作：
- **文本模型 (LLM)**：可选用 Google Gemini 官方原生、OpenAI 兼容或 Claude。
- **生图模型 (Image)**：推荐使用 Google Imagen 3 或兼容生图模型。
- **备用生图接口 (Failover)**：可选配置备用模型，遇额度受限时自动保底。

---

## 📄 开源许可证

本项目基于 MIT License 开源。
