import 'dart:convert';
import 'dart:io';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/character_card_editor_screen.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 在真实事件循环里执行会产生文件 IO / 网络的操作，随后交替「让出真实时间片」与
/// 「冲刷一次 FakeAsync 微任务队列」，直到 [until] 成立或达到 [maxRounds]。
///
/// 为什么必须交替而不能把两步嵌套在同一个 `runAsync` 里：`CharacterStorageService`
/// 的读改写链路有好几跳真实文件 IO（读 cards.json → 改 → 写临时文件 → 改名备份 →
/// 改名正式文件 → 通知监听者重新加载）。`pumpAndSettle()` 只按 UI 帧是否稳定来判断
/// "是否结束"，并不知道背后还有未完成的磁盘 IO；每一跳完成后的延续都是在 widget 树
/// 所在的 FakeAsync 测试时钟上排队的微任务，必须靠测试驱动在"让出真实时间片"
/// （`runAsync` 里的 `Future.delayed`）与"冲刷一次 FakeAsync 微任务队列"
/// （`pump()`）之间来回切换才能被逐跳取出执行；嵌套在同一个 `runAsync` 里时，这次
/// 冲刷根本不会发生，链路会卡在第一跳。[until] 用于在调用方关心的状态已经出现时
/// 提前退出，避免每次调用都不加区分地付出最坏情况下的完整轮数开销。
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

