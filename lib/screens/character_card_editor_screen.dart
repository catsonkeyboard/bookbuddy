import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/app_settings.dart';
import '../models/character_card.dart';
import '../models/style_catalog.dart';
import '../services/book_engine_service.dart';
import '../services/character_storage_service.dart';
import '../services/photo_picker_service.dart';
import '../services/photo_preprocessor.dart';
import '../services/settings_service.dart';
import 'settings_screen.dart';

/// 角色卡新建 / 编辑页。card 为空表示新建。
class CharacterCardEditorScreen extends StatefulWidget {
  final CharacterCard? card;
  final CharacterStorageService? storage;
  final BookEngineService? engine;
  final Future<AppSettings> Function()? loadSettings;
  final PhotoPickerService? photoPicker;

  const CharacterCardEditorScreen({
    super.key,
    this.card,
    this.storage,
    this.engine,
    this.loadSettings,
    this.photoPicker,
  });

  @override
  State<CharacterCardEditorScreen> createState() =>
      _CharacterCardEditorScreenState();
}

class _CharacterCardEditorScreenState extends State<CharacterCardEditorScreen> {
  late final CharacterStorageService _storage;
  late final BookEngineService _engine;
  late final Future<AppSettings> Function() _loadSettings;
  late final PhotoPickerService _photoPicker;

  /// 当前照片（已预处理的 JPEG 字节）；没有照片为 null。
  Uint8List? _photoBytes;

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

