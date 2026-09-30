import 'dart:convert';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 伪造 OpenAI 兼容协议响应（content 为给定字符串），并记录请求体。
Dio fakeOpenAiDio(String content, List<dynamic> sent) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        sent.add(options.data);
        handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'choices': [
                {
                  'message': {'content': content},
                },
              ],
            },
          ),
        );
      },
    ),
  );

/// 伪造 Gemini generateContent 文本响应，并记录请求体。
Dio fakeGeminiDio(String content, List<dynamic> sent) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        sent.add(options.data);
        handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': content},
                    ],
                  },
                },
              ],
            },
          ),
        );
      },
    ),
  );

AppSettings openAiSettings() => AppSettings(
      llmType: 'openai',
      llmBaseUrl: 'https://example.test',
      llmApiKey: 'test',
      llmModel: 'test',
    );

AppSettings geminiSettings() => AppSettings(
      llmType: 'gemini',
      llmBaseUrl: 'https://example.test',
      llmApiKey: 'test',
      llmModel: 'gemini-test',
    );

CharacterCard dino() => CharacterCard(
      id: 'card_dino1',
      name: '豆豆',
      kind: CharacterKind.animal,
      species: '毛绒恐龙',
      appearance: '绿色毛绒身体，肚皮米白，圆圆的黑眼睛',
      defaultOutfit: '红色小围巾',
      personality: '胆子大、爱冒险',
      catchphrase: '冲啊！',
    );

final storyJson = jsonEncode({
  'title': '豆豆的雨天',
  'story': '豆豆出门了。\n\n雨下大了，豆豆迷路了。\n\n它大喊：冲啊！',
});

void main() {
  test('首次生成：系统提示词含角色设定，用户消息含描述，温度 0.8', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeOpenAiDio(storyJson, sent));
    final result = await engine.composeStory(
      settings: openAiSettings(),
      cards: [dino()],
      brief: '豆豆在雨天迷路了，最后学会向别人求助。',
    );
    expect(result.title, '豆豆的雨天');
    expect(result.story, contains('冲啊！'));

    final body = sent.single as Map;
    expect(body['temperature'], 0.8);
    final system = body['messages'][0]['content'] as String;
    final user = body['messages'][1]['content'] as String;
    expect(system, contains('3 到 8 岁'));
    expect(system, contains('豆豆'));
    expect(system, contains('冲啊！'));
    expect(system, contains('胆子大、爱冒险'));
    expect(system, contains('红色小围巾'));
    expect(system, contains('400 到 700 字'));
    expect(user, contains('豆豆在雨天迷路了，最后学会向别人求助。'));
    expect(user, isNot(contains('当前故事')));
  });

  test('修改模式：用户消息附上当前故事与反馈，并要求只改涉及部分', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeOpenAiDio(storyJson, sent));
    await engine.composeStory(
      settings: openAiSettings(),
      cards: [dino()],
      brief: '豆豆在雨天迷路了。',
      currentStory: '豆豆出门了。它走丢了。（我手改过的一句）',
      feedback: '结局再温暖一点',
    );
    final user = (sent.single as Map)['messages'][1]['content'] as String;
    expect(user, contains('（我手改过的一句）'));
    expect(user, contains('结局再温暖一点'));
    expect(user, contains('只修改反馈涉及的部分，其余保持原文不动'));
    expect(user, contains('若反馈明确要求整体重写则可以重写'));
  });

  test('没有角色卡时提示大模型自行设计角色', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeOpenAiDio(storyJson, sent));
    await engine.composeStory(
      settings: openAiSettings(),
      cards: const [],
      brief: '一只想飞的小猪。',
    );
    final system = (sent.single as Map)['messages'][0]['content'] as String;
    expect(system, contains('自行设计'));
    expect(system, isNot(contains('必须原样使用')));
  });

  test('结果缺少 story 时抛 FormatException', () async {
    final engine = BookEngineService(
      dio: fakeOpenAiDio(jsonEncode({'title': '只有标题'}), []),
    );
    await expectLater(
      engine.composeStory(
        settings: openAiSettings(),
        cards: [dino()],
        brief: '随便讲一个。',
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          '故事生成结果格式不正确',
        ),
      ),
    );
  });

  test('title 缺失时取正文首句前 12 个字', () async {
    final engine = BookEngineService(
      dio: fakeOpenAiDio(
        jsonEncode({'story': '豆豆在雨天迷路了，它很害怕。后来它遇到了小猫。'}),
        [],
      ),
    );
    final result = await engine.composeStory(
      settings: openAiSettings(),
      cards: [dino()],
      brief: '随便讲一个。',
    );
    expect(result.title, '豆豆在雨天迷路了，它很害');
  });

  test('超过上限或描述为空在请求前被拒绝', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeOpenAiDio(storyJson, sent));
    final tooMany = List.generate(
      kMaxCharacterCardsPerBook + 1,
      (i) => CharacterCard(id: 'card_$i', name: '角色$i', appearance: 'x'),
    );
    await expectLater(
      engine.composeStory(
        settings: openAiSettings(),
        cards: tooMany,
        brief: '随便讲一个。',
      ),
      throwsArgumentError,
    );
    await expectLater(
      engine.composeStory(
        settings: openAiSettings(),
        cards: [dino()],
        brief: '   ',
      ),
      throwsArgumentError,
    );
    expect(sent, isEmpty);
  });

  test('Gemini 分支：故事用 0.8，分镜保持 0.3；OpenAI 分镜不带 temperature', () async {
    final geminiSent = <dynamic>[];
    final geminiEngine = BookEngineService(
      dio: fakeGeminiDio(storyJson, geminiSent),
    );
    await geminiEngine.composeStory(
      settings: geminiSettings(),
      cards: [dino()],
      brief: '随便讲一个。',
    );
    expect(
      (geminiSent.single as Map)['generationConfig']['temperature'],
      0.8,
    );

    final storyboard = jsonEncode({
      'characters': [],
      'groups': {},
      'scenes': [
        {
          'text': '从前有座山。',
          'action': '',
          'emotion': '',
          'composition': '',
          'characterIds': [],
          'outfitOverrides': {},
        },
      ],
    });
    final geminiBoard = <dynamic>[];
    await BookEngineService(dio: fakeGeminiDio(storyboard, geminiBoard))
        .createStoryboardDraft(
      settings: geminiSettings(),
      title: '山',
      storyText: '从前有座山。',
    );
    expect(
      (geminiBoard.single as Map)['generationConfig']['temperature'],
      0.3,
    );

    final openAiBoard = <dynamic>[];
    await BookEngineService(dio: fakeOpenAiDio(storyboard, openAiBoard))
        .createStoryboardDraft(
      settings: openAiSettings(),
      title: '山',
      storyText: '从前有座山。',
    );
    expect((openAiBoard.single as Map).containsKey('temperature'), isFalse);
  });
}
