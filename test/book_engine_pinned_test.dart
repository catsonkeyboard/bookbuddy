import 'dart:convert';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 伪造 OpenAI 兼容协议的分镜响应，并记录请求体。
Dio fakeLlmDio(Map<String, dynamic> storyboard, List<dynamic> sent) => Dio()
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
                  'message': {'content': jsonEncode(storyboard)},
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

Map<String, dynamic> scene({
  required String text,
  String action = '',
  List<String> ids = const [],
  Map<String, String> outfits = const {},
}) =>
    {
      'text': text,
      'action': action,
      'emotion': '',
      'composition': '',
      'characterIds': ids,
      'outfitOverrides': outfits,
    };

void main() {
  test('有固定角色时系统提示词追加固定角色段落', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [
          {
            'id': 'card_dino1',
            'name': '豆豆',
            'species': '毛绒恐龙',
            'isAnimal': true,
            'appearance': '绿色毛绒身体，肚皮米白，圆圆的黑眼睛',
            'defaultOutfit': '红色小围巾',
          },
        ],
        'groups': {},
        'scenes': [
          scene(text: '豆豆喊：冲啊！', ids: ['card_dino1']),
        ],
      }, sent),
    );
    await engine.createStoryboardDraft(
      settings: openAiSettings(),
      title: '豆豆的雨天',
      storyText: '豆豆在雨天迷路了。',
      pinnedCharacters: [PinnedCharacter(card: dino(), anchorBase64: 'anchor')],
    );
    final system = sent.single['messages'][0]['content'] as String;
    expect(system, contains('【固定角色，必须原样使用】'));
    expect(system, contains('id: card_dino1'));
    expect(system, contains('名字：豆豆'));
    expect(system, contains('口头禅：冲啊！'));
    expect(system, contains('性格：胆子大、爱冒险'));
    expect(system, contains('默认服装：红色小围巾'));
  });

  test('固定角色没有口头禅和性格时不要求大模型体现它们', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [
          {
            'id': 'card_plain',
            'name': '小满',
            'species': '',
            'isAnimal': false,
            'appearance': '灰色鹅卵石',
            'defaultOutfit': '',
          },
        ],
        'groups': {},
        'scenes': [
          scene(text: '小满滚下山坡。', ids: ['card_plain']),
        ],
      }, sent),
    );
    await engine.createStoryboardDraft(
      settings: openAiSettings(),
      title: '小满',
      storyText: '小满滚下山坡。',
      pinnedCharacters: [
        PinnedCharacter(
          card: CharacterCard(
            id: 'card_plain',
            name: '小满',
            kind: CharacterKind.object,
            appearance: '灰色鹅卵石',
            personality: '  ',
            catchphrase: '',
          ),
        ),
      ],
    );
    final system = sent.single['messages'][0]['content'] as String;
    expect(system, contains('2. 故事需要主角时优先使用上述角色'));
    expect(system, isNot(contains('口头禅要自然地出现')));
    // 基础提示词里另有「3. 【画面动作…」，只检查固定角色段落内部。
    final block = system.substring(system.indexOf('【固定角色，必须原样使用】'));
    expect(block, isNot(contains('3. ')));
  });

  test('没有固定角色时提示词不含固定角色段落', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [],
        'groups': {},
        'scenes': [scene(text: '从前有座山。')],
      }, sent),
    );
    await engine.createStoryboardDraft(
      settings: openAiSettings(),
      title: '山',
      storyText: '从前有座山。',
    );
    final system = sent.single['messages'][0]['content'] as String;
    expect(system, isNot(contains('【固定角色，必须原样使用】')));
  });

  test('规则一：同 id 条目被卡片字段覆盖并带上定妆图', () async {
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [
          {
            'id': 'card_dino1',
            'name': '豆豆',
            'species': '蜥蜴',
            'isAnimal': true,
            'appearance': '大模型乱改的外貌',
            'defaultOutfit': '大模型乱加的帽子',
          },
        ],
        'groups': {},
        'scenes': [
          scene(text: '豆豆出发。', ids: ['card_dino1']),
        ],
      }, []),
    );
    final draft = await engine.createStoryboardDraft(
      settings: openAiSettings(),
      title: 't',
      storyText: 's',
      pinnedCharacters: [PinnedCharacter(card: dino(), anchorBase64: 'anchor-b64')],
    );
    final c = draft.characters.singleWhere((c) => c.id == 'card_dino1');
    expect(c.species, '毛绒恐龙');
    expect(c.appearance, '绿色毛绒身体，肚皮米白，圆圆的黑眼睛');
    expect(c.defaultOutfit, '红色小围巾');
    expect(c.isAnimal, isTrue);
    expect(c.referenceImageBase64, 'anchor-b64');
    expect(draft.characters, hasLength(1));
  });

  test('规则二：大模型另造的同名角色被合并到卡片 id，页面引用与换装一并改写', () async {
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [
          {
            'id': 'c1',
            'name': '豆豆',
            'species': '恐龙',
            'isAnimal': true,
            'appearance': '另一个豆豆',
            'defaultOutfit': '',
          },
          {
            'id': 'c2',
            'name': '小猫',
            'species': '猫',
            'isAnimal': true,
            'appearance': '橘猫',
            'defaultOutfit': '自然毛皮',
          },
        ],
        'groups': {},
        'scenes': [
          scene(text: '豆豆和小猫玩。', ids: ['c1', 'c2'], outfits: {'c1': '雨衣'}),
          scene(text: '小猫睡觉。', ids: ['c2']),
        ],
      }, []),
    );
    final draft = await engine.createStoryboardDraft(
      settings: openAiSettings(),
      title: 't',
      storyText: 's',
      pinnedCharacters: [PinnedCharacter(card: dino())],
    );
    expect(draft.characters.map((c) => c.id).toList(), ['card_dino1', 'c2']);
    expect(draft.characters.first.appearance, '绿色毛绒身体，肚皮米白，圆圆的黑眼睛');
    expect(draft.pages.first.characterIds, ['card_dino1', 'c2']);
    expect(draft.pages.first.outfitOverrides, {'card_dino1': '雨衣'});
    expect(draft.pages.last.characterIds, ['c2']);
  });

  test('规则三：卡片未被列入名单但名字出现在页面里时按名字补漏', () async {
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [
          {
            'id': 'c1',
            'name': '小猫',
            'species': '猫',
            'isAnimal': true,
            'appearance': '橘猫',
            'defaultOutfit': '自然毛皮',
          },
        ],
        'groups': {},
        'scenes': [
          scene(text: '小猫在等。', ids: ['c1']),
          scene(text: '这时豆豆跑来了，大喊冲啊！', action: '豆豆冲进画面', ids: ['c1']),
        ],
      }, []),
    );
    final draft = await engine.createStoryboardDraft(
      settings: openAiSettings(),
      title: 't',
      storyText: 's',
      pinnedCharacters: [PinnedCharacter(card: dino())],
    );
    expect(draft.characters.first.id, 'card_dino1');
    expect(draft.pages.first.characterIds, ['c1']);
    expect(draft.pages.last.characterIds, ['c1', 'card_dino1']);
  });

  test('规则四：卡片完全没有出场时抛出可读的 StateError', () async {
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [],
        'groups': {},
        'scenes': [scene(text: '从前有座山。')],
      }, []),
    );
    await expectLater(
      engine.createStoryboardDraft(
        settings: openAiSettings(),
        title: 't',
        storyText: 's',
        pinnedCharacters: [PinnedCharacter(card: dino())],
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          '角色卡「豆豆」没有出现在任何分镜中。请在故事里写到它，或取消选择该角色卡。',
        ),
      ),
    );
  });

  test('超过上限的角色卡在请求前就被拒绝', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeLlmDio({'scenes': []}, sent));
    final cards = List.generate(
      kMaxCharacterCardsPerBook + 1,
      (i) => PinnedCharacter(
        card: CharacterCard(id: 'card_$i', name: '角色$i', appearance: 'x'),
      ),
    );
    await expectLater(
      engine.createStoryboardDraft(
        settings: openAiSettings(),
        title: 't',
        storyText: 's',
        pinnedCharacters: cards,
      ),
      throwsArgumentError,
    );
    expect(sent, isEmpty);
  });

  test('两张同名角色卡在请求前就被拒绝', () async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeLlmDio({'scenes': []}, sent));
    final twin = CharacterCard(
      id: 'card_dino2',
      name: '豆豆',
      appearance: '另一只豆豆',
    );
    await expectLater(
      engine.createStoryboardDraft(
        settings: openAiSettings(),
        title: 't',
        storyText: 's',
        pinnedCharacters: [
          PinnedCharacter(card: dino()),
          PinnedCharacter(card: twin),
        ],
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('两张都叫「豆豆」'),
        ),
      ),
    );
    expect(sent, isEmpty);
  });
}
