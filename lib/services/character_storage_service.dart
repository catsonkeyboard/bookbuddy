import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/character_card.dart';

/// 角色库落盘。目录结构：
/// bookbuddy_characters/
/// ├── cards.json（仅元数据，附 .bak / .tmp 双保险）
/// └── card_xxx/（该卡片的图片文件）
class CharacterStorageService {
  static const _cardsFileName = 'cards.json';

  /// 所有写操作串行化，保证 cards.json 不被并发写坏。
  static Future<void>? _pendingSave;

  /// 新建 / 更新 / 删除卡片后 +1，供列表页刷新。
  static final ValueNotifier<int> cardsChangedNotifier = ValueNotifier<int>(0);

  final Directory? _directory;

  CharacterStorageService({this._directory});

  /// 卡片 id 只能是单个目录名：非空、不含路径分隔符、不是 . 或 ..。
  static bool isValidId(String id) =>
      id.isNotEmpty &&
      !id.contains('/') &&
      !id.contains('\\') &&
      id != '.' &&
      id != '..';

  /// 相对路径只能指向角色库目录内部：非空、不是绝对路径、任一段都不是 . 或 ..。
  static bool isSafeRelativePath(String relativePath) =>
      relativePath.isNotEmpty &&
      !relativePath.startsWith('/') &&
      !relativePath.contains('\\') &&
      relativePath.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');

  Future<Directory> _root() async {
    final dir = _directory ??
        Directory(
          '${(await getApplicationDocumentsDirectory()).path}/bookbuddy_characters',
        );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _cardsFile() async =>
      File('${(await _root()).path}/$_cardsFileName');

  List<CharacterCard>? _parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((m) => CharacterCard.fromJson(Map<String, dynamic>.from(m)))
          .where((c) => isValidId(c.id))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<CharacterCard>> _readAll() async {
    final file = await _cardsFile();
    final backup = File('${file.path}.bak');
    for (final candidate in [file, backup]) {
      if (await candidate.exists()) {
        final cards = _parse(await candidate.readAsString());
        if (cards != null) return cards;
      }
    }
    return [];
  }

  /// 按最近使用时间（没有则按创建时间）倒序。
  Future<List<CharacterCard>> loadCards() async {
    final cards = await _readAll();
    cards.sort(
      (a, b) => (b.lastUsedAt ?? b.createdAt)
          .compareTo(a.lastUsedAt ?? a.createdAt),
    );
    return cards;
  }

  Future<void> saveCard(CharacterCard card) async {
    if (!isValidId(card.id)) {
      throw ArgumentError('Card id is not a valid directory name: ${card.id}');
    }
    await _mutate((cards) {
      final index = cards.indexWhere((c) => c.id == card.id);
      if (index >= 0) {
        cards[index] = card;
      } else {
        cards.add(card);
      }
    });
  }

  Future<void> deleteCard(String id) async {
    if (!isValidId(id)) {
      throw ArgumentError('Card id is not a valid directory name: $id');
    }
    await _mutate((cards) => cards.removeWhere((c) => c.id == id));
    final dir = Directory('${(await _root()).path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 写入卡片目录下的图片文件，返回相对角色库根目录的路径。
  Future<String> writeImage(
    String cardId,
    String fileName,
    Uint8List bytes,
  ) async {
    if (!isValidId(cardId)) {
      throw ArgumentError('Card id is not a valid directory name: $cardId');
    }
    final dir = Directory('${(await _root()).path}/$cardId');
    if (!await dir.exists()) await dir.create(recursive: true);
    await File('${dir.path}/$fileName').writeAsBytes(bytes, flush: true);
    return '$cardId/$fileName';
  }

  Future<File> imageFile(String relativePath) async {
    if (!isSafeRelativePath(relativePath)) {
      throw ArgumentError('Image path escapes the character library: $relativePath');
    }
    return File('${(await _root()).path}/$relativePath');
  }

  Future<String?> readImageBase64(String relativePath) async {
    final file = await imageFile(relativePath);
    if (!await file.exists()) return null;
    return base64Encode(await file.readAsBytes());
  }

  /// 落盘定妆图并更新卡片映射。扩展名按字节头判断（PNG 签名 → png，否则 jpg）。
  Future<String> saveAnchor(
    String cardId,
    String styleId,
    String base64Image,
  ) async {
    if (!isValidId(cardId)) {
      throw ArgumentError('Card id is not a valid directory name: $cardId');
    }
    final raw = base64Image.startsWith('data:')
        ? base64Image.substring(base64Image.indexOf(',') + 1)
        : base64Image;
    final bytes = base64Decode(raw);
    final ext = _isPng(bytes) ? 'png' : 'jpg';
    final relative = await writeImage(cardId, 'anchor_$styleId.$ext', bytes);
    final root = await _root();
    try {
      await _mutate((cards) {
        final index = cards.indexWhere((c) => c.id == cardId);
        if (index < 0) {
          throw StateError('角色卡 $cardId 不存在，无法保存定妆图');
        }
        final old = cards[index].anchorImagePaths[styleId];
        if (old != null && old != relative) {
          final oldFile = File('${root.path}/$old');
          if (oldFile.existsSync()) oldFile.deleteSync();
        }
        cards[index].anchorImagePaths[styleId] = relative;
      });
    } catch (_) {
      final written = File('${root.path}/$relative');
      if (await written.exists()) await written.delete();
      rethrow;
    }
    return relative;
  }

  /// 删除卡片全部定妆图文件并清空映射（外貌设定变更时调用）。
  Future<void> clearAnchors(String cardId) async {
    if (!isValidId(cardId)) {
      throw ArgumentError('Card id is not a valid directory name: $cardId');
    }
    final root = await _root();
    await _mutate((cards) {
      final index = cards.indexWhere((c) => c.id == cardId);
      if (index < 0) return;
      for (final path in cards[index].anchorImagePaths.values) {
        final file = File('${root.path}/$path');
        if (file.existsSync()) file.deleteSync();
      }
      cards[index].anchorImagePaths.clear();
    });
  }

  static bool _isPng(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47;

  /// 读 → 改 → 原子写，排队执行；成功后触发通知。
  Future<void> _mutate(void Function(List<CharacterCard> cards) change) async {
    final previous = _pendingSave;
    final save = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // 上一次失败不应阻塞本次。
        }
      }
      final cards = await _readAll();
      change(cards);
      await _writeAll(cards);
    }();
    _pendingSave = save;
    try {
      await save;
      cardsChangedNotifier.value++;
    } finally {
      if (identical(_pendingSave, save)) _pendingSave = null;
    }
  }

  /// tmp 落盘 → 旧文件可解析则改名 .bak（否则改名 .corrupt.*）→ tmp 改名正式。
  Future<void> _writeAll(List<CharacterCard> cards) async {
    final file = await _cardsFile();
    final backup = File('${file.path}.bak');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(cards.map((c) => c.toJson()).toList()),
      flush: true,
    );

    var movedOriginal = false;
    try {
      if (await file.exists()) {
        if (_parse(await file.readAsString()) != null) {
          if (await backup.exists()) await backup.delete();
          await file.rename(backup.path);
          movedOriginal = true;
        } else {
          await file.rename(
            '${file.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}',
          );
        }
      }
      await temp.rename(file.path);
    } catch (_) {
      // 正式文件已改名为备份但新文件没落成时，把备份复制回来，避免主文件缺失。
      if (movedOriginal && !await file.exists() && await backup.exists()) {
        await backup.copy(file.path);
      }
      rethrow;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
