import 'dart:convert';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  test('故事分镜与故事页请求都不包含角色卡照片', () async {
    const photo = 'UEhPVE9fTUFSS0VS'; // base64("PHOTO_MARKER")
    final anchor = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
    final card = CharacterCard(
      id: 'card_dino1',
      name: '豆豆',
      kind: CharacterKind.animal,
      species: '毛绒恐龙',
      appearance: '绿色毛绒恐龙',
      photoPath: 'card_dino1/photo.jpg',
    );
    final storyboard = jsonEncode({
      'characters': [
        {
          'id': 'card_dino1',
          'name': '豆豆',
          'species': '毛绒恐龙',
          'isAnimal': true,
          'appearance': '绿色毛绒恐龙',
          'defaultOutfit': '',
        },
      ],
      'groups': {},
      'scenes': [
        {
          'text': '豆豆出门了。',
          'action': '豆豆走出家门',
          'emotion': '',
          'composition': '',
          'characterIds': ['card_dino1'],
          'outfitOverrides': {},
        },
      ],
    });

    final llmSent = <dynamic>[];
    final draft = await BookEngineService(
      dio: recordingDio(llmSent, () => {
            'choices': [
              {
                'message': {'content': storyboard},
              },
            ],
          }),
    ).createStoryboardDraft(
      settings: AppSettings(
        llmType: 'openai',
        llmBaseUrl: 'https://example.test',
        llmApiKey: 'k',
        llmModel: 'm',
      ),
      title: '豆豆的一天',
      storyText: '豆豆出门了。',
      pinnedCharacters: [PinnedCharacter(card: card, anchorBase64: anchor, photoBase64: photo)],
    );
    expect(jsonEncode(llmSent.single), isNot(contains(photo)));

    final imageSent = <dynamic>[];
    await BookEngineService(
      dio: recordingDio(imageSent, () => {
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
    ).generateIllustration(
      settings: AppSettings(
        imageType: 'gemini',
        imageBaseUrl: 'https://example.test',
        imageModel: 'gemini-2.5-flash-image',
        imageApiKey: 'k',
      ),
      style: const BookStyle(id: 'watercolor', name: '水彩童话', desc: '', prefix: '水彩', negative: ''),
      page: draft.pages.single,
      characters: draft.characters,
    );
    final pageBody = jsonEncode(imageSent.single);
    expect(pageBody, isNot(contains(photo)));
    expect(pageBody, contains(anchor));
  });
}
