import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/app_settings.dart';
import '../models/book.dart';
import '../models/character_card.dart';
import '../models/fairy_tale_catalog.dart';
import '../models/style_catalog.dart';
import '../services/book_engine_service.dart';
import '../services/character_storage_service.dart';
import '../services/settings_service.dart';
import 'character_library_screen.dart';
import 'story_composer_screen.dart';
import 'storyboard_review_screen.dart';
import 'tale_recommendation_dialog.dart';

class CreateBookScreen extends StatefulWidget {
  final String? initialTitle;
  final String? initialSynopsis;
  final String? initialStyleId;
  final CharacterStorageService? characterStorage;
  final BookEngineService? engine;
  final Future<AppSettings> Function()? loadSettings;

  const CreateBookScreen({
    super.key,
    this.initialTitle,
    this.initialSynopsis,
    this.initialStyleId,
    this.characterStorage,
    this.engine,
    this.loadSettings,
  });

  @override
  State<CreateBookScreen> createState() => _CreateBookScreenState();
}

class _CreateBookScreenState extends State<CreateBookScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _textCtrl;
  late String _selectedStyleId;

  bool _isProcessing = false;
  bool _generatingAnchors = false;
  String _statusText = '';

  late final BookEngineService _engine;
  late final Future<AppSettings> Function() _loadSettings;
  late final CharacterStorageService _characterStorage;

  List<CharacterCard> _cards = [];
  bool _cardsLoading = true;
  final List<String> _selectedCardIds = [];
  bool? _supportsReference;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle ?? '');
    _textCtrl = TextEditingController(text: widget.initialSynopsis ?? '');
    _selectedStyleId = widget.initialStyleId ?? 'watercolor';
    _engine = widget.engine ?? BookEngineService();
    _loadSettings = widget.loadSettings ?? SettingsService().loadSettings;
    _characterStorage = widget.characterStorage ?? CharacterStorageService();
    _loadCards();
    _probeImageChannel();
    CharacterStorageService.cardsChangedNotifier.addListener(_loadCards);
  }

  @override
  void dispose() {
    CharacterStorageService.cardsChangedNotifier.removeListener(_loadCards);
    _titleCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    try {
      final cards = await _characterStorage.loadCards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _selectedCardIds.removeWhere((id) => !cards.any((c) => c.id == id));
        _cardsLoading = false;
      });
    } catch (_) {
      // 角色库读不出来不影响写故事，只是没有卡可选。
      if (mounted) setState(() => _cardsLoading = false);
    }
  }

  /// 读一次设置，判断当前生图通道能否接收参考图；读不到就不提示。
  Future<void> _probeImageChannel() async {
    try {
      final settings = await _loadSettings();
      if (!mounted) return;
      setState(() {
        _supportsReference = _engine.supportsCharacterReference(
          type: settings.imageType,
          baseUrl: settings.imageBaseUrl,
          model: settings.imageModel,
        );
      });
    } catch (_) {
      // 设置读取失败不阻塞创建页；生成时仍按实际配置处理。
    }
  }

  void _toggleCard(CharacterCard card) {
    if (_selectedCardIds.contains(card.id)) {
      setState(() => _selectedCardIds.remove(card.id));
      return;
    }
    if (_selectedCardIds.length >= kMaxCharacterCardsPerBook) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('每本绘本最多选择 $kMaxCharacterCardsPerBook 张角色卡')),
      );
      return;
    }
    setState(() => _selectedCardIds.add(card.id));
  }

  List<CharacterCard> get _selectedCards => [
        for (final id in _selectedCardIds) _cards.firstWhere((c) => c.id == id),
      ];

  /// 已选卡片里缺少当前画风定妆图的卡片：生成分镜前会询问是否现在绘制。
  List<CharacterCard> get _cardsMissingAnchor => [
        for (final card in _selectedCards)
          if (!card.anchorImagePaths.containsKey(_selectedStyleId)) card,
      ];

  /// 询问是否为缺少当前画风定妆照的卡片现在绘制。
  /// 返回 'generate' / 'skip'；取消或关闭对话框返回 null。
  Future<String?> _askGenerateMissingAnchors(
    BookStyle style,
    List<CharacterCard> missing,
  ) {
    final names = missing.map((c) => '「${c.name}」').join('、');
    // 提示这些卡片已经有哪些画风，方便取消后改选现成的画风。
    final existing = [
      for (final card in missing)
        if (card.anchorImagePaths.isNotEmpty)
          '「${card.name}」已有的画风：${[
            for (final s in StyleCatalog.styles)
              if (card.anchorImagePaths.containsKey(s.id)) s.name,
          ].join('、')}。',
    ];
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('缺少「${style.name}」画风的定妆照'),
        content: Text(
          [
            '$names还没有「${style.name}」画风的定妆照。要现在生成吗？'
                '生成后会保存到角色卡，以后用这个画风建书可以直接使用。',
            ...existing,
            '选「暂不生成」会先生成分镜，定妆照留到审核页再画。',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'skip'),
            child: const Text('暂不生成'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'generate'),
            child: const Text('现在生成'),
          ),
        ],
      ),
    );
  }

  /// 逐张绘制 [cards] 在 [style] 画风下的定妆照并写回角色卡；卡片有照片时作为参考。
  Future<void> _generateMissingAnchors(
    AppSettings settings,
    BookStyle style,
    List<CharacterCard> cards,
  ) async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // 桌面 / 测试环境可能没有插件实现。
    }
    try {
      for (var i = 0; i < cards.length; i++) {
        final card = cards[i];
        if (mounted) {
          setState(() {
            _statusText =
                '正在绘制 ${card.name} 的${style.name}定妆照 (${i + 1}/${cards.length})...';
          });
        }
        final photoPath = card.photoPath;
        final photo = photoPath == null
            ? null
            : await _characterStorage.readImageBase64(photoPath);
        final image = await _engine.generateCharacterReference(
          settings: settings,
          style: style,
          character: card.toBookCharacter(),
          photoReferenceBase64: (photo == null || photo.isEmpty) ? null : photo,
        );
        if (image == null || image.isEmpty) {
          throw StateError('${card.name} 定妆照生成失败');
        }
        final path = await _characterStorage.saveAnchor(card.id, style.id, image);
        // 直接更新手里的卡片对象：随后的固定角色要带上这张新定妆照。
        card.anchorImagePaths[style.id] = path;
        await FileImage(await _characterStorage.imageFile(path)).evict();
      }
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  Future<List<PinnedCharacter>> _buildPinned(List<CharacterCard> cards) async {
    final pinned = <PinnedCharacter>[];
    for (final card in cards) {
      final path = card.anchorImagePaths[_selectedStyleId];
      final anchor =
          path == null ? null : await _characterStorage.readImageBase64(path);
      final photoPath = card.photoPath;
      final photo = photoPath == null
          ? null
          : await _characterStorage.readImageBase64(photoPath);
      pinned.add(
        PinnedCharacter(
          card: card,
          anchorBase64: (anchor == null || anchor.isEmpty) ? null : anchor,
          photoBase64: (photo == null || photo.isEmpty) ? null : photo,
        ),
      );
    }
    return pinned;
  }

  /// 打开故事助手；返回结果后回填标题与正文，正文已有内容时先确认覆盖。
  Future<void> _openStoryComposer() async {
    final result = await Navigator.push<StoryDraftResult>(
      context,
      MaterialPageRoute(
        builder: (_) => StoryComposerScreen(
          cards: _selectedCards,
          engine: _engine,
          loadSettings: _loadSettings,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (_textCtrl.text.trim().isNotEmpty) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('用生成的故事替换当前正文？'),
          content: const Text('当前故事正文会被覆盖，标题也会更新。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('替换'),
            ),
          ],
        ),
      );
      if (overwrite != true || !mounted) return;
    }
    setState(() {
      if (result.title.isNotEmpty) _titleCtrl.text = result.title;
      _textCtrl.text = result.story;
    });
  }

  Future<void> _startGenerate() async {
    final title = _titleCtrl.text.trim();
    final text = _textCtrl.text.trim();

    if (title.isEmpty && text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入故事标题或故事正文')));
      return;
    }

    final settings = await _loadSettings();
    if (!mounted) return;
    if (settings.llmApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ 请先点击右上角设置图标，填写 LLM API Key！'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final style = StyleCatalog.styles.firstWhere(
      (s) => s.id == _selectedStyleId,
    );
    // 固定这一刻选中的卡片：后面补画定妆照会触发角色库刷新，不能再依赖 _cards。
    final cards = _selectedCards;
    final missing = [
      for (final card in cards)
        if (!card.anchorImagePaths.containsKey(style.id)) card,
    ];
    var generateAnchors = false;
    // 通道用不上定妆照或还没配生图密钥时不问，沿用页面上已有的提示和审核页的检查。
    if (missing.isNotEmpty &&
        settings.imageApiKey.isNotEmpty &&
        _engine.supportsCharacterReference(
          type: settings.imageType,
          baseUrl: settings.imageBaseUrl,
          model: settings.imageModel,
        )) {
      final choice = await _askGenerateMissingAnchors(style, missing);
      if (choice == null || !mounted) return;
      generateAnchors = choice == 'generate';
    }

    setState(() {
      _isProcessing = true;
      _generatingAnchors = generateAnchors;
      _statusText = '正在分析故事并重构绘本分镜镜头...';
    });

    try {
      if (generateAnchors) {
        try {
          await _generateMissingAnchors(settings, style, missing);
        } catch (e) {
          // 已经画好的定妆照留在角色卡里；停在创建页，可以重试或改选「暂不生成」。
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('定妆照生成失败：$e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        if (!mounted) return;
        setState(() {
          _generatingAnchors = false;
          _statusText = '正在分析故事并重构绘本分镜镜头...';
        });
      }
      final finalTitle = title.isNotEmpty
          ? title
          : (text.length > 20 ? text.substring(0, 20) : text);
      final pinned = await _buildPinned(cards);
      final draft = await _engine.createStoryboardDraft(
        settings: settings,
        title: finalTitle,
        storyText: text.isNotEmpty ? text : finalTitle,
        pinnedCharacters: pinned,
      );

      if (draft.pages.isEmpty) {
        throw Exception('大模型未能成功生成绘本分镜，请重试');
      }

      if (!mounted) return;
      // 成功获得分镜后，进入分镜审核确认页面（支持编辑正文、画面动作、微表情和开关插画）
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoryboardReviewScreen(
            title: finalTitle,
            style: style,
            initialPages: draft.pages,
            initialCharacters: draft.characters,
            settings: settings,
            pinnedCharacters: pinned,
            characterCardIds: [for (final card in cards) card.id],
          ),
        ),
      );
    } on StateError catch (e) {
      // 对账失败：角色卡没有出场等，原文提示，停留在创建页。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } on ArgumentError catch (e) {
      // 角色卡数量或重名等前置校验失败，原文提示，停留在创建页。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${e.message}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _generatingAnchors = false;
        });
      }
    }
  }

  Widget _buildCardPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '👥 选择角色卡（可选，最多 $kMaxCharacterCardsPerBook 张）',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_cardsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_cards.isEmpty)
          Row(
            children: [
              const Text(
                '还没有角色卡。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CharacterLibraryScreen(
                        storage: _characterStorage,
                      ),
                    ),
                  );
                },
                child: const Text('去创建角色'),
              ),
            ],
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final card in _cards)
                FilterChip(
                  label: Text(card.name),
                  avatar: const Icon(Icons.face_retouching_natural, size: 16),
                  selected: _selectedCardIds.contains(card.id),
                  onSelected: (_) => _toggleCard(card),
                ),
            ],
          ),
          if (_selectedCardIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final card in _selectedCards)
              Text(
                card.catchphrase.trim().isEmpty
                    ? card.name
                    : '${card.name} · ${card.catchphrase}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFD8A24A)),
              ),
            const SizedBox(height: 4),
            const Text(
              '在故事里直接用名字称呼他们',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final missingAnchor = [for (final card in _cardsMissingAnchor) card.name];
    final withAnchor = [
      for (final card in _selectedCards)
        if (card.anchorImagePaths.containsKey(_selectedStyleId)) card.name,
    ];
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
            label: const Text(
              '挑选经典童话',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              final selected = await showDialog<FairyTaleItem?>(
                context: context,
                builder: (_) => const TaleRecommendationDialog(),
              );
              if (selected != null && mounted) {
                setState(() {
                  _titleCtrl.text = selected.title;
                  _textCtrl.text = selected.synopsis;
                  _selectedStyleId = selected.recommendedStyle;
                });
              }
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
                      Text(
                        _generatingAnchors
                            ? '定妆照会保存到角色卡，画完后继续生成分镜'
                            : '正在智能分镜与镜头场景重构中，完成后将进入分镜审核确认页面',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
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
                    _buildCardPicker(),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📖 故事正文：',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Flexible(
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFFD8A24A),
                              ),
                              icon: const Text('✨', style: TextStyle(fontSize: 14)),
                              label: const Text(
                                '让 AI 按角色写故事',
                                style: TextStyle(fontSize: 12),
                              ),
                              onPressed: _isProcessing ? null : _openStoryComposer,
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.paste_rounded, size: 16),
                              label: const Text(
                                '从剪贴板粘贴',
                                style: TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                final data = await Clipboard.getData(
                                  Clipboard.kTextPlain,
                                );
                                if (data != null &&
                                    data.text != null &&
                                    data.text!.isNotEmpty) {
                                  setState(() {
                                    _textCtrl.text = data.text!.trim();
                                  });
                                }
                              },
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.clear, size: 16),
                              label: const Text(
                                '清空',
                                style: TextStyle(fontSize: 12),
                              ),
                              onPressed: () => _textCtrl.clear(),
                            ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _textCtrl,
                      maxLines: 6,
                      enableInteractiveSelection: true,
                      decoration: const InputDecoration(
                        hintText: '可直接粘贴故事全文；若留空仅填书名，AI 将自动构思并续写完整童话...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '🎨 选择绘本画风',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: StyleCatalog.styles.map((st) {
                        final isSel = st.id == _selectedStyleId;
                        return ChoiceChip(
                          label: Text(st.name),
                          selected: isSel,
                          onSelected: (_) =>
                              setState(() => _selectedStyleId = st.id),
                        );
                      }).toList(),
                    ),
                    if (_selectedCardIds.isNotEmpty && _supportsReference == false) ...[
                      const SizedBox(height: 8),
                      const Text(
                        '当前生图通道不支持参考图，角色卡的定妆图不会被使用，每页外貌可能不一致。建议在设置里切换到 Gemini 图像模型或腾讯混元。',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ] else if (_selectedCardIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      if (withAnchor.isNotEmpty)
                        Text(
                          '将直接使用 ${withAnchor.join('、')} 已有的该画风定妆照',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      if (missingAnchor.isNotEmpty)
                        Text(
                          '${missingAnchor.join('、')} 还没有该画风的定妆照，生成分镜前会询问是否现在绘制',
                          style: const TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                    ],
                    const SizedBox(height: 36),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _startGenerate,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text(
                        '🎬 分析故事并生成分镜 (进入审核)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
