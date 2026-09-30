import 'dart:io';

import 'package:flutter/material.dart';

import '../models/character_card.dart';
import '../services/book_storage_service.dart';
import '../services/character_storage_service.dart';
import 'character_card_editor_screen.dart';

class CharacterLibraryScreen extends StatefulWidget {
  final CharacterStorageService? storage;
  final BookStorageService? bookStorage;

  const CharacterLibraryScreen({super.key, this.storage, this.bookStorage});

  @override
  State<CharacterLibraryScreen> createState() => _CharacterLibraryScreenState();
}

class _CharacterLibraryScreenState extends State<CharacterLibraryScreen> {
  late final CharacterStorageService _storage;
  late final BookStorageService _bookStorage;
  List<CharacterCard> _cards = [];
  Map<String, int> _bookCounts = {};
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? CharacterStorageService();
    _bookStorage = widget.bookStorage ?? BookStorageService();
    _load();
    CharacterStorageService.cardsChangedNotifier.addListener(_load);
  }

  @override
  void dispose() {
    CharacterStorageService.cardsChangedNotifier.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cards = await _storage.loadCards();
      if (!mounted) return;
      // 先渲染卡片，再统计出演次数；书架很大时不让角色库一直转圈。
      setState(() {
        _cards = cards;
        _loading = false;
        _errorMessage = null;
      });
      final counts = <String, int>{};
      try {
        for (final book in await _bookStorage.loadBooks()) {
          for (final id in book.characterCardIds.toSet()) {
            counts[id] = (counts[id] ?? 0) + 1;
          }
        }
      } catch (_) {
        // 书架读不出来只影响「出演 N 本」，不影响角色库本身。
      }
      if (!mounted) return;
      setState(() => _bookCounts = counts);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '加载角色库失败: $e';
      });
    }
  }

  Future<void> _openEditor([CharacterCard? card]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterCardEditorScreen(card: card, storage: _storage),
      ),
    );
  }

  Future<void> _confirmDelete(CharacterCard card) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除角色「${card.name}」'),
        content: const Text('角色卡和它的定妆图将被删除。已生成的绘本不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _storage.deleteCard(card.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _kindLabel(CharacterKind kind) => switch (kind) {
        CharacterKind.human => '人类',
        CharacterKind.animal => '动物',
        CharacterKind.object => '物件',
      };

  /// 缩略图优先级：默认画风定妆图 → 任意定妆图 → 照片 → 占位图标。
  String? _thumbnailPath(CharacterCard card) {
    if (card.anchorImagePaths.containsKey('watercolor')) {
      return card.anchorImagePaths['watercolor'];
    }
    if (card.anchorImagePaths.isNotEmpty) {
      return card.anchorImagePaths.values.first;
    }
    return card.photoPath;
  }

  Widget _thumbnail(CharacterCard card) {
    final relative = _thumbnailPath(card);
    if (relative == null) {
      return const Center(
        child: Icon(Icons.face_retouching_natural, size: 48, color: Colors.grey),
      );
    }
    return FutureBuilder<File>(
      future: _storage.imageFile(relative),
      builder: (ctx, snap) {
        final file = snap.data;
        if (file == null || !file.existsSync()) {
          return const Center(
            child: Icon(Icons.broken_image_outlined, size: 40, color: Colors.grey),
          );
        }
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (ctx, error, stack) => const Center(
            child: Icon(Icons.broken_image_outlined, size: 40, color: Colors.grey),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('👥 我的角色')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新建角色'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? _buildError()
                  : _cards.isEmpty
                      ? _buildEmpty()
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 200,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: _cards.length,
                          itemBuilder: (ctx, i) => _buildCard(_cards[i]),
                        ),
        ),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.face_retouching_natural, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('还没有角色', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 4),
            const Text(
              '拍一张玩具照片或手动描述，都能创建角色',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('创建第一个角色'),
            ),
          ],
        ),
      );

  Widget _buildCard(CharacterCard card) => Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          onTap: () => _openEditor(card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _thumbnail(card)),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_kindLabel(card.kind)} · 定妆图 ${card.anchorImagePaths.length} 张 · 出演 ${_bookCounts[card.id] ?? 0} 本',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '删除角色',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: Colors.grey,
                      onPressed: () => _confirmDelete(card),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
