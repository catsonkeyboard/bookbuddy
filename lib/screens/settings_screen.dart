import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_settings.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _service = SettingsService();
  late AppSettings _settings;
  bool _loading = true;

  // Controllers
  late TextEditingController _llmUrlCtrl;
  late TextEditingController _llmKeyCtrl;
  late TextEditingController _llmModelCtrl;

  late TextEditingController _imgUrlCtrl;
  late TextEditingController _imgKeyCtrl;
  late TextEditingController _imgModelCtrl;

  late TextEditingController _fbImgUrlCtrl;
  late TextEditingController _fbImgKeyCtrl;
  late TextEditingController _fbImgModelCtrl;

  // MiniMax TTS Controllers
  late TextEditingController _minimaxKeyCtrl;
  late TextEditingController _minimaxGroupIdCtrl;
  late TextEditingController _minimaxModelCtrl;
  late TextEditingController _minimaxVoiceCtrl;
  double _ttsSpeed = 0.85;

  bool _obscureLlmKey = true;
  bool _obscureImgKey = true;
  bool _obscureFbImgKey = true;
  bool _obscureTtsKey = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _settings = await _service.loadSettings();
    _llmUrlCtrl = TextEditingController(text: _settings.llmBaseUrl);
    _llmKeyCtrl = TextEditingController(text: _settings.llmApiKey);
    _llmModelCtrl = TextEditingController(text: _settings.llmModel);

    _imgUrlCtrl = TextEditingController(text: _settings.imageBaseUrl);
    _imgKeyCtrl = TextEditingController(text: _settings.imageApiKey);
    _imgModelCtrl = TextEditingController(text: _settings.imageModel);

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

  Future<void> _save() async {
    _settings.llmBaseUrl = _llmUrlCtrl.text.trim();
    _settings.llmApiKey = _llmKeyCtrl.text.trim();
    _settings.llmModel = _llmModelCtrl.text.trim();

    _settings.imageBaseUrl = _imgUrlCtrl.text.trim();
    _settings.imageApiKey = _imgKeyCtrl.text.trim();
    _settings.imageModel = _imgModelCtrl.text.trim();

    _settings.fallbackImageBaseUrl = _fbImgUrlCtrl.text.trim();
    _settings.fallbackImageApiKey = _fbImgKeyCtrl.text.trim();
    _settings.fallbackImageModel = _fbImgModelCtrl.text.trim();

    _settings.minimaxApiKey = _minimaxKeyCtrl.text.trim();
    _settings.minimaxGroupId = _minimaxGroupIdCtrl.text.trim();
    _settings.minimaxModel = _minimaxModelCtrl.text.trim().isNotEmpty ? _minimaxModelCtrl.text.trim() : 'speech-01-turbo';
    _settings.minimaxVoiceId = _minimaxVoiceCtrl.text.trim().isNotEmpty ? _minimaxVoiceCtrl.text.trim() : 'audiobook_female_1';
    _settings.minimaxSpeed = _ttsSpeed;

    await _service.saveSettings(_settings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ 模型与接口配置已成功保存！'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _pasteTo(TextEditingController ctrl, String fieldLabel) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      setState(() {
        ctrl.text = data.text!.trim();
      });
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

  void _onLlmTypeChanged(String? type) {
    if (type == null) return;
    setState(() {
      _settings.llmType = type;
      if (type == 'gemini') {
        _llmUrlCtrl.text = 'https://generativelanguage.googleapis.com';
        _llmModelCtrl.text = 'gemini-2.5-flash';
      } else if (type == 'anthropic') {
        _llmUrlCtrl.text = 'https://api.anthropic.com';
        _llmModelCtrl.text = 'claude-3-5-sonnet-20241022';
      } else {
        _llmUrlCtrl.text = 'https://api.openai.com/v1';
        _llmModelCtrl.text = 'gpt-4o-mini';
      }
    });
  }

  void _onImgTypeChanged(String? type) {
    if (type == null) return;
    setState(() {
      _settings.imageType = type;
      if (type == 'gemini') {
        _imgUrlCtrl.text = 'https://generativelanguage.googleapis.com';
        _imgModelCtrl.text = 'imagen-3.0-generate-002';
      } else {
        _imgUrlCtrl.text = 'https://api.openai.com/v1';
        _imgModelCtrl.text = 'dall-e-3';
      }
    });
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️ 模型与接口配置'),
        actions: [
          IconButton(
            tooltip: '保存配置',
            icon: const Icon(Icons.check),
            onPressed: _save,
          )
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSectionCard(
                title: '🧠 故事文本模型 (LLM)',
                subtitle: '负责童话文本精简、角色卡提取与分镜场景重构',
                icon: Icons.psychology,
                children: [
                  DropdownButtonFormField<String>(
                    value: _settings.llmType,
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
                        child: Text('OpenAI 兼容协议 (支持自建网关/智谱/DeepSeek)'),
                      ),
                      DropdownMenuItem(
                        value: 'anthropic',
                        child: Text('Anthropic Claude (官方原生)'),
                      ),
                    ],
                    onChanged: _onLlmTypeChanged,
                  ),
                  const SizedBox(height: 16),
                  _buildUrlField(
                    controller: _llmUrlCtrl,
                    label: 'API Base URL',
                    helper: 'Gemini可留空或默认；自建网关填写到/v1',
                  ),
                  const SizedBox(height: 16),
                  _buildKeyField(
                    controller: _llmKeyCtrl,
                    label: 'LLM API Key',
                    obscure: _obscureLlmKey,
                    onToggleObscure: () {
                      setState(() {
                        _obscureLlmKey = !_obscureLlmKey;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _llmModelCtrl,
                    enableInteractiveSelection: true,
                    decoration: InputDecoration(
                      labelText: '模型名称 (Model)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: '从剪贴板粘贴模型名',
                        icon: const Icon(Icons.paste_rounded),
                        onPressed: () => _pasteTo(_llmModelCtrl, '模型名称'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionCard(
                title: '🎨 主生图模型 (Image Primary)',
                subtitle: '负责全书核心跨页插画与角色定妆照生成',
                icon: Icons.palette,
                children: [
                  DropdownButtonFormField<String>(
                    value: _settings.imageType,
                    decoration: const InputDecoration(
                      labelText: '生图接口协议',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'gemini',
                        child: Text('Google Imagen 3 / Gemini 多模态原生'),
                      ),
                      DropdownMenuItem(
                        value: 'openai',
                        child: Text('OpenAI 兼容格式 (CogView / DALL-E / 聊天生图)'),
                      ),
                    ],
                    onChanged: _onImgTypeChanged,
                  ),
                  const SizedBox(height: 16),
                  _buildUrlField(
                    controller: _imgUrlCtrl,
                    label: '生图 API Base URL',
                    helper: 'Google 原生可留空；OpenAI 兼容填网关地址',
                  ),
                  const SizedBox(height: 16),
                  _buildKeyField(
                    controller: _imgKeyCtrl,
                    label: '生图 API Key',
                    obscure: _obscureImgKey,
                    onToggleObscure: () {
                      setState(() {
                        _obscureImgKey = !_obscureImgKey;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _imgModelCtrl,
                    enableInteractiveSelection: true,
                    decoration: InputDecoration(
                      labelText: '生图模型名称 (如 imagen-3.0-generate-002)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: '从剪贴板粘贴模型名',
                        icon: const Icon(Icons.paste_rounded),
                        onPressed: () => _pasteTo(_imgModelCtrl, '生图模型名称'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionCard(
                title: '🛡️ 备用生图接口 (Failover)',
                subtitle: '当主通道遇到 429/503/限流时，自动无缝降级切换至此',
                icon: Icons.alt_route,
                children: [
                  SwitchListTile(
                    title: const Text('启用多通道自动降级'),
                    subtitle: const Text('主通道算力耗尽或故障时，自动调用备选接口保证成书'),
                    value: _settings.enableImageFallback,
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
              const SizedBox(height: 20),
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
              const SizedBox(height: 30),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text(
                  '保存并应用当前配置',
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
