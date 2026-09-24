import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/app_settings.dart';
import '../models/book.dart';
import '../services/book_engine_service.dart';
import '../services/book_storage_service.dart';
import 'book_reader_screen.dart';

class StoryboardReviewScreen extends StatefulWidget {
  final String title;
  final BookStyle style;
  final List<BookPageItem> initialPages;
  final AppSettings settings;

  const StoryboardReviewScreen({
    super.key,
    required this.title,
    required this.style,
    required this.initialPages,
    required this.settings,
  });

  @override
  State<StoryboardReviewScreen> createState() => _StoryboardReviewScreenState();
}

class _StoryboardReviewScreenState extends State<StoryboardReviewScreen> {
  late List<BookPageItem> _pages;
  bool _isGenerating = false;
  String _progressText = '';
  double _progressValue = 0.0;

  final BookEngineService _engine = BookEngineService();
  final BookStorageService _storage = BookStorageService();

  @override
  void initState() {
    super.initState();
    // 深拷贝以允许在界面编辑
    _pages = widget.initialPages
        .map((p) => BookPageItem.fromJson(p.toJson()))
        .toList();
  }

  void _editPage(int index) {
    final page = _pages[index];
    final textCtrl = TextEditingController(text: page.text);
    final actionCtrl = TextEditingController(text: page.sceneAction);
    final emotionCtrl = TextEditingController(text: page.sceneEmotion);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('✏️ 编辑第 ${index + 1} 幕 / 页'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📖 本页故事正文（朗读与阅读展示内容）：',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: textCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '输入本页绘本文字...',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '🎬 画面视觉动作（用于指导 AI 绘制插画）：',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: actionCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '如：小红帽站在门前台阶上挥手告别...',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '😊 角色神态与微表情：',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: emotionCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '如：小红帽笑容灿烂，大灰狼眼神狡黠坏笑...',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD8A24A),
              foregroundColor: Colors.black87,
            ),
            onPressed: () {
              setState(() {
                page.text = textCtrl.text.trim();
                page.sceneAction = actionCtrl.text.trim();
                page.sceneEmotion = emotionCtrl.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('保存修改', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _batchToggle(bool enable) {
    setState(() {
      for (var p in _pages) {
        p.needIllustration = enable;
      }
    });
  }

  Future<void> _startDrawIllustrations() async {
    final activeCount = _pages.where((p) => p.needIllustration).length;
    if (activeCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要开启 1 张插画生成')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _progressText = '准备开始绘制全书插画...';
      _progressValue = 0.0;
    });

    try {
      String? protagonistRef;
      int doneCount = 0;

      for (int i = 0; i < _pages.length; i++) {
        final page = _pages[i];
        if (!page.needIllustration) {
          page.isPlaceholder = true;
          continue;
        }

        doneCount++;
        setState(() {
          _progressText = '正在绘制插画：第 ${i + 1} / ${_pages.length} 页 (${widget.style.name})...\n已完成 $doneCount / $activeCount';
          _progressValue = doneCount / activeCount;
        });

        if (widget.settings.imageApiKey.isNotEmpty) {
          try {
            final b64 = await _engine.generateIllustration(
              settings: widget.settings,
              style: widget.style,
              page: page,
              referenceImageBase64: protagonistRef,
            );
            page.imageBase64 = b64;
            page.generationError = null;
            // 锁定第一页成功生成的角色图作为全书的主角参考基准图
            if (protagonistRef == null && b64 != null && b64.isNotEmpty) {
              protagonistRef = b64;
            }
          } catch (e) {
            page.isPlaceholder = true;
            page.generationError = e.toString();
          }
        } else {
          page.isPlaceholder = true;
          page.generationError = '未配置生图 API Key';
        }
      }

      final newBook = PictureBook(
        id: const Uuid().v4().substring(0, 10),
        title: widget.title,
        styleId: widget.style.id,
        styleName: widget.style.name,
        pages: _pages,
        createdAt: DateTime.now(),
        protagonistRefImage: protagonistRef,
      );

      await _storage.saveBook(newBook);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => BookReaderScreen(book: newBook)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成插画失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _pages.where((p) => p.needIllustration).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('🎬 分镜审核 · ${widget.title}'),
        actions: [
          if (!_isGenerating) ...[
            TextButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('全部开启'),
              onPressed: () => _batchToggle(true),
            ),
            TextButton.icon(
              icon: const Icon(Icons.highlight_off, size: 16),
              label: const Text('全部关闭'),
              onPressed: () => _batchToggle(false),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: _isGenerating
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 24),
                        Text(
                          _progressText,
                          style: const TextStyle(fontSize: 16, height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: _progressValue,
                          backgroundColor: Colors.white12,
                          color: const Color(0xFFD8A24A),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // 顶部提示条
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      color: const Color(0xFF23201B),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFFD8A24A), size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'AI 已重构出 ${_pages.length} 幕镜头（当前计划绘制 $activeCount 幅插画 · ${widget.style.name}）。'
                              '你可以点击卡片自由编辑故事正文、视觉动作与微表情，确认无误后点击下方开始配图。',
                              style: const TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 分镜列表
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _pages.length,
                        itemBuilder: (ctx, i) {
                          final page = _pages[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: page.needIllustration
                                    ? const Color(0xFFD8A24A).withOpacity(0.4)
                                    : Colors.white10,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 序号与状态
                                  Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: page.needIllustration
                                          ? const Color(0xFFD8A24A).withOpacity(0.15)
                                          : Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '第${i + 1}幕',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: page.needIllustration
                                                ? const Color(0xFFD8A24A)
                                                : Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          '第${i + 1}页',
                                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // 内容区
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 绘本正文
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.black26,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('📖 ', style: TextStyle(fontSize: 14)),
                                              Expanded(
                                                child: Text(
                                                  page.text,
                                                  style: const TextStyle(fontSize: 14, height: 1.5),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // 画面动作
                                        if (page.sceneAction.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 4),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('🎬 画面动作：', style: TextStyle(fontSize: 12, color: Color(0xFFD8A24A))),
                                                Expanded(
                                                  child: Text(
                                                    page.sceneAction,
                                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        // 神态微表情
                                        if (page.sceneEmotion.isNotEmpty)
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('😊 神态微表情：', style: TextStyle(fontSize: 12, color: Color(0xFFD8A24A))),
                                              Expanded(
                                                child: Text(
                                                  page.sceneEmotion,
                                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // 操作区：编辑按钮 + 开关
                                  Column(
                                    children: [
                                      IconButton(
                                        tooltip: '编辑正文与画面描述',
                                        icon: const Icon(Icons.edit_outlined, size: 20),
                                        onPressed: () => _editPage(i),
                                      ),
                                      Switch(
                                        value: page.needIllustration,
                                        activeColor: const Color(0xFFD8A24A),
                                        onChanged: (val) {
                                          setState(() => page.needIllustration = val);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // 底部操作栏
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E1C18),
                        border: Border(top: BorderSide(color: Colors.white10)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '共 ${_pages.length} 幕 / 已开启 $activeCount 幅插画',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD8A24A),
                              foregroundColor: Colors.black87,
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.palette),
                            label: Text(
                              '✅ 确认分镜，开始绘制 ($activeCount 张)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            onPressed: _startDrawIllustrations,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
