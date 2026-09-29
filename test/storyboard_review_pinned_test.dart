import 'dart:convert';
import 'dart:io';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/storyboard_review_screen.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:bookbuddy/services/book_storage_service.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在真实事件循环里执行会产生文件 IO / 网络的操作，然后交替「让出真实时间片」与
/// 「冲刷一次 FakeAsync 微任务队列」，直到 [until] 成立或达到 [maxRounds]。
/// 必须交替两个独立调用而不能嵌套在同一个 runAsync 里：每一跳 IO 完成后的延续
/// 都排在测试时钟的微任务队列上，只有 pump 一次才会被取出执行。
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

const watercolor = BookStyle(
  id: 'watercolor',
  name: '水彩童话',
  desc: '',
  prefix: '水彩',
  negative: '',
);

CharacterCard dino() => CharacterCard(
      id: 'card_dino1',
      name: '豆豆',
      kind: CharacterKind.animal,
      species: '毛绒恐龙',
      appearance: '绿色毛绒恐龙',
      defaultOutfit: '红色小围巾',
    );

Dio fakeGeminiImageDio(String base64Png) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response(
          requestOptions: options,
          data: {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'inlineData': {'mimeType': 'image/png', 'data': base64Png},
                    },
                  ],
                },
              },
            ],
          },
        ),
      ),
    ),
  );

void main() {
  late Directory charDir;
  late Directory bookDir;
  late CharacterStorageService charStorage;
  late BookStorageService bookStorage;
  final pngBase64 = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'bookbuddy_books_migrated_to_files': true,
    });
    charDir = Directory.systemTemp.createTempSync('bookbuddy-review-chars-');
    bookDir = Directory.systemTemp.createTempSync('bookbuddy-review-books-');
    charStorage = CharacterStorageService(directory: charDir);
    bookStorage = BookStorageService(booksDirectory: bookDir);
  });

  tearDown(() {
    for (final dir in [charDir, bookDir]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  Future<void> pumpReview(
    WidgetTester tester, {
    required AppSettings settings,
    BookEngineService? engine,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: StoryboardReviewScreen(
          title: '豆豆的雨天',
          style: watercolor,
          initialPages: [
            BookPageItem(pageIndex: 0, text: '豆豆出发了。', characterIds: ['card_dino1']),
          ],
          initialCharacters: [dino().toBookCharacter()],
          settings: settings,
          characterCardIds: const ['card_dino1'],
          characterStorage: charStorage,
          bookStorage: bookStorage,
          engine: engine,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('卡片来源角色显示「角色卡」标签，编辑对话框提示只影响本书', (tester) async {
    await pumpReview(tester, settings: AppSettings());
    expect(find.text('角色卡'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑角色设定'));
    await tester.pumpAndSettle();
    expect(find.text('编辑角色：豆豆（来自角色卡）'), findsOneWidget);
    expect(find.text('此处修改仅影响本书，不会改动角色卡。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('重新生成定妆照后写回角色卡并更新使用时间', (tester) async {
    await tester.runAsync(() => charStorage.saveCard(dino()));
    final settings = AppSettings(
      imageType: 'gemini',
      imageApiKey: 'test-key',
      imageModel: 'gemini-2.5-flash-image',
    );
    await pumpReview(
      tester,
      settings: settings,
      engine: BookEngineService(dio: fakeGeminiImageDio(pngBase64)),
    );

    await runIo(
      tester,
      () => tester.tap(find.byTooltip('重新生成定妆照')),
      until: () => find
          .text('定妆照已保存。请检查角色外貌和服装，确认后再开始绘制故事页。')
          .evaluate()
          .isNotEmpty,
    );

    expect(
      File('${charDir.path}/card_dino1/anchor_watercolor.png').existsSync(),
      isTrue,
    );
    final cards =
        jsonDecode(File('${charDir.path}/cards.json').readAsStringSync()) as List;
    final card = cards.single as Map<String, dynamic>;
    expect(card['anchorImagePaths'], {'watercolor': 'card_dino1/anchor_watercolor.png'});
    expect(card['lastUsedAt'], isNotNull);

    final bookFiles = bookDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(bookFiles, hasLength(1));
    final book = jsonDecode(bookFiles.single.readAsStringSync()) as Map<String, dynamic>;
    expect(book['characterCardIds'], ['card_dino1']);
    expect((book['characters'] as List).single['referenceImageBase64'], pngBase64);
  });
}
