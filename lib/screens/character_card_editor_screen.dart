import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/character_card.dart';
import '../models/style_catalog.dart';
import '../services/book_engine_service.dart';
import '../services/character_storage_service.dart';
import '../services/settings_service.dart';

/// 角色卡新建 / 编辑页。card 为空表示新建。
class CharacterCardEditorScreen extends StatefulWidget {
  final CharacterCard? card;
  final CharacterStorageService? storage;
  final BookEngineService? engine;
  final Future<AppSettings> Function()? loadSettings;

  const CharacterCardEditorScreen({
    super.key,
    this.card,
    this.storage,
    this.engine,
    this.loadSettings,
  });

  @override
  State<CharacterCardEditorScreen> createState() =>
      _CharacterCardEditorScreenState();
}

class _CharacterCardEditorScreenState extends State<CharacterCardEditorScreen> {
  late final CharacterStorageService _storage;
  // ignore: unused_field
  late final BookEngineService _engine;
  // ignore: unused_field
  late final Future<AppSettings> Function() _loadSettings;

  /// 工作副本：编辑模式下是传入卡片的深拷贝，保存前不影响原对象。
  late CharacterCard _card;
  late bool _isNew;

  /// 上次保存时的外貌相关字段快照，用来判断是否需要清空定妆图。
  late String _savedLook;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _speciesCtrl;
  late final TextEditingController _appearanceCtrl;
  late final TextEditingController _outfitCtrl;
  late final TextEditingController _personalityCtrl;
  late final TextEditingController _catchphraseCtrl;
  CharacterKind _kind = CharacterKind.animal;
  String _styleId = 'watercolor';

  // ignore: prefer_final_fields
  bool _busy = false;
  // ignore: prefer_final_fields
  String _busyText = '';

  /// 本次会话刚生成的定妆图字节，优先于磁盘文件显示，避免图片缓存显示旧图。
  final Map<String, Uint8List> _freshAnchors = {};

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? CharacterStorageService();
    _engine = widget.engine ?? BookEngineService();
    _loadSettings = widget.loadSettings ?? SettingsService().loadSettings;
    _isNew = widget.card == null;
    _card = widget.card == null
        ? CharacterCard(id: CharacterCard.newId(), name: '', appearance: '')
        : CharacterCard.fromJson(widget.card!.toJson());
    _kind = _card.kind;
    _nameCtrl = TextEditingController(text: _card.name);
    _speciesCtrl = TextEditingController(text: _card.species);
    _appearanceCtrl = TextEditingController(text: _card.appearance);
    _outfitCtrl = TextEditingController(text: _card.defaultOutfit);
    _personalityCtrl = TextEditingController(text: _card.personality);
    _catchphraseCtrl = TextEditingController(text: _card.catchphrase);
    _savedLook = _lookOf(_card);
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _speciesCtrl,
      _appearanceCtrl,
      _outfitCtrl,
      _personalityCtrl,
      _catchphraseCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _lookOf(CharacterCard c) =>
      '${c.kind.name}|${c.species}|${c.appearance}|${c.defaultOutfit}';

