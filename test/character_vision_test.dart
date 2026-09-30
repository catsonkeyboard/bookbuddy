import 'dart:convert';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 按顺序对每个请求返回 [responder] 的结果，并记录请求体。
Dio recordingDio(List<dynamic> sent, Map<String, dynamic> Function() responder) =>
    Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent.add(options.data);
            handler.resolve(Response(requestOptions: options, data: responder()));
          },
        ),
      );

Map<String, dynamic> openAiReply(String content) => {
      'choices': [
        {
          'message': {'content': content},
        },
      ],
    };

Map<String, dynamic> geminiReply(String content) => {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': content},
            ],
          },
        },
      ],
    };

Map<String, dynamic> anthropicReply(String content) => {
      'content': [
        {'type': 'text', 'text': content},
      ],
    };

final draftJson = jsonEncode({
  'name': '小满',
  'kind': 'object',
  'species': '鹅卵石',
  'appearance': '圆润的灰色鹅卵石，表面有白色斑点',
  'defaultOutfit': '',
  'personality': '慢吞吞但很可靠',
  'catchphrase': '别急，我在这儿',
});

const photo = '/9j/4AAQSkZJRgABAQAAAQABAAD';

AppSettings llm(String type) => AppSettings(
      llmType: type,
      llmBaseUrl: 'https://example.test',
      llmApiKey: 'test',
      llmModel: 'vision-model',
    );

const style = BookStyle(
  id: 'watercolor',
  name: '水彩童话',
  desc: '',
  prefix: '水彩',
  negative: '',
);

final stone = BookCharacter(
  id: 'card_stone',
  name: '小满',
  species: '鹅卵石',
  appearance: '圆润的灰色鹅卵石',
  defaultOutfit: '无服装，保持物件本来的外观',
);

