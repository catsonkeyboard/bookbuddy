class LlmProfile {
  String id;
  String name; // 配置显示名称，如 "Gemini 官方", "DeepSeek-V3", "本地 Ollama"
  String providerType; // 'gemini' | 'openai' | 'anthropic'
  String baseUrl;
  String apiKey;
  String model;

  LlmProfile({
    required this.id,
    required this.name,
    this.providerType = 'gemini',
    this.baseUrl = 'https://generativelanguage.googleapis.com',
    this.apiKey = '',
    this.model = 'gemini-2.5-flash',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'providerType': providerType,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
      };

  factory LlmProfile.fromJson(Map<String, dynamic> json) => LlmProfile(
        id: json['id'] ?? '',
        name: json['name'] ?? '未命名LLM配置',
        providerType: json['providerType'] ?? 'gemini',
        baseUrl: json['baseUrl'] ?? '',
        apiKey: json['apiKey'] ?? '',
        model: json['model'] ?? '',
      );

  LlmProfile copyWith({
    String? id,
    String? name,
    String? providerType,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) {
    return LlmProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      providerType: providerType ?? this.providerType,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
    );
  }
}

class ImageProfile {
  String id;
  String name; // 配置显示名称，如 "Imagen 3 官方", "智谱 CogView-3", "DALL-E 3"
  String providerType; // 'gemini' | 'openai'
  String baseUrl;
  String apiKey;
  String model;

  ImageProfile({
    required this.id,
    required this.name,
    this.providerType = 'gemini',
    this.baseUrl = 'https://generativelanguage.googleapis.com',
    this.apiKey = '',
    this.model = 'imagen-3.0-generate-002',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'providerType': providerType,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
      };

  factory ImageProfile.fromJson(Map<String, dynamic> json) => ImageProfile(
        id: json['id'] ?? '',
        name: json['name'] ?? '未命名生图配置',
        providerType: json['providerType'] ?? 'gemini',
        baseUrl: json['baseUrl'] ?? '',
        apiKey: json['apiKey'] ?? '',
        model: json['model'] ?? '',
      );

  ImageProfile copyWith({
    String? id,
    String? name,
    String? providerType,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) {
    return ImageProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      providerType: providerType ?? this.providerType,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
    );
  }
}

class ImagePreset {
  final String label;
  final String name;
  final String providerType; // 'gemini' | 'openai'
  final String baseUrl;
  final String defaultModel;
  final String description;

  const ImagePreset({
    required this.label,
    required this.name,
    required this.providerType,
    required this.baseUrl,
    required this.defaultModel,
    required this.description,
  });

  static const List<ImagePreset> presets = [
    ImagePreset(
      label: '智谱 GLM 生图',
      name: '智谱 GLM 生图 (glm-image)',
      providerType: 'openai',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4/images/generations',
      defaultModel: 'glm-image',
      description: '智谱官方开放平台最新生图模型 (glm-image)，支持 1280x1280 高清绘本',
    ),
    ImagePreset(
      label: '腾讯 TokenHub 生图',
      name: '腾讯 TokenHub (混元 3.5 生图)',
      providerType: 'tokenhub',
      baseUrl: 'https://tokenhub.tencentmaas.com/v1/wand/hunyuan-image/v35-generation',
      defaultModel: 'hy-image-v3.5-preview',
      description: '腾讯 TokenHub 混元生图 3.5 官方接口 (支持参考图风格/主角一致性)',
    ),
    ImagePreset(
      label: 'Google Imagen 3',
      name: 'Google Imagen 3 (官方原生)',
      providerType: 'gemini',
      baseUrl: 'https://generativelanguage.googleapis.com',
      defaultModel: 'imagen-3.0-generate-002',
      description: 'Google 原生 Imagen 3 绘本画面生成与角色定妆照',
    ),
    ImagePreset(
      label: 'OpenAI DALL-E 3',
      name: 'OpenAI DALL-E 3 (官方格式)',
      providerType: 'openai',
      baseUrl: 'https://api.openai.com/v1',
      defaultModel: 'dall-e-3',
      description: 'OpenAI 官方 DALL-E 3 标准生图接口',
    ),
  ];
}

class AppSettings {
  // LLM 配置列表与激活项
  List<LlmProfile> llmProfiles;
  String activeLlmProfileId;

  // 主生图配置列表与激活项
  List<ImageProfile> imageProfiles;
  String activeImageProfileId;

  // 备用生图配置 (Failover)
  bool enableImageFallback;
  String fallbackImageType;
  String fallbackImageBaseUrl;
  String fallbackImageApiKey;
  String fallbackImageModel;

  // 语音合成配置 (TTS - MiniMax)
  bool ttsEnabled;
  String ttsProvider; // minimax
  String minimaxApiKey;
  String minimaxGroupId;
  String minimaxModel;
  String minimaxVoiceId;
  double minimaxSpeed;

  AppSettings({
    List<LlmProfile>? llmProfiles,
    String? activeLlmProfileId,
    List<ImageProfile>? imageProfiles,
    String? activeImageProfileId,
    // 兼容初始参数（若未提供 profile 时自动建立）
    String? llmType,
    String? llmBaseUrl,
    String? llmApiKey,
    String? llmModel,
    String? imageType,
    String? imageBaseUrl,
    String? imageApiKey,
    String? imageModel,
    this.enableImageFallback = false,
    this.fallbackImageType = 'openai',
    this.fallbackImageBaseUrl = 'https://api.openai.com/v1',
    this.fallbackImageApiKey = '',
    this.fallbackImageModel = 'dall-e-3',
    this.ttsEnabled = true,
    this.ttsProvider = 'minimax',
    this.minimaxApiKey = '',
    this.minimaxGroupId = '',
    this.minimaxModel = 'speech-01-turbo',
    this.minimaxVoiceId = 'audiobook_female_1',
    this.minimaxSpeed = 0.85,
  })  : llmProfiles = llmProfiles ?? _createDefaultLlmProfiles(
          initialType: llmType,
          initialBaseUrl: llmBaseUrl,
          initialApiKey: llmApiKey,
          initialModel: llmModel,
        ),
        activeLlmProfileId = activeLlmProfileId ?? 'llm_gemini_default',
        imageProfiles = imageProfiles ?? _createDefaultImageProfiles(
          initialType: imageType,
          initialBaseUrl: imageBaseUrl,
          initialApiKey: imageApiKey,
          initialModel: imageModel,
        ),
        activeImageProfileId = activeImageProfileId ?? 'img_gemini_default' {
    _ensureActiveLlmValid();
    _ensureActiveImageValid();
  }

  static List<LlmProfile> _createDefaultLlmProfiles({
    String? initialType,
    String? initialBaseUrl,
    String? initialApiKey,
    String? initialModel,
  }) {
    return [
      LlmProfile(
        id: 'llm_gemini_default',
        name: 'Google Gemini (官方推荐)',
        providerType: initialType ?? 'gemini',
        baseUrl: initialBaseUrl ?? 'https://generativelanguage.googleapis.com',
        apiKey: initialApiKey ?? '',
        model: initialModel ?? 'gemini-2.5-flash',
      ),
      LlmProfile(
        id: 'llm_openai_default',
        name: 'OpenAI 协议 (GPT-4o / 自建网关)',
        providerType: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: '',
        model: 'gpt-4o-mini',
      ),
      LlmProfile(
        id: 'llm_deepseek_default',
        name: 'DeepSeek 官方 API',
        providerType: 'openai',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: '',
        model: 'deepseek-chat',
      ),
      LlmProfile(
        id: 'llm_claude_default',
        name: 'Anthropic Claude (官方原生)',
        providerType: 'anthropic',
        baseUrl: 'https://api.anthropic.com',
        apiKey: '',
        model: 'claude-3-5-sonnet-20241022',
      ),
    ];
  }

  static List<ImageProfile> _createDefaultImageProfiles({
    String? initialType,
    String? initialBaseUrl,
    String? initialApiKey,
    String? initialModel,
  }) {
    return [
      ImageProfile(
        id: 'img_gemini_default',
        name: 'Google Imagen 3 (官方原生)',
        providerType: initialType ?? 'gemini',
        baseUrl: initialBaseUrl ?? 'https://generativelanguage.googleapis.com',
        apiKey: initialApiKey ?? '',
        model: initialModel ?? 'imagen-3.0-generate-002',
      ),
      ImageProfile(
        id: 'img_zhipu_glm',
        name: '智谱 GLM 生图 (glm-image)',
        providerType: 'openai',
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4/images/generations',
        apiKey: '',
        model: 'glm-image',
      ),
      ImageProfile(
        id: 'img_tencent_tokenhub',
        name: '腾讯 TokenHub (混元 3.5 生图)',
        providerType: 'tokenhub',
        baseUrl: 'https://tokenhub.tencentmaas.com/v1/wand/hunyuan-image/v35-generation',
        apiKey: '',
        model: 'hy-image-v3.5-preview',
      ),
      ImageProfile(
        id: 'img_openai_default',
        name: 'OpenAI DALL-E 3 (官方格式)',
        providerType: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: '',
        model: 'dall-e-3',
      ),
    ];
  }

  void _ensureActiveLlmValid() {
    if (llmProfiles.isEmpty) {
      llmProfiles.add(LlmProfile(
        id: 'llm_custom_default',
        name: '默认 LLM 配置',
        providerType: 'gemini',
        baseUrl: 'https://generativelanguage.googleapis.com',
        apiKey: '',
        model: 'gemini-2.5-flash',
      ));
      activeLlmProfileId = llmProfiles.first.id;
      return;
    }
    if (!llmProfiles.any((p) => p.id == activeLlmProfileId)) {
      activeLlmProfileId = llmProfiles.first.id;
    }
  }

  void _ensureActiveImageValid() {
    if (imageProfiles.isEmpty) {
      imageProfiles.add(ImageProfile(
        id: 'img_custom_default',
        name: '默认生图配置',
        providerType: 'gemini',
        baseUrl: 'https://generativelanguage.googleapis.com',
        apiKey: '',
        model: 'imagen-3.0-generate-002',
      ));
      activeImageProfileId = imageProfiles.first.id;
      return;
    }
    if (!imageProfiles.any((p) => p.id == activeImageProfileId)) {
      activeImageProfileId = imageProfiles.first.id;
    }
  }

  // 获得当前激活的 LLM Profile
  LlmProfile get activeLlmProfile {
    _ensureActiveLlmValid();
    return llmProfiles.firstWhere(
      (p) => p.id == activeLlmProfileId,
      orElse: () => llmProfiles.first,
    );
  }

  // 获得当前激活的生图 Profile
  ImageProfile get activeImageProfile {
    _ensureActiveImageValid();
    return imageProfiles.firstWhere(
      (p) => p.id == activeImageProfileId,
      orElse: () => imageProfiles.first,
    );
  }

  // 向后兼容 Getters & Setters：代码中已有 settings.llmApiKey / settings.imageType 等无缝访问
  String get llmType => activeLlmProfile.providerType;
  set llmType(String val) => activeLlmProfile.providerType = val;

  String get llmBaseUrl => activeLlmProfile.baseUrl;
  set llmBaseUrl(String val) => activeLlmProfile.baseUrl = val;

  String get llmApiKey => activeLlmProfile.apiKey;
  set llmApiKey(String val) => activeLlmProfile.apiKey = val;

  String get llmModel => activeLlmProfile.model;
  set llmModel(String val) => activeLlmProfile.model = val;

  String get imageType => activeImageProfile.providerType;
  set imageType(String val) => activeImageProfile.providerType = val;

  String get imageBaseUrl => activeImageProfile.baseUrl;
  set imageBaseUrl(String val) => activeImageProfile.baseUrl = val;

  String get imageApiKey => activeImageProfile.apiKey;
  set imageApiKey(String val) => activeImageProfile.apiKey = val;

  String get imageModel => activeImageProfile.model;
  set imageModel(String val) => activeImageProfile.model = val;

  Map<String, dynamic> toJson() => {
        // 兼容旧版本单项字段
        'llmType': llmType,
        'llmBaseUrl': llmBaseUrl,
        'llmApiKey': llmApiKey,
        'llmModel': llmModel,
        'imageType': imageType,
        'imageBaseUrl': imageBaseUrl,
        'imageApiKey': imageApiKey,
        'imageModel': imageModel,

        // 新版本多配置列表与激活项
        'llmProfiles': llmProfiles.map((p) => p.toJson()).toList(),
        'activeLlmProfileId': activeLlmProfileId,
        'imageProfiles': imageProfiles.map((p) => p.toJson()).toList(),
        'activeImageProfileId': activeImageProfileId,

        // 备用与 TTS
        'enableImageFallback': enableImageFallback,
        'fallbackImageType': fallbackImageType,
        'fallbackImageBaseUrl': fallbackImageBaseUrl,
        'fallbackImageApiKey': fallbackImageApiKey,
        'fallbackImageModel': fallbackImageModel,
        'ttsEnabled': ttsEnabled,
        'ttsProvider': ttsProvider,
        'minimaxApiKey': minimaxApiKey,
        'minimaxGroupId': minimaxGroupId,
        'minimaxModel': minimaxModel,
        'minimaxVoiceId': minimaxVoiceId,
        'minimaxSpeed': minimaxSpeed,
      };

  /// Settings that may be kept in ordinary preferences or device backups.
  Map<String, dynamic> toPublicJson() {
    final data = toJson();
    for (final key in [
      'llmApiKey',
      'imageApiKey',
      'fallbackImageApiKey',
      'minimaxApiKey',
    ]) {
      data[key] = '';
    }
    for (final key in ['llmProfiles', 'imageProfiles']) {
      for (final profile in data[key] as List<dynamic>) {
        (profile as Map<String, dynamic>)['apiKey'] = '';
      }
    }
    return data;
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    List<LlmProfile>? loadedLlmProfiles;
    if (json['llmProfiles'] is List) {
      loadedLlmProfiles = (json['llmProfiles'] as List)
          .whereType<Map<String, dynamic>>()
          .map((item) => LlmProfile.fromJson(item))
          .toList();
    }

    List<ImageProfile>? loadedImageProfiles;
    if (json['imageProfiles'] is List) {
      loadedImageProfiles = (json['imageProfiles'] as List)
          .whereType<Map<String, dynamic>>()
          .map((item) => ImageProfile.fromJson(item))
          .toList();
    }

    // 若从旧版本数据恢复且没有 profiles 列表，则将顶层旧字段填充到第一个激活的默认配置中
    if (loadedLlmProfiles == null || loadedLlmProfiles.isEmpty) {
      final oldType = json['llmType'] as String?;
      final oldUrl = json['llmBaseUrl'] as String?;
      final oldKey = json['llmApiKey'] as String?;
      final oldModel = json['llmModel'] as String?;
      loadedLlmProfiles = _createDefaultLlmProfiles(
        initialType: oldType,
        initialBaseUrl: oldUrl,
        initialApiKey: oldKey,
        initialModel: oldModel,
      );
    }

    if (loadedImageProfiles == null || loadedImageProfiles.isEmpty) {
      final oldImgType = json['imageType'] as String?;
      final oldImgUrl = json['imageBaseUrl'] as String?;
      final oldImgKey = json['imageApiKey'] as String?;
      final oldImgModel = json['imageModel'] as String?;
      loadedImageProfiles = _createDefaultImageProfiles(
        initialType: oldImgType,
        initialBaseUrl: oldImgUrl,
        initialApiKey: oldImgKey,
        initialModel: oldImgModel,
      );
    }

    return AppSettings(
      llmProfiles: loadedLlmProfiles,
      activeLlmProfileId: json['activeLlmProfileId'],
      imageProfiles: loadedImageProfiles,
      activeImageProfileId: json['activeImageProfileId'],
      enableImageFallback: json['enableImageFallback'] ?? false,
      fallbackImageType: json['fallbackImageType'] ?? 'openai',
      fallbackImageBaseUrl: json['fallbackImageBaseUrl'] ?? 'https://api.openai.com/v1',
      fallbackImageApiKey: json['fallbackImageApiKey'] ?? '',
      fallbackImageModel: json['fallbackImageModel'] ?? 'dall-e-3',
      ttsEnabled: json['ttsEnabled'] ?? true,
      ttsProvider: json['ttsProvider'] ?? 'minimax',
      minimaxApiKey: json['minimaxApiKey'] ?? '',
      minimaxGroupId: json['minimaxGroupId'] ?? '',
      minimaxModel: json['minimaxModel'] ?? 'speech-01-turbo',
      minimaxVoiceId: json['minimaxVoiceId'] ?? 'audiobook_female_1',
      minimaxSpeed: (json['minimaxSpeed'] as num?)?.toDouble() ?? 0.85,
    );
  }
}

