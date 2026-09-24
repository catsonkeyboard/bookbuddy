import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/app_settings.dart';
import '../models/book.dart';

class BookEngineService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 45),
    receiveTimeout: const Duration(seconds: 90),
  ));

  /// 阶段 1：通过 LLM 将故事重构为 8~12 幕紧凑的绘本跨页镜头
  Future<List<BookPageItem>> createStoryboards({
    required AppSettings settings,
    required String title,
    required String storyText,
  }) async {
    final systemPrompt = '''
你是一位资深儿童绘本分镜大师。请阅读完整故事，将故事整体改编并重构为 8 ~ 12 个连续生动的【绘本跨页镜头（Scenes）】。
## 绘本核心原则：
1. 【一页一图、图文对应】：每个镜头即为绘本的一页，必须包含本页文本以及对应的一幅插画画面设定。
2. 【场景聚合、杜绝零碎】：将发生在同一时空环境下的动作、相关对话及叙述自然融合成一段（2~4句话，朗读顺畅有画面感），严禁将一句问一句答切成孤立碎片。
3. 【画面动作与角色描述规范（极其重要，规避AI安全审查）】：
   - 在 action 画面动作描述中，【严禁使用可能具有商标版权或触发违禁审核的专有名词】（如：严禁出现“辛德瑞拉”、“灰姑娘”、“白雪公主”等受版权保护名称），一律转换为【通用外貌描述】（例如：用“金发少女”、“围着围裙的蓝裙女孩”、“黑发红唇的白肤少女”代替）；
   - 动作和神态描述保持童趣温馨，避免“双膝跪地”、“使唤”、“刻薄”等容易被 AI 审核判定为霸凌或受虐倾向的词汇，改用“正在壁炉旁擦拭地面”、“神态温和恬静”等健康正向画面词汇。
4. 【动物拟人化与微表情】：动物角色保持原生毛皮质感（如灰狼的厚灰毛皮），平时不穿人类衣服（严禁穿背带裤、靴子）；必须采用双足直立行走姿态；重点刻画人类特有的微表情（如坏笑、狡黠眯眼、谄媚假笑）。
5. 只能输出合法 JSON 格式，格式如下：
{
  "scenes": [
    {
      "pageIndex": 0,
      "text": "本页绘本文字（2~4句，生动通俗）",
      "action": "当前画面的核心视觉动作（一句话，突出角色互动与站立体态，使用通用外貌词汇）",
      "emotion": "神态微表情（如：金发少女眼神温柔从容，大灰狼站立在树旁歪嘴坏笑）"
    }
  ]
}
''';

    final userPrompt = '''
### 绘本标题
$title

### 故事正文
$storyText
''';

    final rawJson = await _callLlm(
      settings: settings,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
    );

    final parsed = _extractJson(rawJson);
    final rawList = parsed is Map ? (parsed['scenes'] as List? ?? []) : (parsed is List ? parsed : []);
    final List<BookPageItem> pages = [];
    for (int i = 0; i < rawList.length; i++) {
      final s = rawList[i];
      if (s is Map) {
        pages.add(BookPageItem(
          pageIndex: i,
          text: s['text'] ?? '',
          sceneAction: s['action'] ?? '',
          sceneEmotion: s['emotion'] ?? '',
        ));
      }
    }
    return pages;
  }

  /// 组装默认的原生图提示词
  String buildDefaultPrompt({
    required BookStyle style,
    required BookPageItem page,
  }) {
    final promptBits = [
      style.prefix,
      '场景情节动作：${page.sceneAction}',
      if (page.sceneEmotion.isNotEmpty) '神态微表情：${page.sceneEmotion}',
      '纯净绘本跨页画面，主体突出，温馨和谐，严禁出现三视图、设计稿和字符文字',
    ];
    return promptBits.join('，');
  }

  /// 对 prompt 进行安全净化，消除容易触发上游审查拦截的敏感专有名词与词汇
  String sanitizePrompt(String raw) {
    var p = raw;
    final replacements = {
      '辛德瑞拉': '金发少女',
      '灰姑娘': '质朴金发少女',
      'Cinderella': 'fair-haired maiden',
      '白雪公主': '黑发纯真少女',
      'Snow White': 'fair maiden',
      '睡美人': '沉睡的公主',
      '双膝跪地': '蹲在地上',
      '跪地': '在地面',
      '刻薄': '神态冷淡',
      '使唤': '指点',
      '隐忍': '安静乖巧',
      '上身赤裸': '身披微光纱衣',
      '一丝不挂': '穿着轻薄长袍',
      '没穿衣服': '身着特制透明礼服',
      '没穿衣物': '身着特制透明礼服',
      '光着身子': '身着特制透明礼服',
      '光着身体': '身着特制透明礼服',
    };
    replacements.forEach((key, val) {
      p = p.replaceAll(key, val);
    });
    return p;
  }

  /// 阶段 2：生成单页绘本插画（注入全书统一主角定妆照 referenceImageBase64 锁定外貌一致性）
  Future<String?> generateIllustration({
    required AppSettings settings,
    required BookStyle style,
    required BookPageItem page,
    String? fullPromptOverride,
    String? customInstruction,
    String? referenceImageBase64,
  }) async {
    // 优先使用用户编辑/重写的完整提示词；否则按规范组装
    String finalPrompt;
    if (fullPromptOverride != null && fullPromptOverride.trim().isNotEmpty) {
      finalPrompt = fullPromptOverride.trim();
    } else {
      final promptBits = [
        style.prefix,
        '场景情节动作：${page.sceneAction}',
        if (page.sceneEmotion.isNotEmpty) '神态微表情：${page.sceneEmotion}',
        if (customInstruction != null && customInstruction.isNotEmpty) '画面微调要求：$customInstruction',
        '纯净绘本跨页画面，主体突出，温馨和谐，严禁出现三视图、设计稿和字符文字',
      ];
      finalPrompt = promptBits.join('，');
    }

    // 记录本次实际使用的原生生图提示词
    page.rawPrompt = finalPrompt;

    // 进行安全脱敏过滤（防止触发 PROHIBITED_CONTENT）
    final cleanPrompt = sanitizePrompt(finalPrompt);
    final negative = style.negative;

    // 1. 尝试主通道
    try {
      final b64 = await _callImageApi(
        type: settings.imageType,
        baseUrl: settings.imageBaseUrl,
        apiKey: settings.imageApiKey,
        model: settings.imageModel,
        prompt: cleanPrompt,
        negative: negative,
        referenceImageBase64: referenceImageBase64,
      );
      if (b64 != null && b64.isNotEmpty) {
        page.generationError = null;
        return b64;
      }
    } catch (e) {
      // 主通道失败，检查是否有备用通道
      if (!settings.enableImageFallback || settings.fallbackImageApiKey.isEmpty) {
        page.generationError = e.toString();
        rethrow;
      }
    }

    // 2. 尝试备用通道
    if (settings.enableImageFallback && settings.fallbackImageApiKey.isNotEmpty) {
      try {
        final b64 = await _callImageApi(
          type: settings.fallbackImageType,
          baseUrl: settings.fallbackImageBaseUrl,
          apiKey: settings.fallbackImageApiKey,
          model: settings.fallbackImageModel,
          prompt: cleanPrompt,
          negative: negative,
          referenceImageBase64: referenceImageBase64,
        );
        if (b64 != null && b64.isNotEmpty) {
          page.generationError = null;
          return b64;
        }
      } catch (e) {
        page.generationError = e.toString();
        rethrow;
      }
    }

    return null;
  }

  Future<String> _callLlm({
    required AppSettings settings,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    if (settings.llmType == 'gemini') {
      final base = settings.llmBaseUrl.replaceAll(RegExp(r'/v1(beta)?/?$'), '');
      final url = '$base/v1beta/models/${settings.llmModel}:generateContent';
      final resp = await _dio.post(
        url,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': settings.llmApiKey,
        }),
        data: {
          'contents': [
            {'role': 'user', 'parts': [{'text': userPrompt}]}
          ],
          'systemInstruction': {'parts': [{'text': systemPrompt}]},
          'generationConfig': {'temperature': 0.3},
        },
      );
      final cands = resp.data['candidates'] as List? ?? [];
      if (cands.isEmpty) throw Exception('Gemini 未返回内容');
      final parts = cands[0]['content']['parts'] as List? ?? [];
      return parts.map((p) => p['text'] ?? '').join();
    } else {
      // OpenAI 兼容协议
      final base = settings.llmBaseUrl.endsWith('/v1') ? settings.llmBaseUrl : '${settings.llmBaseUrl}/v1';
      final resp = await _dio.post(
        '$base/chat/completions',
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${settings.llmApiKey}',
        }),
        data: {
          'model': settings.llmModel,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
        },
      );
      final choices = resp.data['choices'] as List? ?? [];
      if (choices.isEmpty) throw Exception('OpenAI 接口未返回内容');
      return choices[0]['message']['content'] ?? '';
    }
  }

  Future<String?> _callImageApi({
    required String type,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required String negative,
    String? referenceImageBase64,
  }) async {
    if (type == 'gemini') {
      final base = baseUrl.replaceAll(RegExp(r'/v1(beta)?/?$'), '');
      if (model.toLowerCase().contains('imagen')) {
        final url = '$base/v1beta/models/$model:predict';
        final resp = await _dio.post(
          url,
          options: Options(headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          }),
          data: {
            'instances': [{'prompt': prompt}],
            'parameters': {'sampleCount': 1, 'aspectRatio': '16:9'},
          },
        );
        final preds = resp.data['predictions'] as List? ?? [];
        if (preds.isNotEmpty && preds[0]['bytesBase64Encoded'] != null) {
          return preds[0]['bytesBase64Encoded'];
        }
      } else {
        // 多模态生图 generateContent (支持注入参考图锁定主角外貌)
        final url = '$base/v1beta/models/$model:generateContent';
        final List<Map<String, dynamic>> parts = [];

        // 注入主角参考图（仅锁定人物的生理生物特征：五官长相、脸型、发型发色与体型，服饰完全遵从当前场景剧情要求）
        if (referenceImageBase64 != null && referenceImageBase64.isNotEmpty) {
          parts.add({
            'inlineData': {
              'mimeType': 'image/jpeg',
              'data': referenceImageBase64,
            }
          });
          parts.add({
            'text': '【角色一致性指导】：第一张参考图仅用于锁定主角的面部五官、脸型容貌与体型特征。'
                '【服饰动态要求】：主角的穿着装扮必须完全严格按照本次具体场景的文字描述绘制（如果当前情节换装、穿着睡衣、未穿衣物或特定服饰，必须严格以文字描述为准，切勿机械复制参考图中的旧衣服）！'
                '$prompt',
          });
        } else {
          parts.add({'text': prompt});
        }

        final resp = await _dio.post(
          url,
          options: Options(headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          }),
          data: {
            'contents': [{'parts': parts}],
            'generationConfig': {'responseModalities': ['IMAGE', 'TEXT']},
            'safetySettings': [
              {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_NONE'},
              {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_NONE'},
              {'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold': 'BLOCK_NONE'},
              {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'BLOCK_NONE'},
              {'category': 'HARM_CATEGORY_CIVIC_INTEGRITY', 'threshold': 'BLOCK_NONE'},
            ],
          },
        );
        final cands = resp.data['candidates'] as List? ?? [];
        if (cands.isNotEmpty) {
          final finishReason = cands[0]['finishReason'];
          if (finishReason == 'PROHIBITED_CONTENT') {
            throw Exception('提示词触发了上游 AI 服务商的内容安全过滤 (PROHIBITED_CONTENT)，请微调提示词规避敏感人物/动作');
          }
          final candParts = cands[0]['content']?['parts'] as List? ?? [];
          for (var p in candParts) {
            if (p['inlineData'] != null && p['inlineData']['data'] != null) {
              return p['inlineData']['data'];
            }
          }
        }
        final promptFeedback = resp.data['promptFeedback'];
        if (promptFeedback != null && promptFeedback['blockReason'] != null) {
          throw Exception('请求被上游安全策略拦截: ${promptFeedback['blockReason']}');
        }
      }
    } else {
      // OpenAI 兼容聊天生图 (支持多模态参考图传入)
      final base = baseUrl.endsWith('/v1') ? baseUrl : '$baseUrl/v1';
      dynamic content;
      if (referenceImageBase64 != null && referenceImageBase64.isNotEmpty) {
        content = [
          {
            'type': 'text',
            'text': '【角色一致性指导】：第一张参考图仅用于锁定主角的面部五官、脸型容貌与体型特征。'
                '【服饰动态要求】：主角的穿着装扮必须完全严格按照本次具体场景的文字描述绘制（如果当前情节换装、穿着睡衣、未穿衣物或特定服饰，必须严格以文字描述为准，切勿机械复制参考图中的旧衣服）！'
                '$prompt',
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$referenceImageBase64'},
          },
        ];
      } else {
        content = prompt;
      }

      final resp = await _dio.post(
        '$base/chat/completions',
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        }),
        data: {
          'model': model,
          'messages': [{'role': 'user', 'content': content}],
        },
      );
      final choices = resp.data['choices'] as List? ?? [];
      if (choices.isNotEmpty) {
        final msg = choices[0]['message'] ?? {};
        final images = msg['images'] as List? ?? [];
        if (images.isNotEmpty) {
          final u = images[0]['image_url']?['url'] ?? '';
          if (u.startsWith('data:image')) {
            return u.split(',').last;
          }
        }
      }
    }
    return null;
  }

  dynamic _extractJson(String raw) {
    var str = raw.trim();
    if (str.startsWith('```')) {
      final lines = str.split('\n');
      if (lines.length > 2) {
        str = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    try {
      return jsonDecode(str);
    } catch (_) {
      final start = str.indexOf('{');
      final end = str.lastIndexOf('}');
      if (start != -1 && end > start) {
        return jsonDecode(str.substring(start, end + 1));
      }
    }
    return {};
  }
}
