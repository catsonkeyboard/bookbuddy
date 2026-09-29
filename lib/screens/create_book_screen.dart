import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/character_card.dart';
import '../models/fairy_tale_catalog.dart';
import '../models/style_catalog.dart';
import '../services/book_engine_service.dart';
import '../services/character_storage_service.dart';
import '../services/settings_service.dart';
import 'character_library_screen.dart';
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
  String _statusText = '';

  late final BookEngineService _engine;
  late final Future<AppSettings> Function() _loadSettings;
  late final CharacterStorageService _characterStorage;

  List<CharacterCard> _cards = [];
  bool _cardsLoading = true;
  final List<String> _selectedCardIds = [];

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

  /// 已选卡片里缺少当前画风定妆图的名字，用于提示「进入审核后会先补画」。
  List<String> get _cardsMissingAnchor => [
        for (final card in _selectedCards)
          if (!card.anchorImagePaths.containsKey(_selectedStyleId)) card.name,
      ];

  Future<List<PinnedCharacter>> _buildPinned() async {
    final pinned = <PinnedCharacter>[];
    for (final card in _selectedCards) {
      final path = card.anchorImagePaths[_selectedStyleId];
      final anchor =
          path == null ? null : await _characterStorage.readImageBase64(path);
      pinned.add(PinnedCharacter(card: card, anchorBase64: anchor));
    }
    return pinned;
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

    setState(() {
      _isProcessing = true;
      _statusText = '正在分析故事并重构绘本分镜镜头...';
    });

    try {
      final finalTitle = title.isNotEmpty
          ? title
          : (text.length > 20 ? text.substring(0, 20) : text);
      final pinned = await _buildPinned();
      final draft = await _engine.createStoryboardDraft(
        settings: settings,
        title: finalTitle,
        storyText: text.isNotEmpty ? text : finalTitle,
        pinnedCharacters: pinned,
      );

      if (draft.pages.isEmpty) {
        throw Exception('大模型未能成功生成绘本分镜，请重试');
      }

      final style = StyleCatalog.styles.firstWhere(
        (s) => s.id == _selectedStyleId,
      );

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
            characterCardIds: List.of(_selectedCardIds),
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
      if (mounted) setState(() => _isProcessing = false);
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
    final missingAnchor = _cardsMissingAnchor;
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
                      const Text(
                        '正在智能分镜与镜头场景重构中，完成后将进入分镜审核确认页面',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
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
                        Row(
                          children: [
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
                    if (missingAnchor.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '进入审核后会先为 ${missingAnchor.join('、')} 绘制该画风的定妆照',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
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
