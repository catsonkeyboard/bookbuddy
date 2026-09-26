import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/book.dart';
import '../models/app_settings.dart';
import '../models/style_catalog.dart';
import '../services/book_engine_service.dart';
import '../services/book_storage_service.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';

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
  bool _isBatchDrawing = false;
  String _batchProgressText = '';
  double _batchProgressValue = 0.0;

  // TTS 与音频播放相关状态
  final BookEngineService _engine = BookEngineService();
  final BookStorageService _storage = BookStorageService();
  final SettingsService _settingsService = SettingsService();
  final TtsService _ttsService = TtsService();

  final AudioPlayer _audioPlayer = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  bool _isAudioSynthesizing = false;
  bool _autoPlayNext = false; // 是否朗读完自动翻下一页

  bool get _isPlaying => _playerState == PlayerState.playing;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _pageController = PageController();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _playerState = state);
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() => _playerState = PlayerState.completed);
        _handleAudioCompleted();
      }
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// 朗读完成事件处理（支持翻页连读）
  void _handleAudioCompleted() {
    if (_autoPlayNext && _currentPage < _book.pages.length - 1) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _pageController.nextPage(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  /// 播放或暂停当前页朗读（优先使用本地已缓存音频，未生成则请求 MiniMax 并保存）
  Future<void> _togglePlayCurrentPage({bool forceRegen = false}) async {
    // 如果正在播放且未要求强制重成，点击直接暂停
    if (_isPlaying && !forceRegen) {
      await _audioPlayer.pause();
      return;
    }

    // 如果处于暂停状态，恢复播放
    if (_playerState == PlayerState.paused && !forceRegen) {
      await _audioPlayer.resume();
      return;
    }

    final curPage = _book.pages[_currentPage];

    // 检查本地是否已有音频文件
    final hasCache = await _ttsService.hasCachedAudio(
      bookId: _book.id,
      pageIndex: _currentPage,
      knownPath: curPage.audioPath,
    );

    if (hasCache && !forceRegen) {
      final audioPath =
          curPage.audioPath ??
          await _ttsService.getLocalAudioPath(
            bookId: _book.id,
            pageIndex: _currentPage,
          );
      curPage.audioPath = audioPath;
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(audioPath));
      return;
    }

    // 本地未缓存或要求强制重新生成，调用 MiniMax 接口合成
    final settings = await _settingsService.loadSettings();
    if (!settings.ttsEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('⚠️ 语音朗读功能未开启，请先在设置中启用')));
      }
      return;
    }

    if (settings.minimaxApiKey.trim().isEmpty ||
        settings.minimaxGroupId.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ 请先前往【设置 -> 绘本语音朗读】配置 MiniMax API Key 与 Group ID'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isAudioSynthesizing = true);
    try {
      final savedAudioPath = await _ttsService.synthesizePageAudio(
        bookId: _book.id,
        pageIndex: _currentPage,
        text: curPage.text,
        settings: settings,
        forceRefresh: forceRegen,
      );

      curPage.audioPath = savedAudioPath;
      curPage.audioError = null;

      // 持久化保存到绘本数据中，下次打开即用
      await _storage.saveBook(_book);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              forceRegen
                  ? '🎉 第 ${_currentPage + 1} 页语音已重新生成并已永久保存在本地！'
                  : '🎉 第 ${_currentPage + 1} 页语音生成完毕，已永久保存在本地！',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(savedAudioPath));
      }
    } catch (e) {
      curPage.audioError = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('语音生成失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAudioSynthesizing = false);
      }
    }
  }

  void _openRegenDialog() {
    final curItem = _book.pages[_currentPage];
    final style = StyleCatalog.styles.firstWhere(
      (s) => s.id == _book.styleId,
      orElse: () => StyleCatalog.styles.first,
    );

    // 默认展示原生图提示词（如果有记录则用已保存的，否则按公式实时组装）
    final initialPrompt =
        curItem.rawPrompt != null && curItem.rawPrompt!.isNotEmpty
        ? curItem.rawPrompt!
        : _engine.buildDefaultPrompt(style: style, page: curItem);

    final promptCtrl = TextEditingController(text: initialPrompt);
    final compositionCtrl = TextEditingController(
      text: curItem.sceneComposition,
    );

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
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline
                          .withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.menu_book,
                            size: 16,
                            color: Color(0xFFD8A24A),
                          ),
                          SizedBox(width: 6),
                          Text(
                            '📖 当前页故事文本：',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                const Text(
                  '🧭 动作朝向与空间关系：',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: compositionCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: '如：大灰狼侧身面向草屋吹气，草屋在狼前方，侧面镜头',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. 原生图提示词（支持微调或清空重写）
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🖼️ 生图提示词 (Prompt)：',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
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
                  '💡 可修改本页场景提示词；重绘时会自动加入已保存的角色外貌、服装与定妆照。',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                if (curItem.imageModelUsed != null)
                  Text(
                    '上次模型：${curItem.imageModelUsed} · 角色参考图：${curItem.imageReferenceApplied ? '已传入' : '未传入'}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
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
            label: const Text(
              '🚀 立即重新生图',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _doRegen(promptCtrl.text.trim(), compositionCtrl.text.trim());
            },
          ),
        ],
      ),
    );
  }

  void _showCharacterReferences() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('角色设定与定妆照'),
        content: SizedBox(
          width: 620,
          height: 460,
          child: ListView(
            children: [
              for (final character in _book.characters)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 120,
                          child: character.referenceImageBase64 == null
                              ? const Icon(Icons.person_outline, size: 48)
                              : Image.memory(
                                  base64Decode(character.referenceImageBase64!),
                                  fit: BoxFit.contain,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                character.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (character.species.isNotEmpty)
                                Text('物种：${character.species}'),
                              Text('固定外貌：${character.appearance}'),
                              Text('默认服装：${character.defaultOutfit}'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 中断后从草稿续画时，先恢复缺失的角色定妆照并让用户查看。
  Future<bool> _ensureCharacterReferences({
    required AppSettings settings,
    required BookStyle style,
    required Iterable<BookPageItem> pages,
  }) async {
    if (!_engine.supportsCharacterReference(
      type: settings.imageType,
      baseUrl: settings.imageBaseUrl,
      model: settings.imageModel,
    )) {
      return true;
    }
    final ids = pages.expand((page) => page.characterIds).toSet();
    final missing = _book.characters
        .where((c) => ids.contains(c.id) && c.referenceImageBase64 == null)
        .toList();
    if (missing.isEmpty) return true;
    for (final character in missing) {
      final image = await _engine.generateCharacterReference(
        settings: settings,
        style: style,
        character: character,
      );
      if (image == null || image.isEmpty) {
        throw StateError('${character.name} 定妆照生成失败');
      }
      character.referenceImageBase64 = image;
      await _storage.saveBook(_book);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已补齐角色定妆照。请先查看角色设定，确认后再次点击重绘或补画。')),
      );
      setState(() {});
    }
    return false;
  }

  Future<void> _doRegen(
    String fullPromptOverride,
    String compositionOverride,
  ) async {
    setState(() => _isRegenerating = true);
    try {
      final settings = await _settingsService.loadSettings();
      final style = StyleCatalog.styles.firstWhere(
        (s) => s.id == _book.styleId,
        orElse: () => StyleCatalog.styles.first,
      );

      final page = _book.pages[_currentPage];
      if (!await _ensureCharacterReferences(
        settings: settings,
        style: style,
        pages: [page],
      )) {
        return;
      }
      page.sceneComposition = compositionOverride;
      await _storage.saveBook(_book);
      final oldImage = page.imageBase64;
      final newB64 = await _engine.generateIllustration(
        settings: settings,
        style: style,
        page: page,
        fullPromptOverride: fullPromptOverride,
        referenceImageBase64: _book.characters.isEmpty
            ? _book.protagonistRefImage
            : null,
        characters: _book.characters,
      );

      if (newB64 != null) {
        page.imageBase64 = newB64;
        // 如果全书此前还没有基准主角图，将本次成功生成的图存为基准
        if (_book.characters.isEmpty &&
            (_book.protagonistRefImage == null ||
                _book.protagonistRefImage == oldImage)) {
          _book.protagonistRefImage = newB64;
        }
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

  Future<void> _startBatchDrawMissing() async {
    final pendingPages = _book.pendingIllustrationPages;
    if (pendingPages.isEmpty) return;

    final settings = await _settingsService.loadSettings();
    if (settings.imageApiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ 请先前往设置中配置生图 API Key'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final style = StyleCatalog.styles.firstWhere(
      (s) => s.id == _book.styleId,
      orElse: () => StyleCatalog.styles.first,
    );

    setState(() {
      _isBatchDrawing = true;
      _batchProgressText = '正在激活屏幕常亮保护，准备补画插画...';
      _batchProgressValue = 0.0;
    });

    try {
      await WakelockPlus.enable();
    } catch (_) {}

    try {
      if (!await _ensureCharacterReferences(
        settings: settings,
        style: style,
        pages: pendingPages,
      )) {
        return;
      }
      int done = 0;
      final totalToDraw = pendingPages.length;

      for (var page in pendingPages) {
        done++;
        if (mounted) {
          setState(() {
            _batchProgressText =
                '正在补画：第 ${page.pageIndex + 1} 页 (${style.name})...\n'
                '进度：$done / $totalToDraw';
            _batchProgressValue = done / totalToDraw;
          });
        }

        try {
          final b64 = await _engine.generateIllustration(
            settings: settings,
            style: style,
            page: page,
            referenceImageBase64: _book.characters.isEmpty
                ? _book.protagonistRefImage
                : null,
            characters: _book.characters,
          );
          if (b64 != null && b64.isNotEmpty) {
            page.imageBase64 = b64;
            page.isPlaceholder = false;
            page.generationError = null;
            if (_book.characters.isEmpty) _book.protagonistRefImage ??= b64;
          }
        } catch (e) {
          page.isPlaceholder = true;
          page.generationError = e.toString();
        }

        // 逐页实时落盘保存在本地
        await _storage.saveBook(_book);
        if (mounted) setState(() {});
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('🎉 批量补画流程已完成！')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量补画异常: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      if (mounted) {
        setState(() => _isBatchDrawing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _book.pages.length;
    final curPage = _book.pages[_currentPage];
    final hasAudioCache =
        curPage.audioPath != null && curPage.audioPath!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('📖 ${_book.title}'),
        actions: [
          if (_book.characters.isNotEmpty)
            IconButton(
              tooltip: '查看角色定妆照与固定设定',
              icon: const Icon(Icons.people_outline),
              onPressed: _showCharacterReferences,
            ),
          // 1. 自动连读切换
          Tooltip(
            message: _autoPlayNext ? '自动翻页连读：已开启' : '自动翻页连读：已关闭',
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: _autoPlayNext
                    ? const Color(0xFFD8A24A)
                    : Colors.grey,
              ),
              icon: Icon(
                _autoPlayNext
                    ? Icons.autorenew_rounded
                    : Icons.sync_disabled_rounded,
                size: 18,
              ),
              label: Text(
                _autoPlayNext ? '连读开' : '连读关',
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: () {
                setState(() => _autoPlayNext = !_autoPlayNext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _autoPlayNext ? '✅ 已开启：读完当前页将自动翻至下一页' : '已关闭自动翻页连读',
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),

          // 2. 重新生成本页语音按钮
          IconButton(
            tooltip: '重新使用 MiniMax 合成本页语音并覆盖',
            icon: const Icon(Icons.record_voice_over_outlined),
            onPressed: (_isAudioSynthesizing || _isRegenerating)
                ? null
                : () => _togglePlayCurrentPage(forceRegen: true),
          ),

          // 3. 核心朗读播放 / 暂停按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: _isAudioSynthesizing
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                  )
                : IconButton.filledTonal(
                    tooltip: _isPlaying
                        ? '暂停朗读'
                        : (hasAudioCache ? '播放本地温柔朗读' : '一键合成温柔朗读'),
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: _isPlaying ? Colors.amber : null,
                    ),
                    onPressed: _isRegenerating
                        ? null
                        : () => _togglePlayCurrentPage(),
                  ),
          ),

          // 4. 重绘插画按钮
          IconButton(
            tooltip: '修改说明并重绘当前页插画',
            icon: const Icon(Icons.brush),
            onPressed: (_isRegenerating || _isBatchDrawing)
                ? null
                : _openRegenDialog,
          ),
          // 5. 如果全书有尚未生成的插画，提供一键批量补画入口
          if (_book.hasUnfinishedIllustrations)
            Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD8A24A),
                  foregroundColor: Colors.black87,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                ),
                icon: const Icon(Icons.palette_outlined, size: 16),
                label: Text(
                  '补画剩余(${_book.pendingIllustrationPages.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: (_isBatchDrawing || _isRegenerating)
                    ? null
                    : _startBatchDrawMissing,
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: total,
            onPageChanged: (i) async {
              await _audioPlayer.stop();
              setState(() => _currentPage = i);
              if (_autoPlayNext) {
                _togglePlayCurrentPage();
              }
            },
            itemBuilder: (context, index) {
              final page = _book.pages[index];
              final isPageCached =
                  page.audioPath != null && page.audioPath!.isNotEmpty;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
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
                                            const Icon(
                                              Icons.broken_image_outlined,
                                              size: 48,
                                              color: Colors.orangeAccent,
                                            ),
                                            const SizedBox(height: 12),
                                            const Text(
                                              '⚠️ 插画未成功生成',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              page.generationError != null
                                                  ? '原因: ${page.generationError}'
                                                  : '可能是上游网络抖动或触发了安全内容拦截',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 16),
                                            ElevatedButton.icon(
                                              icon: const Icon(
                                                Icons.refresh,
                                                size: 16,
                                              ),
                                              label: const Text('点击重新绘制本页'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(
                                                  0xFFD8A24A,
                                                ),
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
                          const SizedBox(height: 16),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Text(
                                      page.text,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        height: 1.8,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // 音频状态小横条
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isPageCached
                                            ? Icons.offline_pin_rounded
                                            : Icons.cloud_download_outlined,
                                        size: 15,
                                        color: isPageCached
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          isPageCached
                                              ? '本地已缓存人声（永久保存，离线即播，零网络消耗）'
                                              : '尚未生成本页人声，点击上方播放按钮即可使用 MiniMax 自动生成并保存',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isPageCached
                                                ? Colors.green
                                                : Colors.grey,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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
          if (_isBatchDrawing)
            Container(
              color: Colors.black87,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      Text(
                        _batchProgressText,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 320,
                        child: LinearProgressIndicator(
                          value: _batchProgressValue,
                          backgroundColor: Colors.white12,
                          color: const Color(0xFFD8A24A),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFD8A24A).withOpacity(0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              size: 16,
                              color: Color(0xFFD8A24A),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '💡 屏幕常亮保护中 · 逐页绘制实时落盘',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                    Text(
                      '正在重绘当前页插画，请稍候...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          if (_isAudioSynthesizing)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 10),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFD8A24A),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        '🎙️ 正在使用 MiniMax 生成温柔人声并落盘中...',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
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