  /// 把表单写回工作副本；返回校验错误文案，null 表示通过。
  String? _applyForm() {
    _card
      ..name = _nameCtrl.text.trim()
      ..kind = _kind
      ..species = _speciesCtrl.text.trim()
      ..appearance = _appearanceCtrl.text.trim()
      ..defaultOutfit = _outfitCtrl.text.trim()
      ..personality = _personalityCtrl.text.trim()
      ..catchphrase = _catchphraseCtrl.text.trim();
    if (_card.name.isEmpty || _card.appearance.isEmpty) {
      return '请填写角色名和外貌';
    }
    return null;
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  /// 校验 → 外貌变更时确认清空定妆图 → 落盘。返回是否成功。
  Future<bool> _save() async {
    final error = _applyForm();
    if (error != null) {
      _toast(error, error: true);
      return false;
    }
    final lookChanged = _lookOf(_card) != _savedLook;
    if (lookChanged && _card.anchorImagePaths.isNotEmpty) {
      final count = _card.anchorImagePaths.length;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('外貌设定已修改'),
          content: Text('已有 $count 张定妆图将被清空，下次使用时重新生成。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空并保存'),
            ),
          ],
        ),
      );
      if (confirm != true) return false;
      try {
        await _storage.clearAnchors(_card.id);
      } catch (e) {
        _toast('清空定妆图失败: $e', error: true);
        return false;
      }
      _card.anchorImagePaths.clear();
      _freshAnchors.clear();
    }
    try {
      await _storage.saveCard(_card);
    } catch (e) {
      _toast('保存失败: $e', error: true);
      return false;
    }
    _isNew = false;
    _savedLook = _lookOf(_card);
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _saveAndClose() async {
    if (await _save() && mounted) {
      Navigator.pop(context, _card);
    }
  }

  Future<void> _generateAnchor() async {
    _toast('定妆图生成将在下一任务实现');
  }

  @override
  Widget build(BuildContext context) {
    final style = StyleCatalog.styles.firstWhere((s) => s.id == _styleId);
    final anchorPath = _card.anchorImagePaths[_styleId];
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建角色' : '编辑角色：${_card.name}'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _saveAndClose,
            icon: const Icon(Icons.check),
            label: const Text('保存'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  _busyText,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
              ],
              _sectionTitle('🧸 基本设定'),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '角色名 *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<CharacterKind>(
                segments: const [
                  ButtonSegment(
                    value: CharacterKind.human,
                    label: Text('人类'),
                    icon: Icon(Icons.person_outline),
                  ),
                  ButtonSegment(
                    value: CharacterKind.animal,
                    label: Text('动物'),
                    icon: Icon(Icons.pets),
                  ),
                  ButtonSegment(
                    value: CharacterKind.object,
                    label: Text('物件'),
                    icon: Icon(Icons.toys_outlined),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: _busy
                    ? null
                    : (selection) => setState(() => _kind = selection.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _speciesCtrl,
                decoration: const InputDecoration(
                  labelText: '物种或物件名（如：毛绒恐龙、石头、小猫）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _appearanceCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '外貌锚定描述 *（颜色、材质、体型、标志性细节）',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _outfitCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '默认服装（可留空）',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle('💬 性格与口头禅'),
              TextField(
                controller: _personalityCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '性格',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _catchphraseCtrl,
                decoration: const InputDecoration(
                  labelText: '口头禅',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle('🎨 定妆图画风'),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: StyleCatalog.styles
                    .map(
                      (s) => ChoiceChip(
                        label: Text(s.name),
                        selected: s.id == _styleId,
                        avatar: _card.anchorImagePaths.containsKey(s.id)
                            ? const Icon(Icons.check_circle, size: 16)
                            : null,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _styleId = s.id),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              _buildAnchorPreview(anchorPath),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _generateAnchor,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  anchorPath == null
                      ? '生成${style.name}定妆图'
                      : '重新生成${style.name}定妆图',
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                '修改角色卡只影响之后新建的绘本。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      );

  Widget _buildAnchorPreview(String? anchorPath) {
    final fresh = _freshAnchors[_styleId];
    final Widget child;
    if (fresh != null) {
      child = Image.memory(fresh, fit: BoxFit.contain);
    } else if (anchorPath == null) {
      child = const Center(
        child: Text('还没有这个画风的定妆图', style: TextStyle(color: Colors.grey)),
      );
    } else {
      child = FutureBuilder<File>(
        future: _storage.imageFile(anchorPath),
        builder: (ctx, snap) {
          final file = snap.data;
          if (file == null || !file.existsSync()) {
            return const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.grey),
            );
          }
          return Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (ctx, error, stack) => const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.grey),
            ),
          );
        },
      );
    }
    return Container(
      height: 260,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: child,
    );
  }
}
