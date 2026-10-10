# .bb 绘本导出/导入功能设计

> 日期：2026-10-10
> 状态：已与用户确认
> 范围：为 BookBuddy 增加绘本专用格式 `.bb` 的导出与导入能力

## 需求

用户可将书架中的每本绘本导出为一份自定义格式文件（后缀 `.bb`），并可将 `.bb` 文件导回 App，实现跨设备迁移、备份与分享。

**用户已确认的两个决策：**

1. **完整作品打包**：`.bb` 内含文字、插画与每页朗读音频（mp3）。
2. **导入冲突存副本**：本地已存在同 id 绘本时，导入为「（导入）」副本，绝不覆盖现有数据。

## .bb 容器格式

采用 ZIP 容器（与 .epub / .docx 同一思路），而非单个大 JSON：音频以二进制存放（JSON+base64 会膨胀 33%）、结构可扩展、格式可自识别。

```
《小熊冒险》.bb  (ZIP)
├── mimetype              "application/x-bookbuddy-book"，STORED 不压缩，第一个条目
├── manifest.json         {"format":"bookbuddy-book","formatVersion":1,"exportedAt":"…","appVersion":"…"}
├── book.json             PictureBook.toJson() 原样（含插画 base64）
└── audio/
    ├── audio_p0.mp3      每页朗读音频，STORED 不压缩（mp3 已压缩，再 deflate 浪费 CPU）
    ├── audio_p1.mp3
    └── …
```

- `mimetype` 与 OCF（epub）惯例一致：STORED 且为第一个条目，用于快速自识别。
- `formatVersion` 当前为 1；导入时遇到更高版本明确报「请升级 App」，低版本向前兼容预留。

## 导入语义

- 本地无同 id 书 → 原样导入，**保留原 id 与标题**（换机恢复场景标题干净）。
- 本地有同 id 书 → 生成新 uuid，标题追加「（导入）」存副本，原书无损；同一文件重复导入亦为副本。
- 音频落盘到 `bookbuddy_audio/{最终id}/audio_p{i}.mp3`；阅读器 `getCachedAudioPath` 的兜底逻辑天然兼容，无需路径重写。
- 导入的书不回填角色卡关联（书内 `BookCharacter` 快照自包含，角色卡不随 .bb 迁移）。

## 校验链（任何一环失败给出人话错误，绝不写半截数据）

1. 文件大小上限 100MB（防 zip 炸弹）
2. zip 可解析
3. mimetype 匹配 `application/x-bookbuddy-book`
4. manifest 存在、format 标识正确、`formatVersion <= 1`
5. book.json 可解析且 `PictureBook.fromJson` 成功

## 代码架构

新增文件（不动现有架构）：

- `lib/services/book_exchange_service.dart` — 核心。纯 `dart:io` + `archive` 包；重活（十几 MB 编解码）放 `compute` 后台 isolate（与 `_writeBookFile` 同款待遇）；`BookStorageService` 与音频目录均可注入以便测试。
- `test/book_exchange_service_test.dart` — 见测试策略。

### 导出流程

书架卡片 trailing 加「导出」按钮（删除按钮旁）→ 系统保存对话框（`file_selector`，macOS 为 NSSavePanel）→ 写 `.bb`。导出前先读整本书（书架只有摘要）。同一时间只允许一个导出任务，防手抖并发。

### 导入流程

AppBar 加「导入」图标 → 系统打开文件对话框选 `.bb` → 校验链 → 落盘书 + 音频 → SnackBar 报结果。

## 平台兼容

| 平台 | 导出 | 导入 | 处理 |
|---|---|---|---|
| macOS / Windows / Linux | 系统保存对话框（`getSaveLocation`） | 系统打开对话框 | macOS entitlements 升级 `user-selected.read-write`；`.bb` 扩展名过滤可用 |
| Android / iOS | 分享面板（`share_plus`，`XFile` 携 `.bb` 文件名）：存到文件/发微信/AirDrop 等 | 系统打开对话框（SAF / UIDocumentPicker） | `file_selector` 的 `getSaveLocation` 在移动端未实现（默认抛 UnimplementedError），故导出走分享 |
| Web | 不支持 | 不支持 | `kIsWeb` 下隐藏入口 |

## 依赖新增

- `archive`（ZIP 读写）
- `file_selector`（flutter.dev 官方文件保存/打开对话框；移动端仅用其 openFile）
- `share_plus`（移动端导出分享）

## 测试策略

- 真实 zip round-trip，不 mock archive。
- 注入 `booksDirectory` 与音频目录（现有 `book_storage_service_test` 同款模式）。
- 覆盖：round-trip、含/不含音频、同 id 存副本、损坏 zip 拒绝、坏 manifest 拒绝、超大小上限拒绝、mimetype 不符拒绝。
- UI 层 widget test：按钮出现、点击走通到 service 被调用。
