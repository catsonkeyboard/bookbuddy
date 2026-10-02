import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/create_book_screen.dart';
import 'package:bookbuddy/screens/story_composer_screen.dart';
import 'package:bookbuddy/screens/storyboard_review_screen.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在真实事件循环里执行会产生文件 IO 的操作，然后交替「让出真实时间片」与
/// 「冲刷一次 FakeAsync 微任务队列」，直到 [until] 成立或达到 [maxRounds]。
Future<void> runIo(
  WidgetTester tester,
  Future<void> Function() body, {
  bool Function()? until,
  int maxRounds = 60,
}) async {
  await tester.runAsync(body);
  for (var i = 0; i < maxRounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    if (until != null && until()) break;
  }
  await tester.pumpAndSettle();
}

CharacterCard card(String id, String name, {Map<String, String>? anchors}) =>
    CharacterCard(
      id: id,
      name: name,
      appearance: '外貌 $name',
      catchphrase: '$name 来啦',
      anchorImagePaths: anchors,
    );

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
                {'message': {'content': jsonEncode(storyboard)}},
              ],
            },
          ),
        );
      },
    ),
  );

void main() {
  late Directory dir;
  late CharacterStorageService storage;

  setUp(() {
    // 故事助手页用 SharedPreferences 存草稿；测试里没有真实平台通道，必须先挂上 mock。
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('bookbuddy-create-test-');
    storage = CharacterStorageService(directory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpCreate(
    WidgetTester tester, {
    BookEngineService? engine,
    AppSettings? settings,
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await runIo(
      tester,
      () => tester.pumpWidget(
        MaterialApp(
          home: CreateBookScreen(
            characterStorage: storage,
            engine: engine,
            loadSettings: () async =>
                settings ??
                AppSettings(
                  imageType: 'gemini',
                  imageApiKey: 'test-key',
                  imageModel: 'gemini-2.5-flash-image',
                ),
          ),
        ),
      ),
      until: () => find.text('👥 选择角色卡（可选，最多 3 张）').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
  }

  testWidgets('角色库为空时显示去创建角色入口', (tester) async {
    await pumpCreate(tester);
    expect(find.text('去创建角色'), findsOneWidget);
  });

  testWidgets('最多选择三张角色卡，第四张被拒绝并提示', (tester) async {
    await tester.runAsync(() async {
      for (final c in [
        card('card_a', '豆豆', anchors: {'watercolor': 'card_a/anchor_watercolor.png'}),
        card('card_b', '小满'),
        card('card_c', '阿福'),
        card('card_d', '毛毛'),
      ]) {
        await storage.saveCard(c);
      }
    });
    await pumpCreate(tester);

    for (final name in ['豆豆', '小满', '阿福']) {
      await tester.tap(find.widgetWithText(FilterChip, name));
      await tester.pumpAndSettle();
    }
    expect(find.text('豆豆 · 豆豆 来啦'), findsOneWidget);
    expect(find.text('在故事里直接用名字称呼他们'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '毛毛'));
    await tester.pumpAndSettle();
    expect(find.text('每本绘本最多选择 3 张角色卡'), findsOneWidget);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '毛毛')).selected, isFalse);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '豆豆')).selected, isTrue);

    // 小满、阿福没有水彩定妆图，豆豆有。
    expect(find.text('将直接使用 豆豆 已有的该画风定妆照'), findsOneWidget);
    expect(
      find.text('小满、阿福 还没有该画风的定妆照，生成分镜前会询问是否现在绘制'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilterChip, '豆豆'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, '豆豆')).selected, isFalse);
    expect(find.text('豆豆 · 豆豆 来啦'), findsNothing);
  });

  testWidgets('生图通道不支持参考图时提示定妆图不会被使用', (tester) async {
    await tester.runAsync(() => storage.saveCard(card('card_a', '豆豆')));
    await pumpCreate(tester, settings: AppSettings(imageApiKey: 'test-key'));
    await tester.tap(find.widgetWithText(FilterChip, '豆豆'));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前生图通道不支持参考图'), findsOneWidget);
    expect(find.textContaining('还没有该画风的定妆照'), findsNothing);
  });

  group('已选卡片缺少当前画风定妆照', () {
    final png = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
    final photoBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 9, 9, 9, 9]);
    final storyboard = {
      'characters': [
        {
          'id': 'card_a',
          'name': '豆豆',
          'species': '',
          'isAnimal': true,
          'appearance': '外貌 豆豆',
          'defaultOutfit': '',
        },
      ],
      'groups': {},
      'scenes': [
        {
          'text': '豆豆出发。',
          'action': '豆豆走出家门',
          'emotion': '',
          'composition': '',
          'characterIds': ['card_a'],
          'outfitOverrides': {},
        },
      ],
    };

    /// 同一个 Dio 既答分镜（OpenAI 协议）也答生图（Gemini 协议），分别记录请求体。
    Dio fakeDio(List<dynamic> llmSent, List<dynamic> imageSent) => Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final isImage = options.uri.toString().contains('generateContent');
            (isImage ? imageSent : llmSent).add(options.data);
            handler.resolve(
              Response(
                requestOptions: options,
                data: isImage
                    ? {
                        'candidates': [
                          {
                            'content': {
                              'parts': [
                                {
                                  'inlineData': {'mimeType': 'image/png', 'data': png},
                                },
                              ],
                            },
                          },
                        ],
                      }
                    : {
                        'choices': [
                          {'message': {'content': jsonEncode(storyboard)}},
                        ],
                      },
              ),
            );
          },
        ),
      );

    /// 豆豆只有黏土画风的定妆照，新书选的是默认的水彩画风。
    Future<void> pumpWithCardMissingWatercolor(
      WidgetTester tester,
      List<dynamic> llmSent,
      List<dynamic> imageSent,
    ) async {
      await tester.runAsync(() async {
        final c = card('card_a', '豆豆')
          ..photoPath = await storage.writeImage('card_a', 'photo.jpg', photoBytes);
        await storage.saveCard(c);
        await storage.saveAnchor('card_a', 'claymation', png);
      });
      await pumpCreate(
        tester,
        engine: BookEngineService(dio: fakeDio(llmSent, imageSent)),
        settings: AppSettings(
          llmType: 'openai',
          llmBaseUrl: 'https://example.test',
          llmApiKey: 'k',
          llmModel: 'm',
          imageType: 'gemini',
          imageApiKey: 'test-key',
          imageModel: 'gemini-2.5-flash-image',
        ),
      );
      await tester.tap(find.widgetWithText(FilterChip, '豆豆'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '可直接粘贴故事全文；若留空仅填书名，AI 将自动构思并续写完整童话...'),
        '豆豆在雨天迷路了。',
      );
      await tester.pump();
    }

    /// 在真实事件循环里点生成：确认后的请求沿用这次点击的 zone。
    Future<void> tapGenerateAndWaitForDialog(WidgetTester tester) => runIo(
          tester,
          () => tester.tap(find.text('🎬 分析故事并生成分镜 (进入审核)')),
          until: () => find.text('缺少「水彩童话」画风的定妆照').evaluate().isNotEmpty,
        );

    Map<String, dynamic> savedCard() =>
        (jsonDecode(File('${dir.path}/cards.json').readAsStringSync()) as List).single
            as Map<String, dynamic>;

    testWidgets('生成分镜前先询问；取消则什么都不请求', (tester) async {
      final llmSent = <dynamic>[];
      final imageSent = <dynamic>[];
      await pumpWithCardMissingWatercolor(tester, llmSent, imageSent);

      await tapGenerateAndWaitForDialog(tester);
      expect(find.textContaining('「豆豆」还没有「水彩童话」画风的定妆照'), findsOneWidget);
      expect(find.textContaining('「豆豆」已有的画风：3D黏土定格'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await runIo(tester, () async {}, maxRounds: 5);

      expect(llmSent, isEmpty);
      expect(imageSent, isEmpty);
      expect(find.byType(StoryboardReviewScreen), findsNothing);
      expect(find.text('🎬 分析故事并生成分镜 (进入审核)'), findsOneWidget);
    });

    testWidgets('选「现在生成」先画定妆照并写回角色卡，再带着它进入审核', (tester) async {
      final llmSent = <dynamic>[];
      final imageSent = <dynamic>[];
      await pumpWithCardMissingWatercolor(tester, llmSent, imageSent);

      await tapGenerateAndWaitForDialog(tester);
      await runIo(
        tester,
        () => tester.tap(find.text('现在生成')),
        until: () => find.byType(StoryboardReviewScreen).evaluate().isNotEmpty,
        maxRounds: 160,
      );

      // 定妆照请求带着卡片照片，结果写回角色卡。
      expect(imageSent, hasLength(1));
      expect(jsonEncode(imageSent.single), contains(base64Encode(photoBytes)));
      expect(savedCard()['anchorImagePaths'], {
        'claymation': 'card_a/anchor_claymation.png',
        'watercolor': 'card_a/anchor_watercolor.png',
      });
      expect(File('${dir.path}/card_a/anchor_watercolor.png').existsSync(), isTrue);

      final review = tester.widget<StoryboardReviewScreen>(find.byType(StoryboardReviewScreen));
      expect(review.pinnedCharacters.single.anchorBase64, png);
      expect(review.pinnedCharacters.single.card.anchorImagePaths, contains('watercolor'));
      expect(review.initialCharacters.single.referenceImageBase64, png);
      expect(llmSent, hasLength(1));
    });

    testWidgets('选「暂不生成」直接生成分镜，定妆照留到审核页', (tester) async {
      final llmSent = <dynamic>[];
      final imageSent = <dynamic>[];
      await pumpWithCardMissingWatercolor(tester, llmSent, imageSent);

      await tapGenerateAndWaitForDialog(tester);
      await runIo(
        tester,
        () => tester.tap(find.text('暂不生成')),
        until: () => find.byType(StoryboardReviewScreen).evaluate().isNotEmpty,
        maxRounds: 160,
      );

      expect(imageSent, isEmpty);
      expect(savedCard()['anchorImagePaths'], {'claymation': 'card_a/anchor_claymation.png'});
      final review = tester.widget<StoryboardReviewScreen>(find.byType(StoryboardReviewScreen));
      expect(review.pinnedCharacters.single.anchorBase64, isNull);
      expect(review.initialCharacters.single.referenceImageBase64, isNull);
      expect(find.text('先生成角色定妆照'), findsOneWidget);
    });
  });

  testWidgets('生成时把已选卡片的定妆图与 id 传给引擎和审核页', (tester) async {
    final png = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
    final photoBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 9, 9, 9, 9]);
    await tester.runAsync(() async {
      final c = card('card_a', '豆豆')
        ..photoPath = await storage.writeImage('card_a', 'photo.jpg', photoBytes);
      await storage.saveCard(c);
      await storage.saveAnchor('card_a', 'watercolor', png);
    });
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: fakeLlmDio({
        'characters': [
          {
            'id': 'card_a',
            'name': '豆豆',
            'species': '',
            'isAnimal': true,
            'appearance': '外貌 豆豆',
            'defaultOutfit': '',
          },
        ],
        'groups': {},
        'scenes': [
          {
            'text': '豆豆出发。',
            'action': '豆豆走出家门',
            'emotion': '',
            'composition': '',
            'characterIds': ['card_a'],
            'outfitOverrides': {},
          },
        ],
      }, sent),
    );
    await pumpCreate(
      tester,
      engine: engine,
      settings: AppSettings(
        llmType: 'openai',
        llmBaseUrl: 'https://example.test',
        llmApiKey: 'k',
        llmModel: 'm',
        imageType: 'gemini',
        imageApiKey: 'test-key',
        imageModel: 'gemini-2.5-flash-image',
      ),
    );
    await tester.tap(find.widgetWithText(FilterChip, '豆豆'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '可直接粘贴故事全文；若留空仅填书名，AI 将自动构思并续写完整童话...'),
      '豆豆在雨天迷路了。',
    );
    await tester.pump();

    await runIo(
      tester,
      () => tester.tap(find.text('🎬 分析故事并生成分镜 (进入审核)')),
      until: () => find.byType(StoryboardReviewScreen).evaluate().isNotEmpty,
      maxRounds: 120,
    );

    final review = tester.widget<StoryboardReviewScreen>(find.byType(StoryboardReviewScreen));
    expect(review.characterCardIds, ['card_a']);
    expect(review.pinnedCharacters.single.card.id, 'card_a');
    expect(review.pinnedCharacters.single.anchorBase64, png);
    expect(review.initialCharacters.single.id, 'card_a');
    expect(review.initialCharacters.single.referenceImageBase64, png);
    expect(sent.single['messages'][0]['content'] as String, contains('【固定角色，必须原样使用】'));
    expect(review.pinnedCharacters.single.photoBase64, base64Encode(photoBytes));
    expect(jsonEncode(sent.single), isNot(contains(base64Encode(photoBytes))));
  });

  testWidgets('入口按钮带着已选角色卡打开故事助手，用这个故事后回填标题与正文', (tester) async {
    await tester.runAsync(() => storage.saveCard(card('card_a', '豆豆')));
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: fakeLlmDio({'title': '豆豆的雨天', 'story': '豆豆出门了。\n\n它迷路了。'}, sent),
    );
    await pumpCreate(
      tester,
      engine: engine,
      settings: AppSettings(
        llmType: 'openai',
        llmBaseUrl: 'https://example.test',
        llmApiKey: 'k',
        llmModel: 'm',
        imageType: 'gemini',
        imageApiKey: 'test-key',
        imageModel: 'gemini-2.5-flash-image',
      ),
    );
    await tester.tap(find.widgetWithText(FilterChip, '豆豆'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('让 AI 按角色写故事'));
    await tester.pumpAndSettle();
    final composer = tester.widget<StoryComposerScreen>(find.byType(StoryComposerScreen));
    expect(composer.cards.single.id, 'card_a');

    await tester.enterText(
      find.widgetWithText(
        TextField,
        '你想讲一个什么样的故事？比如：豆豆和小满在雨天迷路了，最后学会互相帮助',
      ),
      '豆豆在雨天迷路了。',
    );
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('生成故事')),
      until: () => find.text('用这个故事').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('用这个故事'));
    await tester.pumpAndSettle();

    expect(find.byType(StoryComposerScreen), findsNothing);
    final title = tester.widget<TextField>(
      find.widgetWithText(TextField, '故事标题（如：小红帽的故事、三只小猪）'),
    );
    expect(title.controller!.text, '豆豆的雨天');
    expect(find.textContaining('豆豆出门了。'), findsOneWidget);
    expect(sent, hasLength(1));
  });

  testWidgets('正文已有内容时回填前先确认覆盖', (tester) async {
    final engine = BookEngineService(
      dio: fakeLlmDio({'title': '新标题', 'story': '新正文。'}, []),
    );
    await pumpCreate(
      tester,
      engine: engine,
      settings: AppSettings(
        llmType: 'openai',
        llmBaseUrl: 'https://example.test',
        llmApiKey: 'k',
        llmModel: 'm',
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, '可直接粘贴故事全文；若留空仅填书名，AI 将自动构思并续写完整童话...'),
      '我自己写的正文',
    );
    await tester.pump();

    await tester.tap(find.text('让 AI 按角色写故事'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
        TextField,
        '你想讲一个什么样的故事？比如：豆豆和小满在雨天迷路了，最后学会互相帮助',
      ),
      '随便讲一个。',
    );
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('生成故事')),
      until: () => find.text('用这个故事').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('用这个故事'));
    await tester.pumpAndSettle();

    expect(find.text('用生成的故事替换当前正文？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.textContaining('我自己写的正文'), findsOneWidget);
    expect(find.textContaining('新正文'), findsNothing);
  });
}