void main() {
  test('OpenAI 兼容：图片以 data URL 放在文本前，解析出角色草稿', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: recordingDio(sent, () => openAiReply(draftJson)));
    final draft = await engine.describeCharacterFromPhoto(
      settings: llm('openai'),
      photoBase64: photo,
      mimeType: 'image/jpeg',
    );
    expect(draft.name, '小满');
    expect(draft.kind, CharacterKind.object);
    expect(draft.species, '鹅卵石');
    expect(draft.appearance, contains('灰色鹅卵石'));
    expect(draft.defaultOutfit, '');
    expect(draft.catchphrase, '别急，我在这儿');

    final body = sent.single as Map;
    final system = body['messages'][0]['content'] as String;
    expect(system, contains('2 到 4 个汉字'));
    expect(system, contains('不写背景'));
    final content = body['messages'][1]['content'] as List;
    expect(content.first['type'], 'image_url');
    expect(content.first['image_url']['url'], 'data:image/jpeg;base64,$photo');
    expect(content.last['type'], 'text');
    expect(body.containsKey('temperature'), isFalse);
  });

  test('Gemini：inlineData 在文本之前，温度保持默认 0.3', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: recordingDio(sent, () => geminiReply(draftJson)));
    await engine.describeCharacterFromPhoto(
      settings: llm('gemini'),
      photoBase64: photo,
      mimeType: 'image/jpeg',
    );
    final body = sent.single as Map;
    final parts = body['contents'][0]['parts'] as List;
    expect(parts.first['inlineData'], {'mimeType': 'image/jpeg', 'data': photo});
    expect(parts.last['text'], isA<String>());
    expect(body['generationConfig']['temperature'], 0.3);
  });

  test('Anthropic：image source 块在文本之前', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: recordingDio(sent, () => anthropicReply(draftJson)));
    await engine.describeCharacterFromPhoto(
      settings: llm('anthropic'),
      photoBase64: photo,
      mimeType: 'image/jpeg',
    );
    final content = (sent.single as Map)['messages'][0]['content'] as List;
    expect(content.first, {
      'type': 'image',
      'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': photo},
    });
    expect(content.last['type'], 'text');
  });

  test('没有图片时三种协议的用户消息保持原样', () async {
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
    final openAiSent = <dynamic>[];
    await BookEngineService(dio: recordingDio(openAiSent, () => openAiReply(storyboard)))
        .createStoryboardDraft(settings: llm('openai'), title: '山', storyText: '从前有座山。');
    expect((openAiSent.single as Map)['messages'][1]['content'], isA<String>());

    final anthropicSent = <dynamic>[];
    await BookEngineService(dio: recordingDio(anthropicSent, () => anthropicReply(storyboard)))
        .createStoryboardDraft(settings: llm('anthropic'), title: '山', storyText: '从前有座山。');
    expect((anthropicSent.single as Map)['messages'][0]['content'], isA<String>());

    final geminiSent = <dynamic>[];
    await BookEngineService(dio: recordingDio(geminiSent, () => geminiReply(storyboard)))
        .createStoryboardDraft(settings: llm('gemini'), title: '山', storyText: '从前有座山。');
    expect((geminiSent.single as Map)['contents'][0]['parts'], hasLength(1));
  });

  test('缺少必填字段或 JSON 损坏时给出约定的格式错误；未知 kind 取 animal', () async {
    final missing = BookEngineService(
      dio: recordingDio([], () => openAiReply(jsonEncode({'name': '小满', 'kind': 'object'}))),
    );
    await expectLater(
      missing.describeCharacterFromPhoto(settings: llm('openai'), photoBase64: photo, mimeType: 'image/jpeg'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', '识图结果格式不正确')),
    );

    const broken = '{"name": "小满", "kind": "object", "appearance": "第一行\n第二行 "引号""}';
    final corrupt = BookEngineService(dio: recordingDio([], () => openAiReply(broken)));
    await expectLater(
      corrupt.describeCharacterFromPhoto(settings: llm('openai'), photoBase64: photo, mimeType: 'image/jpeg'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', '识图结果格式不正确')),
    );

    final unknownKind = BookEngineService(
      dio: recordingDio([], () => openAiReply(jsonEncode({'name': '豆豆', 'kind': 'dragon', 'appearance': '绿色毛绒'}))),
    );
    final draft = await unknownKind.describeCharacterFromPhoto(
      settings: llm('openai'),
      photoBase64: photo,
      mimeType: 'image/jpeg',
    );
    expect(draft.kind, CharacterKind.animal);
    expect(draft.species, '');
  });

  test('分镜回复是损坏的 JSON 时不再抛出 Dart 原始异常，而是得到空分镜', () async {
    const broken = '{"scenes": [{"text": "第一行\n第二行 "引号""}]}';
    final draft = await BookEngineService(dio: recordingDio([], () => openAiReply(broken)))
        .createStoryboardDraft(settings: llm('openai'), title: '山', storyText: '从前有座山。');
    expect(draft.pages, isEmpty);
  });

  test('支持参考图的通道：定妆照请求带上照片与照片说明', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: recordingDio(sent, () => {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'inlineData': {'data': 'new-image'},
                    },
                  ],
                },
              },
            ],
          }),
    );
    final result = await engine.generateCharacterReference(
      settings: AppSettings(
        imageType: 'gemini',
        imageBaseUrl: 'https://example.test',
        imageModel: 'gemini-2.5-flash-image',
        imageApiKey: 'k',
      ),
      style: style,
      character: stone,
      photoReferenceBase64: photo,
    );
    expect(result, 'new-image');
    final parts = (sent.single as Map)['contents'][0]['parts'] as List;
    expect(parts.first['inlineData']['data'], photo);
    expect(parts[1]['text'], contains('真实玩具或物件照片'));
    expect(parts[1]['text'], contains('忽略照片的背景、光线和拍摄角度'));
    expect(parts.last['text'], contains('单独绘制角色定妆照'));
  });

  test('不支持参考图的通道：照片被忽略，请求里没有照片', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: recordingDio(sent, () => {
            'predictions': [
              {'bytesBase64Encoded': 'new-image'},
            ],
          }),
    );
    await engine.generateCharacterReference(
      settings: AppSettings(
        imageType: 'gemini',
        imageBaseUrl: 'https://example.test',
        imageModel: 'imagen-3.0-generate-002',
        imageApiKey: 'k',
      ),
      style: style,
      character: stone,
      photoReferenceBase64: photo,
    );
    expect(jsonEncode(sent.single), isNot(contains(photo)));
  });

  test('定妆照仍按原文案标注，照片说明只出现在照片参考上', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: recordingDio(sent, () => {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'inlineData': {'data': 'page'},
                    },
                  ],
                },
              },
            ],
          }),
    );
    final anchored = BookCharacter.fromJson(stone.toJson())
      ..referenceImageBase64 = photo;
    await engine.generateIllustration(
      settings: AppSettings(
        imageType: 'gemini',
        imageBaseUrl: 'https://example.test',
        imageModel: 'gemini-2.5-flash-image',
        imageApiKey: 'k',
      ),
      style: style,
      page: BookPageItem(pageIndex: 0, text: '小满在河边。', characterIds: ['card_stone']),
      characters: [anchored],
    );
    final text = jsonEncode(sent.single);
    expect(text, contains('的定妆照'));
    expect(text, isNot(contains('真实玩具或物件照片')));
  });
}
