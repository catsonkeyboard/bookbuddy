import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';
import '../models/style_catalog.dart';
import '../models/fairy_tale_catalog.dart';
import '../services/book_engine_service.dart';
import '../services/book_storage_service.dart';
import '../services/settings_service.dart';
import 'book_reader_screen.dart';
import 'tale_recommendation_dialog.dart';

class CreateBookScreen extends StatefulWidget {
  final String? initialTitle;
  final String? initialSynopsis;
  final String? initialStyleId;

  const CreateBookScreen({
    super.key,
    this.initialTitle,
    this.initialSynopsis,
    this.initialStyleId,
  });

  @override
  State<CreateBookScreen> createState() => _CreateBookScreenState();
}

class _CreateBookScreenState extends State<CreateBookScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _textCtrl;
  late String _selectedStyleId;

  bool _isProcessing = false;
  String _statusText = '';

  final BookEngineService _engine = BookEngineService();
  final SettingsService _settingsService = SettingsService();
  final BookStorageService _storage = BookStorageService();

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle ?? '');
    _textCtrl = TextEditingController(text: widget.initialSynopsis ?? '');
    _selectedStyleId = widget.initialStyleId ?? 'watercolor';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _startGenerate() async {
    final title = _titleCtrl.text.trim();
    final text = _textCtrl.text.trim();

    if (title.isEmpty && text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入故事标题或故事正文')),
      );
      return;
    }

    final settings = await _settingsService.loadSettings();
    if (settings.llmApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 请先点击右上角设置图标，填写 LLM API Key！'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusText = '正在分析故事并重构绘本分镜镜头...';
    });

    try {
      final finalTitle = title.isNotEmpty ? title : (text.length > 20 ? text.substring(0, 20) : text);
      final pages = await _engine.createStoryboards(
        settings: settings,
        title: finalTitle,
        storyText: text.isNotEmpty ? text : finalTitle,
      );

      if (pages.isEmpty) {
        throw Exception('大模型未能成功生成绘本分镜，请重试');
      }

      final style = StyleCatalog.styles.firstWhere((s) => s.id == _selectedStyleId);
      String? protagonistRef;

      // 逐页绘制插画
      for (int i = 0; i < pages.length; i++) {
        setState(() {
          _statusText = '正在绘制插画：第 ${i + 1} / ${pages.length} 页 (${style.name})...';
        });

        if (settings.imageApiKey.isNotEmpty) {
          try {
            final b64 = await _engine.generateIllustration(
              settings: settings,
              style: style,
              page: pages[i],
              referenceImageBase64: protagonistRef,
            );
            pages[i].imageBase64 = b64;
            // 锁定第一页成功生成的角色图作为全书的主角参考基准图
            if (protagonistRef == null && b64 != null && b64.isNotEmpty) {
              protagonistRef = b64;
            }
          } catch (e) {
            pages[i].isPlaceholder = true;
          }
        } else {
          pages[i].isPlaceholder = true;
        }
      }

      final newBook = PictureBook(
        id: const Uuid().v4().substring(0, 10),
        title: finalTitle,
        styleId: style.id,
        styleName: style.name,
        pages: pages,
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
          SnackBar(content: Text('生成失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('✨ 新建绘本作品'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD8A24A),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            icon: const Text('🌟', style: TextStyle(fontSize: 16)),
            label: const Text('挑选经典童话', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (_) => const TaleRecommendationDialog(),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: _isProcessing
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      Text(_statusText, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('正在全自动跨平台绘制中，完成后将自动进入阅读器', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: '故事标题（如：小红帽的故事、三只小猪）',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _textCtrl,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: '故事正文（可直接粘贴文本；若留空仅填书名，AI 将自动续写完整童话）',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('🎨 选择绘本画风', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: StyleCatalog.styles.map((st) {
                        final isSel = st.id == _selectedStyleId;
                        return ChoiceChip(
                          label: Text(st.name),
                          selected: isSel,
                          onSelected: (_) => setState(() => _selectedStyleId = st.id),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 36),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _startGenerate,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('🎬 开始全自动制作绘本', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
