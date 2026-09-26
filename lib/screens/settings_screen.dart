import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/app_settings.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _service = SettingsService();
  final Uuid _uuid = const Uuid();

  late AppSettings _settings;
  bool _loading = true;

  // 备用生图 Controllers
  late TextEditingController _fbImgUrlCtrl;
  late TextEditingController _fbImgKeyCtrl;
  late TextEditingController _fbImgModelCtrl;

  // MiniMax TTS Controllers
  late TextEditingController _minimaxKeyCtrl;
  late TextEditingController _minimaxGroupIdCtrl;
  late TextEditingController _minimaxModelCtrl;
  late TextEditingController _minimaxVoiceCtrl;
  double _ttsSpeed = 0.85;

  bool _obscureFbImgKey = true;
  bool _obscureTtsKey = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _settings = await _service.loadSettings();

    _fbImgUrlCtrl = TextEditingController(text: _settings.fallbackImageBaseUrl);
    _fbImgKeyCtrl = TextEditingController(text: _settings.fallbackImageApiKey);
    _fbImgModelCtrl = TextEditingController(text: _settings.fallbackImageModel);

    _minimaxKeyCtrl = TextEditingController(text: _settings.minimaxApiKey);
    _minimaxGroupIdCtrl = TextEditingController(text: _settings.minimaxGroupId);
    _minimaxModelCtrl = TextEditingController(text: _settings.minimaxModel);
    _minimaxVoiceCtrl = TextEditingController(text: _settings.minimaxVoiceId);
    _ttsSpeed = _settings.minimaxSpeed;

    setState(() {
      _loading = false;
    });
  }

  @override
  void dispose() {
    _fbImgUrlCtrl.dispose();
    _fbImgKeyCtrl.dispose();
    _fbImgModelCtrl.dispose();
    _minimaxKeyCtrl.dispose();
    _minimaxGroupIdCtrl.dispose();
    _minimaxModelCtrl.dispose();
    _minimaxVoiceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _settings.fallbackImageBaseUrl = _fbImgUrlCtrl.text.trim();
    _settings.fallbackImageApiKey = _fbImgKeyCtrl.text.trim();
    _settings.fallbackImageModel = _fbImgModelCtrl.text.trim();

    _settings.minimaxApiKey = _minimaxKeyCtrl.text.trim();
    _settings.minimaxGroupId = _minimaxGroupIdCtrl.text.trim();
    _settings.minimaxModel = _minimaxModelCtrl.text.trim().isNotEmpty
        ? _minimaxModelCtrl.text.trim()
        : 'speech-01-turbo';
    _settings.minimaxVoiceId = _minimaxVoiceCtrl.text.trim().isNotEmpty
        ? _minimaxVoiceCtrl.text.trim()
        : 'audiobook_female_1';
    _settings.minimaxSpeed = _ttsSpeed;

    await _service.saveSettings(_settings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ 模型与接口配置已成功保存并立即生效！'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _pasteTo(TextEditingController ctrl, String fieldLabel) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      ctrl.text = data.text!.trim();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📋 已将剪贴板内容填入 $fieldLabel'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ 剪贴板为空或无可识别的文本内容'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _copyFrom(TextEditingController ctrl, String fieldLabel) async {
    final text = ctrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ $fieldLabel 为空，无可复制内容'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📄 已将 $fieldLabel 复制到剪贴板！'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // --- LLM 多配置管理 ---

  void _activateLlmProfile(String id) {
    setState(() {
      _settings.activeLlmProfileId = id;
    });
    final active = _settings.activeLlmProfile;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⚡ 已启用 LLM 厂商配置：${active.name} (${active.model})'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _deleteLlmProfile(String id) {
    if (_settings.llmProfiles.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ 必须至少保留一个 LLM 配置，无法全部删除！'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final p = _settings.llmProfiles.firstWhere((x) => x.id == id);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除配置？'),
        content: Text('确定要删除「${p.name}」吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _settings.llmProfiles.removeWhere((x) => x.id == id);
                if (_settings.activeLlmProfileId == id) {
                  _settings.activeLlmProfileId = _settings.llmProfiles.first.id;
                }
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('🗑️ 已删除配置：${p.name}')),
              );
            },
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditLlmDialog({LlmProfile? existing}) async {
    final isNew = existing == null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String providerType = existing?.providerType ?? 'openai';
    final urlCtrl = TextEditingController(
      text: existing?.baseUrl ?? 'https://api.openai.com/v1',
    );
    final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    final modelCtrl = TextEditingController(text: existing?.model ?? 'gpt-4o-mini');
    bool obscureKey = true;
    bool setAsActive = isNew;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          void onProviderChanged(String? type) {
            if (type == null) return;
            setDlgState(() {
              providerType = type;
              if (type == 'gemini') {
                if (urlCtrl.text.isEmpty || urlCtrl.text.contains('openai') || urlCtrl.text.contains('anthropic')) {
                  urlCtrl.text = 'https://generativelanguage.googleapis.com';
                }
                if (modelCtrl.text.isEmpty || modelCtrl.text.contains('gpt') || modelCtrl.text.contains('claude')) {
                  modelCtrl.text = 'gemini-2.5-flash';
                }
              } else if (type == 'anthropic') {
                if (urlCtrl.text.isEmpty || urlCtrl.text.contains('google') || urlCtrl.text.contains('openai')) {
                  urlCtrl.text = 'https://api.anthropic.com';
                }
                if (modelCtrl.text.isEmpty || modelCtrl.text.contains('gemini') || modelCtrl.text.contains('gpt')) {
                  modelCtrl.text = 'claude-3-5-sonnet-20241022';
                }
              } else {
                if (urlCtrl.text.isEmpty || urlCtrl.text.contains('google') || urlCtrl.text.contains('anthropic')) {
                  urlCtrl.text = 'https://api.openai.com/v1';
                }
                if (modelCtrl.text.isEmpty || modelCtrl.text.contains('gemini') || modelCtrl.text.contains('claude')) {
                  modelCtrl.text = 'gpt-4o-mini';
                }
              }
            });
          }

          return AlertDialog(
            title: Text(isNew ? '➕ 添加新的 LLM 配置' : '✏️ 编辑 LLM 配置'),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 快捷预定义 LLM 模版选择器
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.bolt, size: 16, color: Colors.amber),
                              SizedBox(width: 4),
                              Text(
                                '快捷预定义 LLM 接口 (点击自动填入地址与模型，只需输入 Key)：',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ActionChip(
                                avatar: const Icon(Icons.psychology, size: 14),
                                label: const Text('DeepSeek 官方'),
                                onPressed: () {
                                  setDlgState(() {
                                    nameCtrl.text = 'DeepSeek 官方 API';
                                    providerType = 'openai';
                                    urlCtrl.text = 'https://api.deepseek.com/v1';
                                    modelCtrl.text = 'deepseek-chat';
                                  });
                                },
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.psychology, size: 14),
                                label: const Text('智谱 GLM 文本'),
                                onPressed: () {
                                  setDlgState(() {
                                    nameCtrl.text = '智谱 GLM (GLM-4-Plus)';
                                    providerType = 'openai';
                                    urlCtrl.text = 'https://open.bigmodel.cn/api/paas/v4';
                                    modelCtrl.text = 'glm-4-plus';
                                  });
                                },
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.psychology, size: 14),
                                label: const Text('Google Gemini'),
                                onPressed: () {
                                  setDlgState(() {
                                    nameCtrl.text = 'Google Gemini (官方推荐)';
                                    providerType = 'gemini';
                                    urlCtrl.text = 'https://generativelanguage.googleapis.com';
                                    modelCtrl.text = 'gemini-2.5-flash';
                                  });
                                },
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.psychology, size: 14),
                                label: const Text('Claude 3.5'),
                                onPressed: () {
                                  setDlgState(() {
                                    nameCtrl.text = 'Anthropic Claude (官方原生)';
                                    providerType = 'anthropic';
                                    urlCtrl.text = 'https://api.anthropic.com';
                                    modelCtrl.text = 'claude-3-5-sonnet-20241022';
                                  });
                                },
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.psychology, size: 14),
                                label: const Text('OpenAI GPT-4o'),
                                onPressed: () {
                                  setDlgState(() {
                                    nameCtrl.text = 'OpenAI 协议 (GPT-4o-mini)';
                                    providerType = 'openai';
                                    urlCtrl.text = 'https://api.openai.com/v1';
                                    modelCtrl.text = 'gpt-4o-mini';
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '配置名称 (如: DeepSeek 官方 / Gemini Pro)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: providerType,
                      decoration: const InputDecoration(
                        labelText: '接口协议规范',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'gemini',
                          child: Text('Google Gemini (官方原生推荐)'),
                        ),
                        DropdownMenuItem(
                          value: 'openai',
                          child: Text('OpenAI 兼容协议 (DeepSeek/智谱/Moonshot/自建网关)'),
                        ),
                        DropdownMenuItem(
                          value: 'anthropic',
                          child: Text('Anthropic Claude (官方原生)'),
                        ),
                      ],
                      onChanged: onProviderChanged,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: urlCtrl,
                      decoration: InputDecoration(
                        labelText: 'API Base URL',
                        helperText: 'Gemini可填原生地址；OpenAI兼容协议填到/v1或网关地址',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: '从剪贴板粘贴 URL',
                          icon: const Icon(Icons.paste_rounded),
                          onPressed: () => _pasteTo(urlCtrl, 'API Base URL'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: keyCtrl,
                      obscureText: obscureKey,
                      decoration: InputDecoration(
                        labelText: 'API Key (密钥)',
                        border: const OutlineInputBorder(),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: obscureKey ? '显示明文' : '隐藏密文',
                              icon: Icon(obscureKey ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setDlgState(() => obscureKey = !obscureKey),
                            ),
                            IconButton(
                              tooltip: '从剪贴板粘贴',
                              icon: const Icon(Icons.paste_rounded),
                              onPressed: () => _pasteTo(keyCtrl, 'API Key'),
                            ),
                            IconButton(
                              tooltip: '复制完整内容',
                              icon: const Icon(Icons.copy_rounded),
                              onPressed: () => _copyFrom(keyCtrl, 'API Key'),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: modelCtrl,
                      decoration: InputDecoration(
                        labelText: '模型名称 (Model)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: '从剪贴板粘贴模型名',
                          icon: const Icon(Icons.paste_rounded),
                          onPressed: () => _pasteTo(modelCtrl, '模型名称'),
                        ),
                      ),
                    ),
                    if (isNew) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: const Text('保存后立即启用此配置'),
                        value: setAsActive,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setDlgState(() => setAsActive = v ?? false),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('⚠️ 请输入配置名称！')),
                    );
                    return;
                  }

                  final targetId = existing?.id ?? 'llm_${_uuid.v4().substring(0, 8)}';
                  final profile = LlmProfile(
                    id: targetId,
                    name: name,
                    providerType: providerType,
                    baseUrl: urlCtrl.text.trim(),
                    apiKey: keyCtrl.text.trim(),
                    model: modelCtrl.text.trim(),
                  );

                  setState(() {
                    if (isNew) {
                      _settings.llmProfiles.add(profile);
                      if (setAsActive) {
                        _settings.activeLlmProfileId = profile.id;
                      }
                    } else {
                      final idx = _settings.llmProfiles.indexWhere((x) => x.id == targetId);
                      if (idx != -1) {
                        _settings.llmProfiles[idx] = profile;
                      }
                    }
                  });

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('💾 LLM 配置「$name」已更新！')),
                  );
                },
                child: const Text('保存配置'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- 生图多配置管理 ---

  void _activateImageProfile(String id) {
    setState(() {
      _settings.activeImageProfileId = id;
    });
    final active = _settings.activeImageProfile;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎨 已启用生图模型配置：${active.name} (${active.model})'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _deleteImageProfile(String id) {
    if (_settings.imageProfiles.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ 必须至少保留一个生图配置，无法全部删除！'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final p = _settings.imageProfiles.firstWhere((x) => x.id == id);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除生图配置？'),
        content: Text('确定要删除「${p.name}」吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _settings.imageProfiles.removeWhere((x) => x.id == id);
                if (_settings.activeImageProfileId == id) {
                  _settings.activeImageProfileId = _settings.imageProfiles.first.id;
                }
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('🗑️ 已删除生图配置：${p.name}')),
              );
            },
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditImageDialog({ImageProfile? existing}) async {
    final isNew = existing == null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String providerType = existing?.providerType ?? 'openai';
    final urlCtrl = TextEditingController(
      text: existing?.baseUrl ?? 'https://api.openai.com/v1',
    );
    final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    final modelCtrl = TextEditingController(text: existing?.model ?? 'dall-e-3');
    bool obscureKey = true;
    bool setAsActive = isNew;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          void onProviderChanged(String? type) {
            if (type == null) return;
            setDlgState(() {
              providerType = type;
              if (type == 'gemini') {
                if (urlCtrl.text.isEmpty || urlCtrl.text.contains('openai') || urlCtrl.text.contains('tokenhub')) {
                  urlCtrl.text = 'https://generativelanguage.googleapis.com';
                }
                if (modelCtrl.text.isEmpty || modelCtrl.text.contains('dall-e') || modelCtrl.text.contains('cogview') || modelCtrl.text.contains('hy-image')) {
                  modelCtrl.text = 'imagen-3.0-generate-002';
                }
              } else if (type == 'tokenhub') {
                urlCtrl.text = 'https://tokenhub.tencentmaas.com/v1/wand/hunyuan-image/v35-generation';
                modelCtrl.text = 'hy-image-v3.5-preview';
              } else {
                if (urlCtrl.text.isEmpty || urlCtrl.text.contains('google') || urlCtrl.text.contains('tokenhub')) {
                  urlCtrl.text = 'https://api.openai.com/v1';
                }
                if (modelCtrl.text.isEmpty || modelCtrl.text.contains('imagen') || modelCtrl.text.contains('hy-image')) {
                  modelCtrl.text = 'dall-e-3';
                }
              }
            });
          }

          return AlertDialog(
            title: Text(isNew ? '➕ 添加新的生图模型配置' : '✏️ 编辑生图模型配置'),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 快捷预定义生图模版选择器
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.bolt, size: 16, color: Colors.amber),
                              SizedBox(width: 4),
                              Text(
                                '快捷预定义生图接口 (点击自动填好地址与规范，只需输入 Key)：',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ImagePreset.presets.map((preset) {
                              return ActionChip(
                                avatar: const Icon(Icons.auto_awesome, size: 14),
                                label: Text(preset.label),
                                onPressed: () {
                                  setDlgState(() {
                                    nameCtrl.text = preset.name;
                                    providerType = preset.providerType;
                                    urlCtrl.text = preset.baseUrl;
                                    modelCtrl.text = preset.defaultModel;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('⚡ 已填入「${preset.label}」预定义配置！请填写 API Key。'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '💡 支持智谱 GLM (glm-image)、腾讯 TokenHub 混元 3.5、Google Imagen 与 DALL-E，图片自动下载缓存。',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '配置名称 (如: 智谱 GLM / 腾讯 TokenHub / Imagen 3)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: providerType,
                      decoration: const InputDecoration(
                        labelText: '生图接口协议',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'tokenhub',
                          child: Text('腾讯 TokenHub 协议 (混元 3.5 官方接口)'),
                        ),
                        DropdownMenuItem(
                          value: 'gemini',
                          child: Text('Google Imagen 3 / Gemini 多模态原生'),
                        ),
                        DropdownMenuItem(
                          value: 'openai',
                          child: Text('OpenAI 兼容协议 (DALL-E / 智谱 CogView / 网关)'),
                        ),
                      ],
                      onChanged: onProviderChanged,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: urlCtrl,
                      decoration: InputDecoration(
                        labelText: '生图 API Base URL',
                        helperText: 'Google 原生填默认地址；OpenAI 兼容填网关/v1地址',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: '从剪贴板粘贴 URL',
                          icon: const Icon(Icons.paste_rounded),
                          onPressed: () => _pasteTo(urlCtrl, '生图 API Base URL'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: keyCtrl,
                      obscureText: obscureKey,
                      decoration: InputDecoration(
                        labelText: '生图 API Key (密钥)',
                        border: const OutlineInputBorder(),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: obscureKey ? '显示明文' : '隐藏密文',
                              icon: Icon(obscureKey ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setDlgState(() => obscureKey = !obscureKey),
                            ),
                            IconButton(
                              tooltip: '从剪贴板粘贴',
                              icon: const Icon(Icons.paste_rounded),
                              onPressed: () => _pasteTo(keyCtrl, '生图 API Key'),
                            ),
                            IconButton(
                              tooltip: '复制完整内容',
                              icon: const Icon(Icons.copy_rounded),
                              onPressed: () => _copyFrom(keyCtrl, '生图 API Key'),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: modelCtrl,
                      decoration: InputDecoration(
                        labelText: '生图模型名称 (如 imagen-3.0-generate-002, dall-e-3)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: '从剪贴板粘贴模型名',
                          icon: const Icon(Icons.paste_rounded),
                          onPressed: () => _pasteTo(modelCtrl, '生图模型名称'),
                        ),
                      ),
                    ),
                    if (isNew) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: const Text('保存后立即启用此生图配置'),
                        value: setAsActive,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setDlgState(() => setAsActive = v ?? false),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('⚠️ 请输入配置名称！')),
                    );
                    return;
                  }

                  final targetId = existing?.id ?? 'img_${_uuid.v4().substring(0, 8)}';
                  final profile = ImageProfile(
                    id: targetId,
                    name: name,
                    providerType: providerType,
                    baseUrl: urlCtrl.text.trim(),
                    apiKey: keyCtrl.text.trim(),
                    model: modelCtrl.text.trim(),
                  );

                  setState(() {
                    if (isNew) {
                      _settings.imageProfiles.add(profile);
                      if (setAsActive) {
                        _settings.activeImageProfileId = profile.id;
                      }
                    } else {
                      final idx = _settings.imageProfiles.indexWhere((x) => x.id == targetId);
                      if (idx != -1) {
                        _settings.imageProfiles[idx] = profile;
                      }
                    }
                  });

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('💾 生图配置「$name」已更新！')),
                  );
                },
                child: const Text('保存配置'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKeyField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggleObscure,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      enableInteractiveSelection: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: obscure ? '显示明文' : '隐藏密文',
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: onToggleObscure,
            ),
            IconButton(
              tooltip: '从剪贴板粘贴',
              icon: const Icon(Icons.paste_rounded),
              onPressed: () => _pasteTo(controller, label),
            ),
            IconButton(
              tooltip: '复制完整内容',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => _copyFrom(controller, label),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlField({
    required TextEditingController controller,
    required String label,
    required String helper,
  }) {
    return TextFormField(
      controller: controller,
      enableInteractiveSelection: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: '从剪贴板粘贴 URL',
          icon: const Icon(Icons.paste_rounded),
          onPressed: () => _pasteTo(controller, label),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final activeLlm = _settings.activeLlmProfile;
    final activeImg = _settings.activeImageProfile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️ 模型与接口配置'),
        actions: [
          IconButton(
            tooltip: '保存并应用所有配置',
            icon: const Icon(Icons.check),
            onPressed: _save,
          )
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            children: [
              // 1. LLM 配置多选项卡片
              _buildSectionCard(
                title: '🧠 故事文本模型 (LLM Multi-Provider)',
                subtitle: '配置多个 LLM 厂商地址与密钥，可在已配置列表中自由切换当前生效模型',
                icon: Icons.psychology,
                badge: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        '当前生效: ${activeLlm.name}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                children: [
                  ..._settings.llmProfiles.map((p) {
                    final isActive = p.id == _settings.activeLlmProfileId;
                    return Card(
                      elevation: isActive ? 2 : 0,
                      color: isActive
                          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                          : Theme.of(context).cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isActive
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).dividerColor.withOpacity(0.4),
                          width: isActive ? 1.8 : 1.0,
                        ),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Radio<String>(
                              value: p.id,
                              groupValue: _settings.activeLlmProfileId,
                              onChanged: (id) {
                                if (id != null) _activateLlmProfile(id);
                              },
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () => _activateLlmProfile(p.id),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            p.name,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: isActive
                                                  ? Theme.of(context).colorScheme.primary
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            p.providerType.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          ),
                                          if (isActive) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                '已启用',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '模型: ${p.model.isNotEmpty ? p.model : "(未指定)"}  •  接口地址: ${p.baseUrl.isNotEmpty ? p.baseUrl : "(默认)"}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.outline,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        p.apiKey.isNotEmpty
                                            ? '密钥已配置 (${p.apiKey.length > 8 ? "${p.apiKey.substring(0, 4)}••••${p.apiKey.substring(p.apiKey.length - 4)}" : "••••"})'
                                            : '⚠️ 未配置 API Key',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: p.apiKey.isNotEmpty ? Colors.grey : Colors.amber.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isActive)
                                  TextButton.icon(
                                    icon: const Icon(Icons.power_settings_new, size: 16),
                                    label: const Text('启用'),
                                    onPressed: () => _activateLlmProfile(p.id),
                                  ),
                                IconButton(
                                  tooltip: '编辑此配置',
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _showEditLlmDialog(existing: p),
                                ),
                                IconButton(
                                  tooltip: '删除此配置',
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () => _deleteLlmProfile(p.id),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('➕ 添加新的 LLM 模型配置 (如自建网关/DeepSeek)'),
                    onPressed: () => _showEditLlmDialog(),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 2. 生图模型配置多选项卡片
              _buildSectionCard(
                title: '🎨 主生图模型 (Image Multi-Provider)',
                subtitle: '配置多个生图引擎接口，自由切换全书插画与定妆照的主力画师',
                icon: Icons.palette,
                badge: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        '当前生效: ${activeImg.name}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                children: [
                  ..._settings.imageProfiles.map((p) {
                    final isActive = p.id == _settings.activeImageProfileId;
                    return Card(
                      elevation: isActive ? 2 : 0,
                      color: isActive
                          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                          : Theme.of(context).cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isActive
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).dividerColor.withOpacity(0.4),
                          width: isActive ? 1.8 : 1.0,
                        ),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Radio<String>(
                              value: p.id,
                              groupValue: _settings.activeImageProfileId,
                              onChanged: (id) {
                                if (id != null) _activateImageProfile(id);
                              },
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () => _activateImageProfile(p.id),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            p.name,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: isActive
                                                  ? Theme.of(context).colorScheme.primary
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            p.providerType.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          ),
                                          if (isActive) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                '已启用',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '模型: ${p.model.isNotEmpty ? p.model : "(未指定)"}  •  接口地址: ${p.baseUrl.isNotEmpty ? p.baseUrl : "(默认)"}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.outline,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        p.apiKey.isNotEmpty
                                            ? '密钥已配置 (${p.apiKey.length > 8 ? "${p.apiKey.substring(0, 4)}••••${p.apiKey.substring(p.apiKey.length - 4)}" : "••••"})'
                                            : '⚠️ 未配置 API Key',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: p.apiKey.isNotEmpty ? Colors.grey : Colors.amber.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isActive)
                                  TextButton.icon(
                                    icon: const Icon(Icons.power_settings_new, size: 16),
                                    label: const Text('启用'),
                                    onPressed: () => _activateImageProfile(p.id),
                                  ),
                                IconButton(
                                  tooltip: '编辑此配置',
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _showEditImageDialog(existing: p),
                                ),
                                IconButton(
                                  tooltip: '删除此配置',
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () => _deleteImageProfile(p.id),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: const Text('➕ 添加新的生图模型配置 (如 CogView / Flux / 网关)'),
                    onPressed: () => _showEditImageDialog(),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 3. 备用生图接口 (Failover)
              _buildSectionCard(
                title: '🛡️ 备用生图通道 (Failover)',
                subtitle: '当主力通道遇到 429/503/限流时，自动无缝降级切换至此备用通道',
                icon: Icons.alt_route,
                children: [
                  SwitchListTile(
                    title: const Text('启用多通道自动降级'),
                    subtitle: const Text('主通道算力耗尽或故障时，自动调用备选接口保证成书'),
                    value: _settings.enableImageFallback,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setState(() {
                        _settings.enableImageFallback = val;
                      });
                    },
                  ),
                  if (_settings.enableImageFallback) ...[
                    const Divider(),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _settings.fallbackImageType,
                      decoration: const InputDecoration(
                        labelText: '备用通道协议',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'tokenhub',
                          child: Text('腾讯 TokenHub 混元 3.5'),
                        ),
                        DropdownMenuItem(
                          value: 'openai',
                          child: Text('OpenAI 兼容 (如智谱/其他网关)'),
                        ),
                        DropdownMenuItem(
                          value: 'gemini',
                          child: Text('Google 官方原生'),
                        ),
                      ],
                      onChanged: (type) {
                        if (type != null) {
                          setState(() {
                            _settings.fallbackImageType = type;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildUrlField(
                      controller: _fbImgUrlCtrl,
                      label: '备用 API Base URL',
                      helper: '网关地址',
                    ),
                    const SizedBox(height: 16),
                    _buildKeyField(
                      controller: _fbImgKeyCtrl,
                      label: '备用生图 API Key',
                      obscure: _obscureFbImgKey,
                      onToggleObscure: () {
                        setState(() {
                          _obscureFbImgKey = !_obscureFbImgKey;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _fbImgModelCtrl,
                      enableInteractiveSelection: true,
                      decoration: InputDecoration(
                        labelText: '备用生图模型名称',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: '从剪贴板粘贴模型名',
                          icon: const Icon(Icons.paste_rounded),
                          onPressed: () => _pasteTo(_fbImgModelCtrl, '备用生图模型名称'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 24),

              // 4. TTS 语音朗读 (MiniMax)
              _buildSectionCard(
                title: '🎙️ 绘本温柔语音朗读 (TTS - MiniMax)',
                subtitle: '配置 MiniMax 故事语音大模型，为绘本每页生成温柔温润的睡前朗读声',
                icon: Icons.record_voice_over_rounded,
                children: [
                  SwitchListTile(
                    title: const Text('启用语音伴读功能'),
                    subtitle: const Text('开启后阅读器支持一键播放、自动朗读与本地永久保存'),
                    value: _settings.ttsEnabled,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setState(() {
                        _settings.ttsEnabled = val;
                      });
                    },
                  ),
                  if (_settings.ttsEnabled) ...[
                    const SizedBox(height: 10),
                    _buildKeyField(
                      controller: _minimaxKeyCtrl,
                      label: 'MiniMax API Key',
                      obscure: _obscureTtsKey,
                      onToggleObscure: () {
                        setState(() {
                          _obscureTtsKey = !_obscureTtsKey;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _minimaxGroupIdCtrl,
                      enableInteractiveSelection: true,
                      decoration: InputDecoration(
                        labelText: 'MiniMax Group ID (组织ID)',
                        helperText: '在 MiniMax 开放平台账户中心/API Keys 页面可查看',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: '从剪贴板粘贴 Group ID',
                          icon: const Icon(Icons.paste_rounded),
                          onPressed: () => _pasteTo(_minimaxGroupIdCtrl, 'Group ID'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: ['speech-01-turbo', 'speech-02-turbo'].contains(_minimaxModelCtrl.text)
                          ? _minimaxModelCtrl.text
                          : 'speech-01-turbo',
                      decoration: const InputDecoration(
                        labelText: '语音模型版本',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'speech-01-turbo',
                          child: Text('speech-01-turbo (故事朗读推荐 / 稳定温和)'),
                        ),
                        DropdownMenuItem(
                          value: 'speech-02-turbo',
                          child: Text('speech-02-turbo (次时代拟真 / 情绪丰富)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _minimaxModelCtrl.text = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: [
                        'audiobook_female_1',
                        'audiobook_female_2',
                        'female-shaonv',
                        'female-yujie',
                        'presenter_female',
                      ].contains(_minimaxVoiceCtrl.text)
                          ? _minimaxVoiceCtrl.text
                          : 'audiobook_female_1',
                      decoration: const InputDecoration(
                        labelText: '朗读音色预设',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'audiobook_female_1',
                          child: Text('治愈暖心姐姐 (audiobook_female_1，儿童绘本首推)'),
                        ),
                        DropdownMenuItem(
                          value: 'audiobook_female_2',
                          child: Text('温柔小姨/故事妈妈 (audiobook_female_2，睡前轻柔)'),
                        ),
                        DropdownMenuItem(
                          value: 'female-shaonv',
                          child: Text('青涩甜美少女 (female-shaonv，轻快生动)'),
                        ),
                        DropdownMenuItem(
                          value: 'female-yujie',
                          child: Text('知性温润御姐 (female-yujie)'),
                        ),
                        DropdownMenuItem(
                          value: 'presenter_female',
                          child: Text('专业故事电台女主播 (presenter_female)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _minimaxVoiceCtrl.text = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('朗读语速 (Speed)：', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(
                              '${_ttsSpeed.toStringAsFixed(2)}x (${_ttsSpeed <= 0.85 ? "😴 适合睡前慢速" : "⚡ 正常语速"})',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _ttsSpeed,
                          min: 0.70,
                          max: 1.20,
                          divisions: 10,
                          label: '${_ttsSpeed.toStringAsFixed(2)}x',
                          onChanged: (val) {
                            setState(() {
                              _ttsSpeed = val;
                            });
                          },
                        ),
                        Text(
                          '提示：儿童睡前绘本推荐语速 0.80x ~ 0.85x，更具轻柔与催眠效果。',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                        ),
                      ],
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 32),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text(
                  '保存并应用当前所有配置',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? badge,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ?badge,
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}