  bool _busy = false;
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
    _photoPicker = widget.photoPicker ?? PhotoPickerService();
    _loadPhoto();
    _recoverLostPhoto();
  }

  @override
  void dispose() {
    // 新建且从未保存的角色：照片不应留在本机。
    if (_isNew && _card.photoPath != null) {
      unawaited(_storage.deleteCard(_card.id).catchError((_) {}));
    }
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
    var anchorsCleared = false;
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
      anchorsCleared = true;
    }
    try {
      await _storage.saveCard(_card);
    } catch (e) {
      _toast(
        anchorsCleared ? '保存失败: $e。定妆图已按确认清空，请重试保存。' : '保存失败: $e',
        error: true,
      );
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

  Future<void> _loadPhoto() async {
    final path = _card.photoPath;
    if (path == null) return;
    try {
      final b64 = await _storage.readImageBase64(path);
      if (b64 == null || !mounted) return;
      setState(() => _photoBytes = base64Decode(b64));
    } catch (_) {
      // 照片文件丢失或路径异常：当作没有照片。
    }
  }

  Future<void> _recoverLostPhoto() async {
    final bytes = await _photoPicker.retrieveLost();
    if (bytes != null && mounted) await _setPhoto(bytes);
  }

  Future<void> _pickPhoto(PhotoSource source) async {
    if (_busy) return;
    final Uint8List? bytes;
    try {
      bytes = await _photoPicker.pick(source);
    } catch (e) {
      _toast('无法打开相机或相册: $e', error: true);
      return;
    }
    if (bytes == null || !mounted) return;
    await _setPhoto(bytes);
  }

  /// 预处理（后台 isolate）→ 落盘 → 已保存的卡片立即更新元数据。
  Future<void> _setPhoto(Uint8List raw) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyText = '正在处理照片...';
    });
    try {
      final processed = await compute(preprocessPhoto, raw);
      final path = await _storage.writeImage(_card.id, 'photo.jpg', processed);
      await FileImage(await _storage.imageFile(path)).evict();
      _card
        ..photoPath = path
        ..source = CharacterCardSource.photo;
      if (!_isNew) await _storage.setPhoto(_card.id, path);
      if (mounted) setState(() => _photoBytes = processed);
    } on FormatException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('保存照片失败: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    final path = _card.photoPath;
    if (_busy || path == null) return;
    setState(() {
      _busy = true;
      _busyText = '正在移除照片...';
    });
    try {
      if (!_isNew) await _storage.setPhoto(_card.id, null);
      await _storage.deleteImage(path);
      await FileImage(await _storage.imageFile(path)).evict();
      _card
        ..photoPath = null
        ..source = CharacterCardSource.manual;
      if (mounted) setState(() => _photoBytes = null);
    } catch (e) {
      _toast('移除照片失败: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recognize() async {
    final photo = _photoBytes;
    if (_busy || photo == null) return;
    setState(() {
      _busy = true;
      _busyText = '正在认识它...';
    });
    CharacterCardDraft? draft;
    try {
      final settings = await _loadSettings();
      if (!mounted) return;
      if (settings.llmApiKey.isEmpty) {
        _toast('⚠️ 请先在设置里填写 LLM API Key', error: true);
        return;
      }
      draft = await _engine.describeCharacterFromPhoto(
        settings: settings,
        photoBase64: base64Encode(photo),
        mimeType: 'image/jpeg',
      );
    } on FormatException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast(
        '识别失败: $e。如果当前文本模型不支持图片输入，请在设置里换成 Gemini、GPT-4o 等多模态模型。',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (draft == null || !mounted) return;
    await _applyDraft(draft);
  }

  /// 把识图结果填进表单；已有输入时让用户选择只补空白还是全部覆盖。
  Future<void> _applyDraft(CharacterCardDraft d) async {
    final fields = <TextEditingController, String>{
      _nameCtrl: d.name,
      _speciesCtrl: d.species,
      _appearanceCtrl: d.appearance,
      _outfitCtrl: d.defaultOutfit,
      _personalityCtrl: d.personality,
      _catchphraseCtrl: d.catchphrase,
    };
    var overwriteAll = true;
    if (fields.keys.any((c) => c.text.trim().isNotEmpty)) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('用识别结果填写表单？'),
          content: const Text('你已经填写了部分内容。可以只补空白项，也可以全部替换成识别结果。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'blank'),
              child: const Text('只填空白项'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: const Text('全部覆盖'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null || choice == 'cancel') return;
      overwriteAll = choice == 'all';
    }
    fields.forEach((ctrl, value) {
      if (overwriteAll || ctrl.text.trim().isEmpty) ctrl.text = value;
    });
    if (overwriteAll) setState(() => _kind = d.kind);
    _toast('已填入识别结果，请检查后保存');
  }

  /// 校验并保存 → 读设置 → 通道前置检查 → 生成 → 落盘并写回卡片映射。
  Future<void> _generateAnchor() async {
    if (!await _save()) return;

    final AppSettings settings;
    try {
      settings = await _loadSettings();
    } catch (e) {
      _toast('读取设置失败: $e', error: true);
      return;
    }
    if (settings.imageApiKey.isEmpty) {
      _toast('请先在设置中配置生图 API Key', error: true);
      return;
    }

    final supportsReference = _engine.supportsCharacterReference(
      type: settings.imageType,
      baseUrl: settings.imageBaseUrl,
      model: settings.imageModel,
    );
    if (!supportsReference) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('当前生图通道不支持参考图'),
          content: Text(
            _photoBytes != null
                ? '定妆图只能按文字生成，照片不会被参考，后续绘本每页可能出现外貌不一致。'
                    '建议切换到 Gemini 图像模型（如 gemini-2.5-flash-image）或腾讯混元。'
                : '定妆图只能按文字生成，后续绘本每页可能出现外貌不一致。'
                    '建议切换到 Gemini 图像模型（如 gemini-2.5-flash-image）或腾讯混元。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'settings'),
              child: const Text('去设置'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'proceed'),
              child: const Text('仍然生成'),
            ),
          ],
        ),
      );
      if (choice == 'settings' && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        return;
      }
      if (choice != 'proceed') return;
      if (!mounted) return;
    }

    final style = StyleCatalog.styles.firstWhere((s) => s.id == _styleId);
    final styleId = _styleId;
    setState(() {
      _busy = true;
      _busyText = '正在绘制 ${_card.name} 的${style.name}定妆图...';
    });
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // 桌面 / 测试环境可能没有插件实现。
    }
    try {
      final image = await _engine.generateCharacterReference(
        settings: settings,
        style: style,
        character: _card.toBookCharacter(),
        photoReferenceBase64:
            _photoBytes == null ? null : base64Encode(_photoBytes!),
      );
      if (image == null || image.isEmpty) {
        throw StateError('生图接口未返回图片');
      }
      final path = await _storage.saveAnchor(_card.id, styleId, image);
      _card.anchorImagePaths[styleId] = path;
      // 同路径覆盖写入后，清掉图片缓存里的旧位图，否则列表页和重新打开的编辑页仍显示旧图。
      await FileImage(await _storage.imageFile(path)).evict();
      _freshAnchors[styleId] = base64Decode(
        image.startsWith('data:')
            ? image.substring(image.indexOf(',') + 1)
            : image,
      );
      _toast('定妆图已保存，请检查外貌是否符合预期');
    } catch (e) {
      _toast('定妆图生成失败: $e', error: true);
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
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
              _sectionTitle('📷 照片（可选）'),
              if (_photoBytes != null) ...[
                Container(
                  height: 180,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Image.memory(
                    _photoBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, error, stack) => const Center(
                      child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_photoPicker.supportsCamera)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pickPhoto(PhotoSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('拍照'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickPhoto(PhotoSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('从相册选择'),
                  ),
                  if (_photoBytes != null)
                    TextButton.icon(
                      onPressed: _busy ? null : _removePhoto,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('移除照片'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: (_busy || _photoBytes == null) ? null : _recognize,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('让 AI 认识它'),
              ),
              const SizedBox(height: 24),
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
                '照片只保存在本机；识别和生成定妆图时会各上传一次，故事页不会上传照片。修改角色卡只影响之后新建的绘本。',
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
      child = Image.memory(
        fresh,
        fit: BoxFit.contain,
        errorBuilder: (ctx, error, stack) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.grey),
        ),
      );
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
