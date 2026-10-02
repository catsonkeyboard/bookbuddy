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

/// 定妆照成功的 SnackBar 已出现，且转圈动画已停（`finally` 里 `_isGenerating` 已复位）。
/// 只等文案会在转圈仍在时提前退出，随后 `pumpAndSettle` 会被无限动画卡住。
bool portraitSavedAndIdle() =>
    find
        .text('定妆照已保存。请检查角色外貌和服装，确认后再开始绘制故事页。')
        .evaluate()
        .isNotEmpty &&
    find.byType(CircularProgressIndicator).evaluate().isEmpty;

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

Dio fakeGeminiImageDio(String base64Png, [List<dynamic>? sent]) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        sent?.add(options.data);
        handler.resolve(
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
        );
      },
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
    List<BookCharacter>? initialCharacters,
    List<PinnedCharacter> pinnedCharacters = const [],
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
          initialCharacters: initialCharacters ?? [dino().toBookCharacter()],
          settings: settings,
          pinnedCharacters: pinnedCharacters,
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
      until: portraitSavedAndIdle,
      maxRounds: 120,
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

    // 卡片现在有这个画风的定妆图了：再次重绘要先确认，取消则什么都不做。
    await tester.tap(find.byTooltip('重新生成定妆照'));
    await tester.pumpAndSettle();
    expect(find.text('只用于本书'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('只用于本书'), findsNothing);
  });

  group('卡片已有本画风定妆图', () {
    final oldAnchorBytes = [0x89, 0x50, 0x4e, 0x47, 1, 1, 1, 1];
    final oldAnchor = base64Encode(oldAnchorBytes);
    final imageSettings = AppSettings(
      imageType: 'gemini',
      imageApiKey: 'test-key',
      imageModel: 'gemini-2.5-flash-image',
    );
    File anchorFile() => File('${charDir.path}/card_dino1/anchor_watercolor.png');

    Future<List<dynamic>> pumpWithCardAnchor(WidgetTester tester) async {
      await tester.runAsync(() async {
        await charStorage.saveCard(dino());
        await charStorage.saveAnchor('card_dino1', 'watercolor', oldAnchor);
      });
      final card = dino()
        ..anchorImagePaths['watercolor'] = 'card_dino1/anchor_watercolor.png';
      final sent = <dynamic>[];
      await pumpReview(
        tester,
        settings: imageSettings,
        engine: BookEngineService(dio: fakeGeminiImageDio(pngBase64, sent)),
        initialCharacters: [card.toBookCharacter()..referenceImageBase64 = oldAnchor],
        pinnedCharacters: [PinnedCharacter(card: card, anchorBase64: oldAnchor)],
      );
      return sent;
    }

    /// 在真实事件循环里点「重新生成定妆照」打开确认框：确认后的生图请求沿用这次点击的
    /// zone，若在 FakeAsync 里点击，请求里的计时器要等测试时钟推进，runIo 永远等不到结果。
    Future<void> openRegenerateDialog(WidgetTester tester) async {
      await tester.runAsync(() => tester.tap(find.byTooltip('重新生成定妆照')));
      await tester.pumpAndSettle();
      expect(find.textContaining('角色卡里已经有水彩童话画风的定妆图'), findsOneWidget);
    }

    String bookReference() {
      final bookFile = bookDir
          .listSync()
          .whereType<File>()
          .singleWhere((f) => f.path.endsWith('.json'));
      final book = jsonDecode(bookFile.readAsStringSync()) as Map<String, dynamic>;
      return (book['characters'] as List).single['referenceImageBase64'] as String;
    }

    testWidgets('重绘先确认；取消不请求，「只用于本书」不覆盖卡片定妆图', (tester) async {
      final sent = await pumpWithCardAnchor(tester);

      await openRegenerateDialog(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await openRegenerateDialog(tester);
      await runIo(
        tester,
        () => tester.tap(find.text('只用于本书')),
        until: portraitSavedAndIdle,
        maxRounds: 120,
      );

      expect(sent, hasLength(1));
      expect(anchorFile().readAsBytesSync(), oldAnchorBytes);
      expect(bookReference(), pngBase64);
    });

    testWidgets('选「同时更新角色卡」时覆盖卡片定妆图', (tester) async {
      final sent = await pumpWithCardAnchor(tester);

      await openRegenerateDialog(tester);
      await runIo(
        tester,
        () => tester.tap(find.text('同时更新角色卡')),
        until: portraitSavedAndIdle,
        maxRounds: 120,
      );

      expect(sent, hasLength(1));
      expect(anchorFile().readAsBytesSync(), base64Decode(pngBase64));
      final card =
          (jsonDecode(File('${charDir.path}/cards.json').readAsStringSync()) as List)
              .single as Map<String, dynamic>;
      expect(card['anchorImagePaths'], {'watercolor': 'card_dino1/anchor_watercolor.png'});
      expect(bookReference(), pngBase64);
    });
  });

  testWidgets('书内改过外貌的卡片角色重绘定妆照时不写回卡片', (tester) async {
    await tester.runAsync(() => charStorage.saveCard(dino()));
    final edited = dino().toBookCharacter()..appearance = '紫色毛绒恐龙';
    final settings = AppSettings(
      imageType: 'gemini',
      imageApiKey: 'test-key',
      imageModel: 'gemini-2.5-flash-image',
    );
    await pumpReview(
      tester,
      settings: settings,
      engine: BookEngineService(dio: fakeGeminiImageDio(pngBase64)),
      initialCharacters: [edited],
      pinnedCharacters: [PinnedCharacter(card: dino())],
    );

    await runIo(
      tester,
      () => tester.tap(find.byTooltip('重新生成定妆照')),
      until: portraitSavedAndIdle,
      maxRounds: 120,
    );

    expect(
      File('${charDir.path}/card_dino1/anchor_watercolor.png').existsSync(),
      isFalse,
    );
    final card =
        (jsonDecode(File('${charDir.path}/cards.json').readAsStringSync()) as List)
            .single as Map<String, dynamic>;
    expect(card['anchorImagePaths'], isEmpty);
    expect(card['lastUsedAt'], isNotNull);

    final bookFile = bookDir
        .listSync()
        .whereType<File>()
        .singleWhere((f) => f.path.endsWith('.json'));
    final book = jsonDecode(bookFile.readAsStringSync()) as Map<String, dynamic>;
    expect((book['characters'] as List).single['referenceImageBase64'], pngBase64);
    expect((book['characters'] as List).single['appearance'], '紫色毛绒恐龙');
  });

  testWidgets('书内角色已有定妆照时重绘先确认，取消则不调用生图模型', (tester) async {
    final oldReference = base64Encode([0x89, 0x50, 0x4e, 0x47, 1, 1, 1, 1]);
    await tester.runAsync(() => charStorage.saveCard(dino()));
    final sent = <dynamic>[];
    // 书内改过外貌：定妆照只属于本书，走普通确认而不是「是否更新角色卡」。
    final edited = dino().toBookCharacter()
      ..appearance = '紫色毛绒恐龙'
      ..referenceImageBase64 = oldReference;
    await pumpReview(
      tester,
      settings: AppSettings(
        imageType: 'gemini',
        imageApiKey: 'test-key',
        imageModel: 'gemini-2.5-flash-image',
      ),
      engine: BookEngineService(dio: fakeGeminiImageDio(pngBase64, sent)),
      initialCharacters: [edited],
      pinnedCharacters: [PinnedCharacter(card: dino())],
    );

    Future<void> openConfirm() async {
      await tester.runAsync(() => tester.tap(find.byTooltip('重新生成定妆照')));
      await tester.pumpAndSettle();
      expect(find.text('重新生成定妆照？'), findsOneWidget);
      expect(find.text('只用于本书'), findsNothing);
    }

    await openConfirm();
    expect(find.textContaining('「豆豆」已经有定妆照了'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await openConfirm();
    await runIo(
      tester,
      () => tester.tap(find.text('重新生成')),
      until: portraitSavedAndIdle,
      maxRounds: 120,
    );
    expect(sent, hasLength(1));
    final bookFile = bookDir
        .listSync()
        .whereType<File>()
        .singleWhere((f) => f.path.endsWith('.json'));
    final book = jsonDecode(bookFile.readAsStringSync()) as Map<String, dynamic>;
    expect((book['characters'] as List).single['referenceImageBase64'], pngBase64);
  });

  testWidgets('卡片角色补画定妆照时附带卡片照片', (tester) async {
    const photo = 'UEhPVE9fTUFSS0VS';
    final settings = AppSettings(
      imageType: 'gemini',
      imageApiKey: 'test-key',
      imageModel: 'gemini-2.5-flash-image',
    );

    final sent = <dynamic>[];
    await tester.runAsync(() => charStorage.saveCard(dino()));
    await pumpReview(
      tester,
      settings: settings,
      engine: BookEngineService(dio: fakeGeminiImageDio(pngBase64, sent)),
      pinnedCharacters: [PinnedCharacter(card: dino(), photoBase64: photo)],
    );
    await runIo(
      tester,
      () => tester.tap(find.byTooltip('重新生成定妆照')),
      until: portraitSavedAndIdle,
      maxRounds: 120,
    );
    final withPhoto = jsonEncode(sent.single);
    expect(withPhoto, contains(photo));
    expect(withPhoto, contains('真实玩具或物件照片'));
  });

  // 与上一条分开：同一用例里第二次 pumpReview 会复用第一次的审核页 State（旧引擎、
  // 旧角色，请求落进第一个记录器）；卸载整棵树则会触发 dispose 里未捕获的
  // WakelockPlus.disable()（测试环境无平台通道）。各用各的树最稳。
  testWidgets('书内改过外貌的卡片角色补画定妆照时不带卡片照片', (tester) async {
    const photo = 'UEhPVE9fTUFSS0VS';
    final settings = AppSettings(
      imageType: 'gemini',
      imageApiKey: 'test-key',
      imageModel: 'gemini-2.5-flash-image',
    );

    await tester.runAsync(() => charStorage.saveCard(dino()));
    final editedSent = <dynamic>[];
    await pumpReview(
      tester,
      settings: settings,
      engine: BookEngineService(dio: fakeGeminiImageDio(pngBase64, editedSent)),
      initialCharacters: [dino().toBookCharacter()..appearance = '紫色毛绒恐龙'],
      pinnedCharacters: [PinnedCharacter(card: dino(), photoBase64: photo)],
    );
    await runIo(
      tester,
      () => tester.tap(find.byTooltip('重新生成定妆照')),
      until: portraitSavedAndIdle,
      maxRounds: 120,
    );
    expect(jsonEncode(editedSent.single), isNot(contains(photo)));
  });
}
