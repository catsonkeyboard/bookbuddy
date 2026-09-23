class AppSettings {
  // LLM 配置
  String llmType; // openai | gemini | anthropic
  String llmBaseUrl;
  String llmApiKey;
  String llmModel;

  // 主生图配置
  String imageType; // openai | gemini
  String imageBaseUrl;
  String imageApiKey;
  String imageModel;

  // 备用生图配置 (Failover)
  bool enableImageFallback;
  String fallbackImageType;
  String fallbackImageBaseUrl;
  String fallbackImageApiKey;
  String fallbackImageModel;

  AppSettings({
    this.llmType = 'gemini',
    this.llmBaseUrl = 'https://generativelanguage.googleapis.com',
    this.llmApiKey = '',
    this.llmModel = 'gemini-2.5-flash',
    this.imageType = 'gemini',
    this.imageBaseUrl = 'https://generativelanguage.googleapis.com',
    this.imageApiKey = '',
    this.imageModel = 'imagen-3.0-generate-002',
    this.enableImageFallback = false,
    this.fallbackImageType = 'openai',
    this.fallbackImageBaseUrl = 'https://api.openai.com/v1',
    this.fallbackImageApiKey = '',
    this.fallbackImageModel = 'dall-e-3',
  });

  Map<String, dynamic> toJson() => {
        'llmType': llmType,
        'llmBaseUrl': llmBaseUrl,
        'llmApiKey': llmApiKey,
        'llmModel': llmModel,
        'imageType': imageType,
        'imageBaseUrl': imageBaseUrl,
        'imageApiKey': imageApiKey,
        'imageModel': imageModel,
        'enableImageFallback': enableImageFallback,
        'fallbackImageType': fallbackImageType,
        'fallbackImageBaseUrl': fallbackImageBaseUrl,
        'fallbackImageApiKey': fallbackImageApiKey,
        'fallbackImageModel': fallbackImageModel,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        llmType: json['llmType'] ?? 'gemini',
        llmBaseUrl: json['llmBaseUrl'] ?? 'https://generativelanguage.googleapis.com',
        llmApiKey: json['llmApiKey'] ?? '',
        llmModel: json['llmModel'] ?? 'gemini-2.5-flash',
        imageType: json['imageType'] ?? 'gemini',
        imageBaseUrl: json['imageBaseUrl'] ?? 'https://generativelanguage.googleapis.com',
        imageApiKey: json['imageApiKey'] ?? '',
        imageModel: json['imageModel'] ?? 'imagen-3.0-generate-002',
        enableImageFallback: json['enableImageFallback'] ?? false,
        fallbackImageType: json['fallbackImageType'] ?? 'openai',
        fallbackImageBaseUrl: json['fallbackImageBaseUrl'] ?? 'https://api.openai.com/v1',
        fallbackImageApiKey: json['fallbackImageApiKey'] ?? '',
        fallbackImageModel: json['fallbackImageModel'] ?? 'dall-e-3',
      );
}
