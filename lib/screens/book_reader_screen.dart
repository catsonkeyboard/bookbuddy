import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../models/book.dart';
import '../models/style_catalog.dart';
import '../services/book_engine_service.dart';
import '../services/book_storage_service.dart';
import '../services/settings_service.dart';

class BookReaderScreen extends StatefulWidget {
  final PictureBook book;
  const BookReaderScreen({super.key, required this.book});

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  late PictureBook _book;
  late PageController _pageController;
  int _currentPage = 0;
  bool _isRegenerating = false;

  final BookEngineService _engine = BookEngineService();
  final BookStorageService _storage = BookStorageService();
  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openRegenDialog() {
    final curItem = _book.pages[_currentPage];
    final style = StyleCatalog.styles.firstWhere(
      (s) => s.id == _book.styleId,
      orElse: () => StyleCatalog.styles.first,
    );

    // 默认展示原生图提示词（如果有记录则用已保存的，否则按公式实时组装）
    final initialPrompt = curItem.rawPrompt != null && curItem.rawPrompt!.isNotEmpty
        ? curItem.rawPrompt!
        : _engine.buildDefaultPrompt(style: style, page: curItem);

    final promptCtrl = TextEditingController(text: initialPrompt);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('🎨 修改并重绘第 ${_currentPage + 1} 页插画'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 当前故事文本卡片
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.menu_book, size: 16, color: Color(0xFFD8A24A)),
                          SizedBox(width: 6),
                          Text('📖 当前页故事文本：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        curItem.text,
                        style: const TextStyle(fontSize: 14, height: 1.6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 2. 原生图提示词（支持微调或清空重写）
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🖼️ 生图提示词 (Prompt)：',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('清空重写', style: TextStyle(fontSize: 12)),
                      onPressed: () => promptCtrl.clear(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: promptCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: '可直接在此修改细节（如动作、站姿、神态、光影），也可以清空全部重写新的生图提示词...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '💡 说明：支持直接在上方修改提示词细节，也可以全部删掉重新编写；点击重绘将直接使用上述提示词进行生成。',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
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
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD8A24A),
              foregroundColor: Colors.black87,
            ),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('🚀 立即重新生图', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              _doRegen(promptCtrl.text.trim());
            },
          ),
        ],
      ),
    );
  }

  Future<void> _doRegen(String fullPromptOverride) async {
    setState(() => _isRegenerating = true);
    try {
      final settings = await _settingsService.loadSettings();
      final style = StyleCatalog.styles.firstWhere(
        (s) => s.id == _book.styleId,
        orElse: () => StyleCatalog.styles.first,
      );

      final page = _book.pages[_currentPage];
      final newB64 = await _engine.generateIllustration(
        settings: settings,
        style: style,
        page: page,
        fullPromptOverride: fullPromptOverride,
        referenceImageBase64: _book.protagonistRefImage, // 注入全书统一主角定妆照锁定外貌
      );

      if (newB64 != null) {
        page.imageBase64 = newB64;
        // 如果全书此前还没有基准主角图，将本次成功生成的图存为基准
        _book.protagonistRefImage ??= newB64;
        await _storage.saveBook(_book);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('🎉 第 ${_currentPage + 1} 页插画已重新生成！')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重绘失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isRegenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _book.pages.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('📖 ${_book.title}'),
        actions: [
          IconButton(
            tooltip: '修改说明并重绘当前页插画',
            icon: const Icon(Icons.brush),
            onPressed: _isRegenerating ? null : _openRegenDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: total,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final page = _book.pages[index];
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 5,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: page.imageBase64 != null
                                  ? Image.memory(
                                      base64Decode(page.imageBase64!),
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: Colors.black26,
                                      padding: const EdgeInsets.all(20),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.broken_image_outlined, size: 48, color: Colors.orangeAccent),
                                            const SizedBox(height: 12),
                                            const Text('⚠️ 插画未成功生成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                            const SizedBox(height: 6),
                                            Text(
                                              page.generationError != null
                                                  ? '原因: ${page.generationError}'
                                                  : '可能是上游网络抖动或触发了安全内容拦截',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 16),
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.refresh, size: 16),
                                              label: const Text('点击重新绘制本页'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFFD8A24A),
                                                foregroundColor: Colors.black87,
                                              ),
                                              onPressed: _openRegenDialog,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            flex: 2,
                            child: SingleChildScrollView(
                              child: Text(
                                page.text,
                                style: const TextStyle(fontSize: 18, height: 1.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (_isRegenerating)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在重绘当前页插画，请稍候...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton.icon(
              onPressed: _currentPage > 0
                  ? () => _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      )
                  : null,
              icon: const Icon(Icons.arrow_back),
              label: const Text('上一页'),
            ),
            Text(
              '第 ${_currentPage + 1} 页 / 共 $total 页',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            ElevatedButton.icon(
              onPressed: _currentPage < total - 1
                  ? () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      )
                  : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('下一页'),
            ),
          ],
        ),
      ),
    );
  }
}
