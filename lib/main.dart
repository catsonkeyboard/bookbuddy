import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'models/book.dart';
import 'models/fairy_tale_catalog.dart';
import 'screens/book_reader_screen.dart';
import 'screens/character_card_editor_screen.dart';
import 'screens/character_library_screen.dart';
import 'screens/create_book_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tale_recommendation_dialog.dart';
import 'services/book_exchange_service.dart';
import 'services/book_storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BookBuddyApp());
}

class BookBuddyApp extends StatelessWidget {
  const BookBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BookBuddy 绘本工坊',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.amber,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF141311),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD8A24A),
          surface: Color(0xFF1E1C18),
          surfaceContainerHighest: Color(0xFF282520),
          outline: Color(0xFF8A8275),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E1C18),
        ),
      ),
      home: const MainHomeScreen(),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  final BookStorageService? bookStorage;

  const MainHomeScreen({super.key, this.bookStorage});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  late final BookStorageService _storage =
      widget.bookStorage ?? BookStorageService();
  late final BookExchangeService _exchange = BookExchangeService();
  List<BookSummary> _books = [];
  bool _loading = true;
  bool _shelfLoadInFlight = false;
  bool _shelfReloadRequested = false;
  String? _openingBookId;

  String? _errorMessage;

  /// 正在导出/导入的书 id / 文件名，用于禁用对应入口防手抖并发。
  String? _exportingBookId;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _loadBooks();
    BookStorageService.booksChangedNotifier.addListener(_onBooksChanged);
  }

  @override
  void dispose() {
    BookStorageService.booksChangedNotifier.removeListener(_onBooksChanged);
    super.dispose();
  }

  void _onBooksChanged() {
    if (mounted) {
      _loadBooks();
    }
  }

  /// 书架只加载摘要，读取和解析在后台 isolate 里进行。
  ///
  /// 加载期间又来了刷新请求（连续保存会连续通知）时不再并行开一个后台加载，
  /// 而是等这一轮结束后补一轮，保证书架最后停在最新状态。
  Future<void> _loadBooks() async {
    if (_shelfLoadInFlight) {
      _shelfReloadRequested = true;
      return;
    }
    _shelfLoadInFlight = true;
    try {
      do {
        _shelfReloadRequested = false;
        try {
          final list = await _storage.loadBookSummaries();
          if (mounted) {
            setState(() {
              _books = list;
              _loading = false;
              _errorMessage = null;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _loading = false;
              _errorMessage = '加载绘本数据失败: $e';
            });
          }
        }
      } while (_shelfReloadRequested && mounted);
    } finally {
      _shelfLoadInFlight = false;
    }
  }

  /// 书架手里只有摘要，点开时才把整本（含插画）加载出来交给阅读器。
  Future<void> _openBook(BookSummary summary) async {
    if (_openingBookId != null) return;
    setState(() => _openingBookId = summary.id);
    PictureBook? book;
    try {
      book = await _storage.loadBook(summary.id);
    } catch (_) {
      // 按读不出来处理。
    }
    if (!mounted) return;
    setState(() => _openingBookId = null);
    if (book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打不开绘本《${summary.title}》：文件已损坏或被删除'),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      final opened = book;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BookReaderScreen(book: opened)),
      );
    }
    // 阅读器内可能重绘/重录，返回后刷新书架；页面可能已在 await 期间退出。
    if (mounted) _loadBooks();
  }

  Future<void> _confirmDeleteBook(BookSummary book) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('删除绘本'),
          ],
        ),
        content: Text(
          '确定要彻底删除绘本《${book.title}》吗？\n所有已生成的插画及语音缓存都将被永久删除，此操作不可恢复。',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _storage.deleteBook(book.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除绘本《${book.title}》')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 导出一本书为 .bb：桌面端弹保存对话框，移动端走系统分享面板。
  ///
  /// 书架手里只有摘要，导出前先把整本（含插画）加载出来；同一时间只允许
  /// 一个导出任务，防手抖连续点击。
  Future<void> _exportBook(BookSummary summary) async {
    if (_exportingBookId != null) return;
    setState(() => _exportingBookId = summary.id);
    try {
      PictureBook? book;
      try {
        book = await _storage.loadBook(summary.id);
      } catch (_) {}
      if (book == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('打不开绘本《${summary.title}》：文件已损坏或被删除'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final safeTitle = _safeFileName(summary.title);
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _exportViaShareSheet(book, safeTitle);
        return;
      }
      await _exportViaSaveDialog(book, safeTitle);
    } finally {
      if (mounted) setState(() => _exportingBookId = null);
    }
  }

  Future<void> _exportViaSaveDialog(PictureBook book, String safeTitle) async {
    final location = await getSaveLocation(
      suggestedName: '$safeTitle.bb',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'BookBuddy 绘本', extensions: ['bb']),
      ],
    );
    if (location == null) return; // 用户取消
    var outputPath = location.path;
    if (!outputPath.toLowerCase().endsWith('.bb')) {
      outputPath = '$outputPath.bb'; // 某些平台对话框不给自动补后缀
    }

    try {
      final bytes = await _exchange.exportBookToFile(book, outputPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已导出《${book.title}』（${(bytes / 1024 / 1024).toStringAsFixed(1)} MB）',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportViaShareSheet(PictureBook book, String safeTitle) async {
    final tmpDir = await getTemporaryDirectory();
    final tmpPath = '${tmpDir.path}/${book.id}_export.bb';
    try {
      await _exchange.exportBookToFile(book, tmpPath);
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tmpPath)],
          fileNameOverrides: ['$safeTitle.bb'],
        ),
      );
      if (mounted && result.status == ShareResultStatus.success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已导出《${book.title}』')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      try {
        final f = File(tmpPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// 导入一本 .bb：系统打开对话框选文件，校验通过后落盘并刷新书架。
  Future<void> _importBook() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'BookBuddy 绘本', extensions: ['bb']),
        ],
      );
      if (file == null) return; // 用户取消

      try {
        final result = await _exchange.importBookFromFile(file.path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.isDuplicateCopy
                    ? '已导入副本《${result.book.title}』'
                    : '已导入《${result.book.title}』',
              ),
            ),
          );
        }
      } on BookExchangeException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 文件名去掉各平台文件系统的非法字符。
  String _safeFileName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[\\/:*?\"<>|]'), '_').trim();
    return cleaned.isEmpty ? '绘本' : cleaned;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📖 BookBuddy 绘本工坊'),
        actions: [
          if (!kIsWeb)
            IconButton(
              tooltip: '导入绘本 (.bb)',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: _importing ? null : _importBook,
            ),
          IconButton(
            tooltip: '我的角色',
            icon: const Icon(Icons.face_retouching_natural),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CharacterLibraryScreen()),
              );
            },
          ),
          IconButton(
            tooltip: '模型与接口配置',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部创建引导卡片
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        color: const Color(0xFF23201B),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_stories, size: 54, color: Color(0xFFD8A24A)),
                              const SizedBox(width: 20),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '创作一本全新的精美绘本',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '输入童话标题或故事正文，自动分镜并逐页绘制高清插画',
                                      style: TextStyle(fontSize: 13, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFD8A24A),
                                      side: const BorderSide(color: Color(0xFFD8A24A)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    ),
                                    icon: const Text('🌟', style: TextStyle(fontSize: 16)),
                                    label: const Text('经典故事灵感', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () async {
                                      final selectedTale = await showDialog<FairyTaleItem?>(
                                        context: context,
                                        builder: (_) => const TaleRecommendationDialog(),
                                      );
                                      if (selectedTale != null && context.mounted) {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => CreateBookScreen(
                                              initialTitle: selectedTale.title,
                                              initialSynopsis: selectedTale.synopsis,
                                              initialStyleId: selectedTale.recommendedStyle,
                                            ),
                                          ),
                                        );
                                      }
                                      _loadBooks();
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD8A24A),
                                      foregroundColor: Colors.black87,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                    ),
                                    icon: const Icon(Icons.add),
                                    label: const Text('新建绘本', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const CreateBookScreen()),
                                      );
                                      _loadBooks();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 角色卡引导
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        color: const Color(0xFF23201B),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          child: Row(
                            children: [
                              const Icon(Icons.face_retouching_natural, size: 54, color: Color(0xFFD8A24A)),
                              const SizedBox(width: 20),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '拍一张玩具，做一个专属主角',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '拍照或手动描述，创建可复用的角色卡，之后每本绘本都能请他出场',
                                      style: TextStyle(fontSize: 13, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFD8A24A),
                                      side: const BorderSide(color: Color(0xFFD8A24A)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    ),
                                    icon: const Icon(Icons.people_outline, size: 18),
                                    label: const Text('我的角色', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const CharacterLibraryScreen()),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD8A24A),
                                      foregroundColor: Colors.black87,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                    ),
                                    icon: const Icon(Icons.add),
                                    label: const Text('新建角色', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const CharacterCardEditorScreen()),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() => _loading = true);
                                  _loadBooks();
                                },
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      // 下方：我的作品书架列表
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '📚 我的绘本作品库',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '共 ${_books.length} 本',
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _books.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.book_outlined, size: 64, color: Colors.grey),
                                    const SizedBox(height: 16),
                                    const Text('书架空空如也，快去点击上方“新建绘本”创作第一本吧！', style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _books.length,
                                itemBuilder: (ctx, i) {
                                  final b = _books[i];
                                  final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(b.createdAt);
                                  final hasUnfinished = b.hasUnfinishedIllustrations;
                                  final completedCount = b.completedIllustrationCount;
                                  final targetCount = b.targetIllustrationCount;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                      leading: CircleAvatar(
                                        backgroundColor: hasUnfinished
                                            ? Colors.orange.withOpacity(0.15)
                                            : const Color(0xFF2F2920),
                                        child: Icon(
                                          hasUnfinished ? Icons.brush_outlined : Icons.menu_book,
                                          color: hasUnfinished ? Colors.orange : const Color(0xFFD8A24A),
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              b.title,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (b.usesCharacterCards) ...[
                                            const SizedBox(width: 6),
                                            const Tooltip(
                                              message: '使用了角色卡',
                                              child: Icon(
                                                Icons.face_retouching_natural,
                                                size: 16,
                                                color: Color(0xFFD8A24A),
                                              ),
                                            ),
                                          ],
                                          if (hasUnfinished) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: Colors.orange.withOpacity(0.4)),
                                              ),
                                              child: Text(
                                                '待补画 ($completedCount/$targetCount)',
                                                style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      subtitle: Text('$dateStr · ${b.pageCount} 页 · 画风: ${b.styleName}'),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!kIsWeb) ...[
                                            if (_exportingBookId == b.id)
                                              const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: Padding(
                                                  padding: EdgeInsets.all(3),
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                              )
                                            else
                                              IconButton(
                                                tooltip: '导出绘本 (.bb)',
                                                icon: const Icon(
                                                  Icons.ios_share_outlined,
                                                  size: 20,
                                                ),
                                                color: Colors.grey,
                                                onPressed:
                                                    _exportingBookId != null
                                                        ? null
                                                        : () =>
                                                            _exportBook(b),
                                              ),
                                          ],
                                          IconButton(
                                            tooltip: '删除绘本',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 20,
                                            ),
                                            color: Colors.grey,
                                            hoverColor: Colors.red
                                                .withOpacity(0.1),
                                            onPressed: () => _confirmDeleteBook(b),
                                          ),
                                          if (_openingBookId == b.id)
                                            const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: Padding(
                                                padding: EdgeInsets.all(3),
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              ),
                                            )
                                          else
                                            const Icon(Icons.chevron_right),
                                        ],
                                      ),
                                      onTap: () => _openBook(b),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
