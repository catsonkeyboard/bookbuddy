import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/character_card.dart';
import '../services/book_engine_service.dart';
import '../services/settings_service.dart';

/// 故事创作助手：角色卡 + 一句描述 → AI 写故事；可手改，可用反馈让 AI 在现文本上重写。
/// 「用这个故事」通过 Navigator.pop 返回 [StoryDraftResult]。
class StoryComposerScreen extends StatefulWidget {
  final List<CharacterCard> cards;
  final BookEngineService? engine;
  final Future<AppSettings> Function()? loadSettings;

  const StoryComposerScreen({
    super.key,
    this.cards = const [],
    this.engine,
    this.loadSettings,
  });

  @override
  State<StoryComposerScreen> createState() => _StoryComposerScreenState();
}

class _StoryVersion {
  final String title;
  final String story;
  const _StoryVersion(this.title, this.story);
}

class _StoryComposerScreenState extends State<StoryComposerScreen> {
  static const _templates = <String, String>{
    '它从哪里来': '讲一讲{名}是从哪里来的，第一次来到这个家时发生了什么。',
    '它今天遇到了什么': '{名}今天出门遇到了一件意想不到的小事，最后开开心心地回家。',
    '它和朋友的一天': '{名}和好朋友一起度过的一天，中间闹了个小别扭又和好了。',
    '它学会了一件事': '{名}第一次尝试一件不太敢做的事，最后学会了它。',
    '它的一个小秘密': '{名}有一个藏了很久的小秘密，今天终于告诉了最好的朋友。',
  };

  late final BookEngineService _engine;
  late final Future<AppSettings> Function() _loadSettings;

  final _briefCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _storyCtrl = TextEditingController();
  final _feedbackCtrl = TextEditingController();

  bool _hasStory = false;
  bool _busy = false;
  String _busyText = '';
  final List<_StoryVersion> _history = [];

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? BookEngineService();
    _loadSettings = widget.loadSettings ?? SettingsService().loadSettings;
    for (final c in [_briefCtrl, _titleCtrl, _storyCtrl, _feedbackCtrl]) {
      c.addListener(_onAnyFieldChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [_briefCtrl, _titleCtrl, _storyCtrl, _feedbackCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 任一输入变化时触发；按钮可用状态依赖输入内容，草稿保存在下一任务接入。
  void _onAnyFieldChanged() {
    if (mounted) setState(() {});
  }

  String get _protagonistName =>
      widget.cards.isEmpty ? '它' : widget.cards.first.name;

  void _applyTemplate(String template) {
    _briefCtrl.text = template.replaceAll('{名}', _protagonistName);
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

  /// 生成或重写：成功前压入当前版本；失败时编辑框与版本栈都不变。
  /// 进入即置忙，避免读设置期间重复触发。
  Future<void> _run({required bool revise}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyText = revise ? '正在按你的建议重写故事...' : '正在为你写故事...';
    });
    try {
      final AppSettings settings;
      try {
        settings = await _loadSettings();
      } catch (e) {
        _toast('读取设置失败: $e', error: true);
        return;
      }
      if (!mounted) return;
      if (settings.llmApiKey.isEmpty) {
        _toast('⚠️ 请先在设置里填写 LLM API Key', error: true);
        return;
      }
      final result = await _engine.composeStory(
        settings: settings,
        cards: widget.cards,
        brief: _briefCtrl.text,
        currentStory: revise ? _storyCtrl.text : null,
        feedback: revise ? _feedbackCtrl.text : null,
      );
      if (!mounted) return;
      if (_hasStory) {
        _history.add(_StoryVersion(_titleCtrl.text, _storyCtrl.text));
      }
      // 控制器赋值会触发监听器里的 setState，所以放在 setState 之外，避免嵌套。
      _titleCtrl.text = result.title;
      _storyCtrl.text = result.story;
      if (revise) _feedbackCtrl.clear();
      setState(() => _hasStory = true);
    } on FormatException catch (e) {
      _toast(e.message, error: true);
    } on ArgumentError catch (e) {
      _toast('${e.message}', error: true);
    } catch (e) {
      _toast('故事生成失败: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _undo() {
    if (_history.isEmpty) return;
    final previous = _history.removeLast();
    _titleCtrl.text = previous.title;
    _storyCtrl.text = previous.story;
    setState(() {});
  }

  void _useStory() {
    Navigator.pop(
      context,
      StoryDraftResult(
        title: _titleCtrl.text.trim(),
        story: _storyCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGenerate = !_busy && _briefCtrl.text.trim().isNotEmpty;
    final canRewrite = !_busy &&
        _feedbackCtrl.text.trim().isNotEmpty &&
        _storyCtrl.text.trim().isNotEmpty;
    final canUse = !_busy && _storyCtrl.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('✨ 让 AI 按角色写故事')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(_busyText, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 16),
              ],
              _buildCastBar(),
              const SizedBox(height: 16),
              TextField(
                controller: _briefCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '你想讲一个什么样的故事？比如：豆豆和小满在雨天迷路了，最后学会互相帮助',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in _templates.entries)
                    ActionChip(
                      label: Text(entry.key),
                      onPressed: _busy ? null : () => _applyTemplate(entry.value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canGenerate ? () => _run(revise: false) : null,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('生成故事'),
              ),
              if (_hasStory) ...[
                const SizedBox(height: 24),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '故事标题',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _storyCtrl,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: '故事正文',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _feedbackCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '想改哪里？比如：结局再温暖一点 / 加一段他们吵架又和好',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: canRewrite ? () => _run(revise: true) : null,
                      icon: const Icon(Icons.edit_note),
                      label: const Text('按建议重写'),
                    ),
                    TextButton.icon(
                      onPressed: (_busy || _history.isEmpty) ? null : _undo,
                      icon: const Icon(Icons.undo),
                      label: const Text('回到上一版'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: canUse ? _useStory : null,
                  icon: const Icon(Icons.check),
                  label: const Text('用这个故事'),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCastBar() {
    if (widget.cards.isEmpty) {
      return const Text(
        '未选择角色卡，AI 会自行设计角色',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final card in widget.cards)
          Chip(
            avatar: const Icon(Icons.face_retouching_natural, size: 16),
            label: Text(card.name),
          ),
      ],
    );
  }
}
