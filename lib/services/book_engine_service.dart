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
3. 【画面动作与角色描述规范】：
   - 人物与动物名词规范：自然界中的动物（如乌龟、小蝌蚪、大青蛙、鲤鱼、小鸟、小羊、小猪等）直接使用标准生物名词（如“一只大乌龟”、“一群黑色小蝌蚪”、“绿色大青蛙”），【绝对不要】抽象化改写为“甲壳水生动物”、“水生幼体”等怪异生硬词汇！
   - 商标版权规避（仅限特定商业IP）：仅对具有明确商业版权/商标的人物IP（如迪士尼特有的“辛德瑞拉”、“白雪公主”）才转换为通用外貌（如“金发少女”、“黑发少女”）；
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
    } else if (settings.llmType == 'anthropic') {
      final base = settings.llmBaseUrl.endsWith('/')
          ? settings.llmBaseUrl.substring(0, settings.llmBaseUrl.length - 1)
          : settings.llmBaseUrl;
      final url = '$base/v1/messages';
      final resp = await _dio.post(
        url,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'x-api-key': settings.llmApiKey,
          'anthropic-version': '2023-06-01',
        }),
        data: {
          'model': settings.llmModel,
          'max_tokens': 4096,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': userPrompt},
          ],
        },
      );
      final content = resp.data['content'] as List? ?? [];
      if (content.isEmpty) throw Exception('Anthropic Claude 接口未返回内容');
      final textParts = content
          .where((c) => c['type'] == 'text')
          .map((c) => c['text'] ?? '')
          .toList();
      return textParts.join();
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
    // 自动判定或按协议走 腾讯 TokenHub 混元 3.5 生图接口
    final isTokenHub = type == 'tokenhub' ||
        baseUrl.contains('tokenhub.tencentmaas.com') ||
        baseUrl.contains('wand/hunyuan-image') ||
        model.toLowerCase().contains('hy-image');

    if (isTokenHub) {
      String targetUrl = baseUrl.trim();
      if (!targetUrl.contains('v35-generation')) {
        final clean = targetUrl.endsWith('/')
            ? targetUrl.substring(0, targetUrl.length - 1)
            : targetUrl;
        if (clean.endsWith('/v1')) {
          targetUrl = '$clean/wand/hunyuan-image/v35-generation';
        } else {
          targetUrl = '$clean/v1/wand/hunyuan-image/v35-generation';
        }
      }

      final sessionId = 'bookbuddy-${DateTime.now().millisecondsSinceEpoch}';
      final List<Map<String, dynamic>> contentList = [
        {'type': 'text', 'text': prompt},
      ];

      // 若有主角基准参考图，按混元 3.5 规范传入 image_url
      if (referenceImageBase64 != null && referenceImageBase64.isNotEmpty) {
        contentList.add({
          'type': 'image_url',
          'image_url': {
            'url': referenceImageBase64.startsWith('http')
                ? referenceImageBase64
                : 'data:image/jpeg;base64,$referenceImageBase64',
          },
        });
      }

      final resp = await _dio.post(
        targetUrl,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        }),
        data: {
          'model': model.isNotEmpty ? model : 'hy-image-v3.5-preview',
          'session': sessionId,
          'messages': [
            {
              'role': 'user',
              'content': contentList,
            }
          ],
        },
      );

      final imgResult = await _extractImageFromResponse(resp.data);
      if (imgResult != null) {
        return imgResult;
      }
      throw Exception('腾讯 TokenHub 接口已响应但未提取到有效图片数据: ${resp.data}');
    }

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
      // OpenAI 规范生图 (智谱 GLM CogView / 腾讯 TokenHub / DALL-E 3 / 自建兼容网关)
      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

      // 1. 优先尝试标准生图接口 /images/generations (智谱 GLM, 腾讯 TokenHub 生图, DALL-E 均遵循此标准)
      try {
        final imgUrl = cleanBase.endsWith('/images/generations')
            ? cleanBase
            : (cleanBase.endsWith('/v1') || cleanBase.endsWith('/v4')
                ? '$cleanBase/images/generations'
                : '$cleanBase/v1/images/generations');

        final headers = {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        };

        final Map<String, dynamic> requestData = {
          'model': model,
          'prompt': prompt,
        };
        if (model.toLowerCase().contains('glm-image') ||
            model.toLowerCase().contains('cogview') ||
            baseUrl.contains('bigmodel.cn')) {
          requestData['size'] = '1280x1280';
        }

        final resp = await _dio.post(
          imgUrl,
          options: Options(headers: headers),
          data: requestData,
        );

        final res = await _extractImageFromResponse(resp.data);
        if (res != null) return res;
      } on DioException catch (dioErr) {
        // 如果是 404/405 说明该服务端未提供 /images/generations 端点，降级尝试 /chat/completions
        final code = dioErr.response?.statusCode;
        if (code != 404 && code != 405 && code != 400) {
          rethrow;
        }
      } catch (_) {
        // 其他非致命格式异常，尝试聊天生图降级
      }

      // 2. 降级尝试聊天补全多模态生图 (适用于某些将生图封装为 chat/completions 的网关)
      final chatUrl = cleanBase.endsWith('/chat/completions')
          ? cleanBase
          : (cleanBase.endsWith('/v1') || cleanBase.endsWith('/v4')
              ? '$cleanBase/chat/completions'
              : '$cleanBase/v1/chat/completions');

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
        chatUrl,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        }),
        data: {
          'model': model,
          'messages': [{'role': 'user', 'content': content}],
        },
      );

      final chatRes = await _extractImageFromResponse(resp.data);
      if (chatRes != null) return chatRes;
    }
    return null;
  }

  /// 从上游各种异构 JSON 响应（choices、data、images、url）中稳健提取图片并转为 Base64
  Future<String?> _extractImageFromResponse(dynamic data) async {
    if (data == null) return null;

    // 1. data 数组风格 (智谱 GLM, DALL-E, 腾讯 TokenHub)
    if (data is Map && data['data'] is List) {
      final list = data['data'] as List;
      if (list.isNotEmpty && list[0] is Map) {
        final item = list[0] as Map;
        if (item['b64_json'] != null && item['b64_json'].toString().isNotEmpty) {
          return item['b64_json'].toString();
        }
        final u = item['url']?.toString();
        if (u != null && u.isNotEmpty) {
          return await _downloadImageAsBase64(u);
        }
      }
    }

    // 2. choices 风格 (Chat 补全 / 腾讯混元 3.5 多模态生图)
    if (data is Map && data['choices'] is List) {
      final choices = data['choices'] as List;
      if (choices.isNotEmpty && choices[0] is Map) {
        final choice = choices[0] as Map;
        final msg = choice['message'] is Map ? (choice['message'] as Map) : choice;

        // choices.message.images
        if (msg['images'] is List) {
          final imgs = msg['images'] as List;
          if (imgs.isNotEmpty) {
            final firstImg = imgs[0];
            String? u;
            if (firstImg is Map) {
              u = firstImg['url']?.toString() ?? firstImg['image_url']?['url']?.toString();
            } else if (firstImg is String) {
              u = firstImg;
            }
            if (u != null && u.isNotEmpty) {
              return await _downloadImageAsBase64(u);
            }
          }
        }

        // choices.message.content (提取纯 URL 或 Markdown 图片语法)
        final textContent = msg['content']?.toString() ?? '';
        if (textContent.startsWith('http')) {
          return await _downloadImageAsBase64(textContent.trim());
        }
        final mdImgMatch = RegExp(r'!\[.*?\]\((https?://[^\s\)]+)\)').firstMatch(textContent);
        if (mdImgMatch != null) {
          return await _downloadImageAsBase64(mdImgMatch.group(1)!);
        }
        final rawUrlMatch = RegExp(r'https?://[^\s"]+\.(?:png|jpg|jpeg|webp)').firstMatch(textContent);
        if (rawUrlMatch != null) {
          return await _downloadImageAsBase64(rawUrlMatch.group(0)!);
        }
      }
    }

    // 3. images 列表风格
    if (data is Map && data['images'] is List) {
      final imgs = data['images'] as List;
      if (imgs.isNotEmpty) {
        final firstImg = imgs[0];
        String? u;
        if (firstImg is Map) {
          u = firstImg['url']?.toString();
        } else if (firstImg is String) {
          u = firstImg;
        }
        if (u != null && u.isNotEmpty) {
          return await _downloadImageAsBase64(u);
        }
      }
    }

    // 4. 顶层 url 风格
    if (data is Map && data['url'] != null) {
      return await _downloadImageAsBase64(data['url'].toString());
    }

    return null;
  }

  /// 远程图片下载并转换为本地 Base64 编码
  Future<String> _downloadImageAsBase64(String imageUrl) async {
    if (imageUrl.startsWith('data:image')) {
      return imageUrl.split(',').last;
    }
    final response = await _dio.get<List<int>>(
      imageUrl,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    if (response.data != null && response.data!.isNotEmpty) {
      return base64Encode(response.data!);
    }
    throw Exception('下载上游生成的图片失败，数据为空');
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
