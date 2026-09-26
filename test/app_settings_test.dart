import 'package:flutter_test/flutter_test.dart';
import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/services/book_engine_service.dart';

void main() {
  group('AppSettings Multi-Profile Tests', () {
    test('Default profiles are initialized properly', () {
      final settings = AppSettings();

      expect(settings.llmProfiles.isNotEmpty, isTrue);
      expect(settings.imageProfiles.isNotEmpty, isTrue);
      expect(settings.activeLlmProfileId, isNotEmpty);
      expect(settings.activeImageProfileId, isNotEmpty);

      // 默认激活的 Gemini
      expect(settings.llmType, 'gemini');
      expect(settings.imageType, 'gemini');
      expect(settings.llmModel, 'gemini-2.5-flash');
      expect(settings.imageModel, 'imagen-3.0-generate-002');
    });

    test('Switching active profile updates compatible getters', () {
      final settings = AppSettings();

      // 查找 DeepSeek 配置
      final deepseek = settings.llmProfiles.firstWhere(
        (p) => p.name.contains('DeepSeek'),
        orElse: () => settings.llmProfiles[1],
      );

      // 激活 DeepSeek
      settings.activeLlmProfileId = deepseek.id;
      expect(settings.llmType, deepseek.providerType);
      expect(settings.llmBaseUrl, deepseek.baseUrl);
      expect(settings.llmModel, deepseek.model);

      // 修改当前激活 profile 的 apiKey，检验写入与映射
      settings.llmApiKey = 'sk-test-deepseek-key';
      expect(deepseek.apiKey, 'sk-test-deepseek-key');
    });

    test('Full serialization and deserialization retains multi-profiles', () {
      final settings = AppSettings();
      settings.llmProfiles.add(LlmProfile(
        id: 'llm_custom_1',
        name: '本地 Ollama 3.2',
        providerType: 'openai',
        baseUrl: 'http://localhost:11434/v1',
        apiKey: 'ollama',
        model: 'llama3.2',
      ));
      settings.activeLlmProfileId = 'llm_custom_1';

      settings.imageProfiles.add(ImageProfile(
        id: 'img_custom_1',
        name: '自建 SDXL 接口',
        providerType: 'openai',
        baseUrl: 'http://192.168.1.100:8000/v1',
        apiKey: 'sdxl-secret',
        model: 'sdxl-turbo',
      ));
      settings.activeImageProfileId = 'img_custom_1';

      final jsonMap = settings.toJson();
      expect(jsonMap['activeLlmProfileId'], 'llm_custom_1');
      expect(jsonMap['activeImageProfileId'], 'img_custom_1');

      final restored = AppSettings.fromJson(jsonMap);
      expect(restored.activeLlmProfileId, 'llm_custom_1');
      expect(restored.activeImageProfileId, 'img_custom_1');
      expect(restored.llmType, 'openai');
      expect(restored.llmModel, 'llama3.2');
      expect(restored.llmBaseUrl, 'http://localhost:11434/v1');
      expect(restored.imageModel, 'sdxl-turbo');

      final foundCustomLlm = restored.llmProfiles.any((p) => p.id == 'llm_custom_1');
      expect(foundCustomLlm, isTrue);
    });

    test('Default profiles include Zhipu GLM and Tencent TokenHub', () {
      final settings = AppSettings();

      final glm = settings.imageProfiles.firstWhere(
        (p) => p.name.contains('智谱 GLM'),
      );
      expect(glm.baseUrl, 'https://open.bigmodel.cn/api/paas/v4/images/generations');
      expect(glm.model, 'glm-image');
      expect(glm.providerType, 'openai');

      final tokenhub = settings.imageProfiles.firstWhere(
        (p) => p.name.contains('腾讯 TokenHub'),
      );
      expect(tokenhub.baseUrl, 'https://tokenhub.tencentmaas.com/v1/wand/hunyuan-image/v35-generation');
      expect(tokenhub.model, 'hy-image-v3.5-preview');
      expect(tokenhub.providerType, 'tokenhub');

      // 验证预设模板库
      expect(ImagePreset.presets.any((p) => p.label.contains('智谱 GLM')), isTrue);
      expect(ImagePreset.presets.any((p) => p.label.contains('腾讯 TokenHub')), isTrue);
    });

    test('Tencent TokenHub response format extraction', () async {
      final engine = BookEngineService();

      // 1. choices[].delta.image.url 格式 (TokenHub 实际流式输出)
      final sampleChunk = {
        'choices': [
          {
            'delta': {
              'image': {
                'url': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
                'type': 'image',
              },
            },
          }
        ],
      };
      final res1 = await engine.extractImageFromResponseForTesting(sampleChunk);
      expect(res1, isNotNull);
      expect(res1!.startsWith('iVBORw0KGgo'), isTrue);

      // 2. assembled_history 工具链格式 (TokenHub 历史消息备份)
      final sampleHistory = {
        'assembled_history': [
          {
            'content': [
              {
                'image_url': {
                  'url': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
                },
                'type': 'image_url',
              }
            ],
            'role': 'tool',
          }
        ],
      };
      final res2 = await engine.extractImageFromResponseForTesting(sampleHistory);
      expect(res2, isNotNull);
      expect(res2!.startsWith('iVBORw0KGgo'), isTrue);
    });

    test('Zhipu GLM image response format extraction', () async {
      final engine = BookEngineService();

      // data[0].b64_json 格式
      final sampleB64 = {
        'created': 1720000000,
        'data': [
          {
            'b64_json': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
          }
        ]
      };
      final res = await engine.extractImageFromResponseForTesting(sampleB64);
      expect(res, isNotNull);
      expect(res!.startsWith('iVBORw0KGgo'), isTrue);
    });

    test('Old format JSON backward compatibility upgrade', () {
      final legacyJson = {
        'llmType': 'anthropic',
        'llmBaseUrl': 'https://api.anthropic.com',
        'llmApiKey': 'sk-ant-test',
        'llmModel': 'claude-3-5-sonnet-20241022',
        'imageType': 'openai',
        'imageBaseUrl': 'https://api.openai.com/v1',
        'imageApiKey': 'sk-openai-img',
        'imageModel': 'dall-e-3',
        'enableImageFallback': true,
        'fallbackImageType': 'gemini',
        'fallbackImageBaseUrl': 'https://generativelanguage.googleapis.com',
        'fallbackImageApiKey': 'gemini-key',
        'fallbackImageModel': 'imagen-3.0',
      };

      final settings = AppSettings.fromJson(legacyJson);
      expect(settings.llmType, 'anthropic');
      expect(settings.llmApiKey, 'sk-ant-test');
      expect(settings.llmModel, 'claude-3-5-sonnet-20241022');
      expect(settings.imageType, 'openai');
      expect(settings.imageApiKey, 'sk-openai-img');
      expect(settings.imageModel, 'dall-e-3');
      expect(settings.enableImageFallback, isTrue);
    });
  });
}
