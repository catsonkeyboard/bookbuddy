import 'package:flutter/material.dart';
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

  bool _obscureLlmKey = true;
  bool _obscureImgKey = true;
  bool _obscureFbImgKey = true;

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

    await _service.saveSettings(_settings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ 模型与接口配置已成功保存！'),
        backgroundColor: Colors.green,
      ),
    );
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
                  TextFormField(
                    controller: _llmUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API Base URL',
                      helperText: 'Gemini可留空或默认；自建网关填写到/v1',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _llmKeyCtrl,
                    obscureText: _obscureLlmKey,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureLlmKey
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () {
                          setState(() {
                            _obscureLlmKey = !_obscureLlmKey;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _llmModelCtrl,
                    decoration: const InputDecoration(
                      labelText: '模型名称 (Model)',
                      border: OutlineInputBorder(),
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
                  TextFormField(
                    controller: _imgUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API Base URL',
                      helperText: 'Google 原生可留空；OpenAI 兼容填网关地址',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _imgKeyCtrl,
                    obscureText: _obscureImgKey,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureImgKey
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () {
                          setState(() {
                            _obscureImgKey = !_obscureImgKey;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _imgModelCtrl,
                    decoration: const InputDecoration(
                      labelText: '生图模型名称 (如 imagen-3.0-generate-002)',
                      border: OutlineInputBorder(),
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
                    TextFormField(
                      controller: _fbImgUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: '备用 API Base URL',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _fbImgKeyCtrl,
                      obscureText: _obscureFbImgKey,
                      decoration: InputDecoration(
                        labelText: '备用 API Key',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureFbImgKey
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () {
                            setState(() {
                              _obscureFbImgKey = !_obscureFbImgKey;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _fbImgModelCtrl,
                      decoration: const InputDecoration(
                        labelText: '备用生图模型名称',
                        border: OutlineInputBorder(),
                      ),
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
