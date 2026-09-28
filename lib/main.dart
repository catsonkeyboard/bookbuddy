import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/book.dart';
import 'models/fairy_tale_catalog.dart';
import 'screens/book_reader_screen.dart';
import 'screens/character_card_editor_screen.dart';
import 'screens/character_library_screen.dart';
import 'screens/create_book_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tale_recommendation_dialog.dart';
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
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  final BookStorageService _storage = BookStorageService();
  List<PictureBook> _books = [];
  bool _loading = true;

  String? _errorMessage;

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

  Future<void> _loadBooks() async {
    try {
      final list = await _storage.loadBooks();
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
  }

  Future<void> _confirmDeleteBook(PictureBook book) async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📖 BookBuddy 绘本工坊'),
        actions: [
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
                                      '给孩子做一个专属主角',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '创建可复用的角色卡，之后每本绘本都能请他出场',
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
                                      subtitle: Text('$dateStr · ${b.pages.length} 页 · 画风: ${b.styleName}'),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: '删除绘本',
                                            icon: const Icon(Icons.delete_outline, size: 20),
                                            color: Colors.grey,
                                            hoverColor: Colors.red.withOpacity(0.1),
                                            onPressed: () => _confirmDeleteBook(b),
                                          ),
                                          const Icon(Icons.chevron_right),
                                        ],
                                      ),
                                      onTap: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => BookReaderScreen(book: b)),
                                        );
                                        _loadBooks();
                                      },
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