List<Map<String, dynamic>> readCards(Directory dir) =>
    (jsonDecode(File('${dir.path}/cards.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

/// 伪造 Gemini 多模态生图响应，并记录请求体。
Dio fakeGeminiImageDio(String base64Png, List<dynamic> sentBodies) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        sentBodies.add(options.data);
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
  late Directory dir;
  late CharacterStorageService storage;
  final pngBase64 = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bookbuddy-editor-test-');
    storage = CharacterStorageService(directory: dir);
  });

  tearDown(() {
    if (!dir.existsSync()) return;
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows 上引擎解码过的图片文件句柄在进程内无法可靠释放
      //（evict/clear/unmount 均无效），残留的临时目录交给系统清理。
    }
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    CharacterCard? card,
    BookEngineService? engine,
    AppSettings? settings,
  }) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 从一个占位页 push 进入编辑页，保证「保存后返回」有可返回的路由。
    await runIo(
      tester,
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => CharacterCardEditorScreen(
                          card: card,
                          storage: storage,
                          engine: engine,
                          loadSettings: () async => settings ?? AppSettings(),
                        ),
                      ),
                    ),
                    child: const Text('打开编辑页'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开编辑页'));
      },
      until: () =>
          find.byType(CharacterCardEditorScreen).evaluate().isNotEmpty,
    );
  }

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextField, '角色名 *'), '豆豆');
    await tester.enterText(
      find.widgetWithText(TextField, '外貌锚定描述 *（颜色、材质、体型、标志性细节）'),
      '绿色毛绒恐龙，肚皮米白',
    );
    await tester.pump();
  }

  testWidgets('角色名或外貌为空时不能保存', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请填写角色名和外貌'), findsOneWidget);
    expect(File('${dir.path}/cards.json').existsSync(), isFalse);
  });

  testWidgets('切换画风后保存对应定妆图原图', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final saved = <Map>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('gal'), (call) async {
      if (call.method == 'requestAccess') return true;
      if (call.method == 'putImageBytes') saved.add(call.arguments as Map);
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('gal'), null);
    });
    final watercolor = img.encodePng(img.Image(width: 2, height: 2));
    final anime = img.encodePng(img.Image(width: 3, height: 3));
    final card = CharacterCard(id: 'card_a', name: '豆豆', appearance: '绿色');
    await tester.runAsync(() async {
      await storage.saveCard(card);
      await storage.saveAnchor(card.id, 'watercolor', base64Encode(watercolor));
      await storage.saveAnchor(card.id, 'anime', base64Encode(anime));
    });
    await pumpEditor(tester, card: CharacterCard.fromJson(readCards(dir).single));
    await tester.ensureVisible(find.text('日系动漫'));
    await tester.tap(find.text('日系动漫'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存定妆图'));
    await runIo(tester, () => tester.tap(find.text('保存定妆图')),
      until: () => saved.isNotEmpty);
    expect(saved.single['bytes'], anime);
    expect(saved.single['name'], '豆豆_日系动漫');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('填写必填项后保存落盘并返回', (tester) async {
    await pumpEditor(tester);
    await fillRequired(tester);
    await tester.enterText(find.widgetWithText(TextField, '口头禅'), '冲啊！');
    await tester.tap(find.text('物件'));
    await tester.pump();

    await runIo(
      tester,
      () => tester.tap(find.text('保存')),
      until: () => find.text('打开编辑页').evaluate().isNotEmpty,
    );

    final saved = readCards(dir).single;
    expect(saved['name'], '豆豆');
    expect(saved['appearance'], '绿色毛绒恐龙，肚皮米白');
    expect(saved['catchphrase'], '冲啊！');
    expect(saved['kind'], 'object');
    expect(saved['source'], 'manual');
    expect((saved['id'] as String).startsWith('card_'), isTrue);
    expect(find.byType(CharacterCardEditorScreen), findsNothing);
    expect(find.text('打开编辑页'), findsOneWidget);
  });

  testWidgets('编辑已有卡片时表单预填且保存为更新', (tester) async {
    final card = CharacterCard(
      id: 'card_a',
      name: '豆豆',
      species: '毛绒恐龙',
      appearance: '绿色',
      personality: '勇敢',
    );
    await tester.runAsync(() => storage.saveCard(card));
    await pumpEditor(tester, card: card);
    expect(find.text('编辑角色：豆豆'), findsOneWidget);
    expect(find.text('毛绒恐龙'), findsOneWidget);
    expect(find.text('勇敢'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '性格'), '勇敢又贪吃');
    await runIo(
      tester,
      () => tester.tap(find.text('保存')),
      until: () => find.text('打开编辑页').evaluate().isNotEmpty,
    );
    final cards = readCards(dir);
    expect(cards, hasLength(1));
    expect(cards.single['personality'], '勇敢又贪吃');
  });

  testWidgets('修改外貌后保存需确认，确认后清空定妆图', (tester) async {
    final card = CharacterCard(id: 'card_a', name: '豆豆', appearance: '绿色');
    await tester.runAsync(() async {
      await storage.saveCard(card);
      await storage.saveAnchor('card_a', 'watercolor', pngBase64);
    });
    final reloaded = CharacterCard.fromJson(readCards(dir).single);
    await pumpEditor(tester, card: reloaded);

    await tester.enterText(
      find.widgetWithText(TextField, '外貌锚定描述 *（颜色、材质、体型、标志性细节）'),
      '蓝色',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('外貌设定已修改'), findsOneWidget);
    expect(find.text('已有 1 张定妆图将被清空，下次使用时重新生成。'), findsOneWidget);

    await runIo(
      tester,
      () => tester.tap(find.text('清空并保存')),
      until: () => find.text('打开编辑页').evaluate().isNotEmpty,
    );
    final saved = readCards(dir).single;
    expect(saved['appearance'], '蓝色');
    expect(saved['anchorImagePaths'], isEmpty);
    expect(File('${dir.path}/card_a/anchor_watercolor.png').existsSync(), isFalse);
  });

  testWidgets('只改性格不触发定妆图失效确认', (tester) async {
    // 实验：合法 PNG
    final validPng = base64Encode([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
      0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    ]);
    final card = CharacterCard(id: 'card_a', name: '豆豆', appearance: '绿色');
    await tester.runAsync(() async {
      await storage.saveCard(card);
      await storage.saveAnchor('card_a', 'watercolor', validPng);
    });
    await pumpEditor(tester, card: CharacterCard.fromJson(readCards(dir).single));
    await tester.enterText(find.widgetWithText(TextField, '性格'), '温柔');
    await runIo(
      tester,
      () => tester.tap(find.text('保存')),
      until: () => find.text('打开编辑页').evaluate().isNotEmpty,
    );
    expect(find.text('外貌设定已修改'), findsNothing);
    final saved = readCards(dir).single;
    expect(saved['personality'], '温柔');
    expect(saved['anchorImagePaths'], {'watercolor': 'card_a/anchor_watercolor.png'});
  });

  // ---- 以下两条属于 Task 6，本任务结束时它们会失败 ----

  testWidgets('Imagen 默认通道点击生成定妆图弹出不支持参考图对话框', (tester) async {
    final settings = AppSettings(imageApiKey: 'test-key');
    await pumpEditor(tester, settings: settings);
    await fillRequired(tester);

    await runIo(
      tester,
      () => tester.tap(find.text('生成水彩童话定妆图')),
      until: () => find.text('当前生图通道不支持参考图').evaluate().isNotEmpty,
    );
    expect(find.text('当前生图通道不支持参考图'), findsOneWidget);
    expect(find.text('仍然生成'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final saved = readCards(dir).single;
    expect(saved['name'], '豆豆');
    expect(saved['anchorImagePaths'], isEmpty);
  });

  testWidgets('支持参考图的通道生成定妆图并写回卡片', (tester) async {
    final sent = <dynamic>[];
    final engine = BookEngineService(dio: fakeGeminiImageDio(pngBase64, sent));
    final settings = AppSettings(
      imageType: 'gemini',
      imageApiKey: 'test-key',
      imageModel: 'gemini-2.5-flash-image',
    );
    await pumpEditor(tester, engine: engine, settings: settings);
    await fillRequired(tester);

    await runIo(
      tester,
      () => tester.tap(find.text('生成水彩童话定妆图')),
      until: () => find.text('重新生成水彩童话定妆图').evaluate().isNotEmpty,
    );

    expect(find.text('定妆图已保存，请检查外貌是否符合预期'), findsOneWidget);
    final saved = readCards(dir).single;
    final id = saved['id'] as String;
    expect(saved['anchorImagePaths'], {'watercolor': '$id/anchor_watercolor.png'});
    expect(File('${dir.path}/$id/anchor_watercolor.png').existsSync(), isTrue);
    expect(sent, hasLength(1));
    final promptText = jsonEncode(sent.single);
    expect(promptText, contains('豆豆'));
    expect(promptText, contains('绿色毛绒恐龙'));
    expect(find.text('重新生成水彩童话定妆图'), findsOneWidget);
  });
}
