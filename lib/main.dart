import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/book.dart';
import 'models/fairy_tale_catalog.dart';
import 'screens/book_reader_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    final list = await _storage.loadBooks();
    setState(() {
      _books = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📖 BookBuddy 绘本工坊'),
        actions: [
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
                                      await showDialog(
                                        context: context,
                                        builder: (_) => const TaleRecommendationDialog(),
                                      );
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
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                      leading: const CircleAvatar(
                                        backgroundColor: Color(0xFF2F2920),
                                        child: Icon(Icons.menu_book, color: Color(0xFFD8A24A)),
                                      ),
                                      title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      subtitle: Text('$dateStr · ${b.pages.length} 页 · 画风: ${b.styleName}'),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => BookReaderScreen(book: b)),
                                        );
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
