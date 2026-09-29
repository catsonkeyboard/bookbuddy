import 'dart:convert';
import 'dart:io';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/create_book_screen.dart';
import 'package:bookbuddy/screens/storyboard_review_screen.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(find.text('进入审核后会先为 小满、阿福 绘制该画风的定妆照'), findsOneWidget);

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
    expect(find.textContaining('进入审核后会先为'), findsNothing);
  });

  testWidgets('生成时把已选卡片的定妆图与 id 传给引擎和审核页', (tester) async {
    final png = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
    await tester.runAsync(() async {
      await storage.saveCard(card('card_a', '豆豆'));
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
  });
}
