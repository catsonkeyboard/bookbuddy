import 'dart:convert';

import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:bookbuddy/screens/storyboard_review_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final character = BookCharacter(
    id: 'c1',
    name: '小鹿',
    species: '鹿',
    isAnimal: true,
    appearance: '浅棕毛，左耳有白斑，圆眼睛',
    defaultOutfit: '蓝色围巾',
    referenceImageBase64: 'portrait-base64',
  );

  test('角色档案和每页换装在绘本序列化后保留', () {
    final book = PictureBook(
      id: 'book-1',
      title: '小鹿的旅行',
      styleId: 'watercolor',
      styleName: '水彩',
      pages: [
        BookPageItem(
          pageIndex: 0,
          text: '小鹿出发了。',
          sceneComposition: '小鹿朝向森林小路',
          characterIds: ['c1'],
          outfitOverrides: {'c1': '红色雨衣'},
        ),
      ],
      characters: [character],
      createdAt: DateTime(2026, 1, 1),
    );

    final restored = PictureBook.fromJson(book.toJson());
    expect(restored.characters.single.appearance, contains('左耳有白斑'));
    expect(restored.characters.single.species, '鹿');
    expect(restored.characters.single.isAnimal, isTrue);
    expect(restored.characters.single.referenceImageBase64, 'portrait-base64');
    expect(restored.pages.single.characterIds, ['c1']);
    expect(restored.pages.single.outfitOverrides['c1'], '红色雨衣');
    expect(restored.pages.single.sceneComposition, '小鹿朝向森林小路');
    expect(restored.pages.single.imageReferenceApplied, isFalse);

    final oldJson = book.toJson()..remove('characters');
    final oldPage = (oldJson['pages'] as List).first as Map<String, dynamic>;
    oldPage.remove('characterIds');
    oldPage.remove('outfitOverrides');
    oldPage.remove('sceneComposition');
    final legacy = PictureBook.fromJson(oldJson);
    expect(legacy.characters, isEmpty);
    expect(legacy.pages.single.characterIds, isEmpty);
    expect(legacy.pages.single.outfitOverrides, isEmpty);
    expect(legacy.pages.single.sceneComposition, isEmpty);
  });

  test('页面提示词固定角色外貌，只有明确换装才改变服装', () {
    final engine = BookEngineService();
    final page = BookPageItem(
      pageIndex: 0,
      text: '小鹿走过森林',
      characterIds: ['c1'],
    );
    final normal = engine.composePagePrompt(
      page: page,
      characters: [character],
      scenePrompt: '小鹿站在树下',
    );
    expect(normal, contains('左耳有白斑'));
    expect(normal, contains('本页服装：蓝色围巾'));
    expect(normal, contains('小鹿站在树下'));

    page.outfitOverrides = {'c1': '红色雨衣'};
    final changed = engine.composePagePrompt(
      page: page,
      characters: [character],
      scenePrompt: '小鹿站在雨中',
    );
    expect(changed, contains('本页服装：红色雨衣'));
    expect(changed, isNot(contains('本页服装：蓝色围巾')));
  });

  test('只把真正接收参考图的接口标为支持', () {
    final engine = BookEngineService();
    expect(
      engine.supportsCharacterReference(
        type: 'gemini',
        baseUrl: '',
        model: 'imagen-3.0-generate-002',
      ),
      isFalse,
    );
    expect(
      engine.supportsCharacterReference(
        type: 'gemini',
        baseUrl: '',
        model: 'gemini-2.5-flash-image',
      ),
      isTrue,
    );
    expect(
      engine.supportsCharacterReference(
        type: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        model: 'dall-e-3',
      ),
      isFalse,
    );
    expect(
      engine.supportsCharacterReference(
        type: 'tokenhub',
        baseUrl: '',
        model: 'hy-image-v3.5-preview',
      ),
      isTrue,
    );
  });

  test('Gemini 多模态请求逐个发送角色参考图并保留文字约束', () async {
    final image = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
    character.referenceImageBase64 = image;
    dynamic sent;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent = options.data;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
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
                },
              ),
            );
          },
        ),
      );
    final page = BookPageItem(
      pageIndex: 0,
      text: '小鹿走进森林',
      characterIds: ['c1'],
    );
    final settings = AppSettings(
      imageType: 'gemini',
      imageBaseUrl: 'https://example.test',
      imageModel: 'gemini-image',
      imageApiKey: 'test-key',
    );
    final result = await BookEngineService(dio: dio).generateIllustration(
      settings: settings,
      style: const BookStyle(
        id: 'test',
        name: 'test',
        desc: '',
        prefix: '水彩',
        negative: '',
      ),
      page: page,
      characters: [character],
    );
    expect(result, 'new-image');
    final parts = (sent['contents'][0]['parts'] as List);
    expect(parts.first['inlineData']['mimeType'], 'image/png');
    expect(parts.first['inlineData']['data'], image);
    expect(parts.last['text'], contains('左耳有白斑'));
    expect(page.imageReferenceApplied, isTrue);
    expect(page.imageModelUsed, 'gemini-image');
    expect(BookPageItem.fromJson(page.toJson()).imageReferenceApplied, isTrue);
  });

  test('文字生图请求明确标记参考图未应用', () async {
    dynamic sent;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent = options.data;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'data': [
                    {'b64_json': 'new-image'},
                  ],
                },
              ),
            );
          },
        ),
      );
    final page = BookPageItem(
      pageIndex: 0,
      text: '小鹿走进森林',
      characterIds: ['c1'],
    );
    final settings = AppSettings(
      imageType: 'openai',
      imageBaseUrl: 'https://example.test',
      imageModel: 'dall-e-3',
      imageApiKey: 'test-key',
    );
    await BookEngineService(dio: dio).generateIllustration(
      settings: settings,
      style: const BookStyle(
        id: 'test',
        name: 'test',
        desc: '',
        prefix: '水彩',
        negative: '',
      ),
      page: page,
      characters: [character],
    );
    expect(sent['prompt'], contains('左耳有白斑'));
    expect(sent.containsKey('image'), isFalse);
    expect(page.imageReferenceApplied, isFalse);
  });

  test('参考图通道失败时不静默降级到纯文字通道', () async {
    character.referenceImageBase64 = base64Encode([
      0x89,
      0x50,
      0x4e,
      0x47,
      0,
      0,
      0,
      0,
    ]);
    var requests = 0;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(
              DioException(
                requestOptions: options,
                message: 'primary unavailable',
              ),
            );
          },
        ),
      );
    final settings = AppSettings(
      imageType: 'gemini',
      imageBaseUrl: 'https://example.test',
      imageModel: 'gemini-image',
      imageApiKey: 'test-key',
      enableImageFallback: true,
      fallbackImageType: 'openai',
      fallbackImageBaseUrl: 'https://example.test',
      fallbackImageModel: 'dall-e-3',
      fallbackImageApiKey: 'fallback-key',
    );
    final page = BookPageItem(pageIndex: 0, text: '小鹿', characterIds: ['c1']);
    await expectLater(
      BookEngineService(dio: dio).generateIllustration(
        settings: settings,
        style: const BookStyle(
          id: 'test',
          name: 'test',
          desc: '',
          prefix: '水彩',
          negative: '',
        ),
        page: page,
        characters: [character],
      ),
      throwsA(isA<StateError>()),
    );
    expect(requests, 1);
    expect(page.generationError, contains('不支持角色参考图'));
  });

  test('不来梅四个动物伙伴的集合称呼会展开成驴狗猫公鸡', () async {
    final storyboard = jsonEncode({
      'characters': [
        {
          'id': 'c1',
          'name': '老驴',
          'species': '驴',
          'isAnimal': true,
          'appearance': '灰毛老驴',
          'defaultOutfit': '自然毛皮',
        },
        {
          'id': 'c2',
          'name': '老狗',
          'species': '狗',
          'isAnimal': true,
          'appearance': '棕毛老狗',
          'defaultOutfit': '自然毛皮',
        },
        {
          'id': 'c3',
          'name': '老猫',
          'species': '猫',
          'isAnimal': true,
          'appearance': '黑白花猫',
          'defaultOutfit': '自然毛皮',
        },
        {
          'id': 'c4',
          'name': '公鸡',
          'species': '公鸡',
          'isAnimal': true,
          'appearance': '红冠公鸡',
          'defaultOutfit': '自然羽毛',
        },
      ],
      'groups': {
        '乐队伙伴们': ['c1', 'c2', 'c3', 'c4'],
      },
      'scenes': [
        {
          'text': '四个动物伙伴一同唱歌。',
          'action': '四个动物伙伴站在窗前唱歌',
          'emotion': '兴奋',
          'composition': '四位伙伴面向屋内的强盗，窗户在他们前方',
          'characterIds': ['c1'],
          'outfitOverrides': {},
        },
        {
          'text': '乐队伙伴们继续旅行。',
          'action': '乐队伙伴们走过森林',
          'emotion': '愉快',
          'composition': '伙伴们面向前方小路',
          'characterIds': [],
          'outfitOverrides': {},
        },
      ],
    });
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'choices': [
                  {
                    'message': {'content': storyboard},
                  },
                ],
              },
            ),
          ),
        ),
      );
    final engine = BookEngineService(dio: dio);
    final draft = await engine.createStoryboardDraft(
      settings: AppSettings(
        llmType: 'openai',
        llmBaseUrl: 'https://example.test',
        llmApiKey: 'test',
        llmModel: 'test',
      ),
      title: '不来梅的音乐家',
      storyText: '驴、狗、猫、公鸡一起去不来梅。',
    );
    expect(draft.pages.first.characterIds.toSet(), {'c1', 'c2', 'c3', 'c4'});
    expect(draft.pages.last.characterIds.toSet(), {'c1', 'c2', 'c3', 'c4'});
    final prompt = engine.composePagePrompt(
      page: draft.pages.first,
      characters: draft.characters,
      scenePrompt: '四个动物伙伴唱歌',
    );
    expect(prompt, contains('老猫（猫）'));
    expect(prompt, contains('公鸡（公鸡）'));
    expect(prompt, contains('不能遗漏、替换物种'));
    draft.pages.first.characterIds = ['c1'];
    expect(
      engine.validateSceneCast(
        page: draft.pages.first,
        characters: draft.characters,
      ),
      contains('画面描述有 4 个角色'),
    );
  });

  test('动物未指定鞋子时明确禁止鞋靴，狼朝向动作对象', () {
    final duck = BookCharacter(
      id: 'duck',
      name: '丑小鸭',
      species: '鸭子',
      isAnimal: true,
      appearance: '灰色羽毛的小鸭',
      defaultOutfit: '自然羽毛，无衣服',
    );
    final wolf = BookCharacter(
      id: 'wolf',
      name: '大灰狼',
      species: '狼',
      isAnimal: true,
      appearance: '厚灰毛',
      defaultOutfit: '自然毛皮',
    );
    final engine = BookEngineService();
    final duckPrompt = engine.composePagePrompt(
      page: BookPageItem(pageIndex: 0, text: '小鸭游泳', characterIds: ['duck']),
      characters: [duck],
      scenePrompt: '丑小鸭走在池塘边',
    );
    expect(duckPrompt, contains('没有写鞋靴就不能画鞋靴'));
    final wolfPage = BookPageItem(
      pageIndex: 1,
      text: '狼朝茅草屋吹气',
      characterIds: ['wolf'],
      sceneComposition: '狼在画面左侧侧身面向右侧茅草屋，气流从狼吹向屋子，屋子位于狼前方',
    );
    final wolfPrompt = engine.composePagePrompt(
      page: wolfPage,
      characters: [wolf],
      scenePrompt: '大灰狼鼓起腮帮吹气',
    );
    expect(wolfPrompt, contains('气流从狼吹向屋子'));
    expect(wolfPrompt, contains('不要为了展示正脸而把角色转向观众'));
  });

  testWidgets('分镜审核可核对每页出场角色和换装', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StoryboardReviewScreen(
          title: '小鹿的旅行',
          style: const BookStyle(
            id: 'test',
            name: '水彩',
            desc: '',
            prefix: '水彩',
            negative: '',
          ),
          initialPages: [
            BookPageItem(pageIndex: 0, text: '小鹿出发了', characterIds: ['c1']),
          ],
          initialCharacters: [character],
          settings: AppSettings(),
        ),
      ),
    );
    expect(find.text('添加角色设定'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑本页出场角色与换装'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 页出场角色与换装'), findsOneWidget);
    expect(find.text('小鹿'), findsWidgets);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑正文与画面描述'));
    await tester.pumpAndSettle();
    expect(find.text('🧭 画面朝向与空间关系：'), findsOneWidget);
  });
}
