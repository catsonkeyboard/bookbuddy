import 'dart:convert';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/story_composer_screen.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在真实事件循环里执行会产生网络 / 文件 Future 的操作，然后交替「让出真实时间片」与
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

/// 每次请求按顺序返回 [contents] 里的下一个字符串（超出则重复最后一个），并记录请求体。
Dio sequencedOpenAiDio(List<String> contents, List<dynamic> sent) {
  var calls = 0;
  return Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          sent.add(options.data);
          final content = contents[calls < contents.length ? calls : contents.length - 1];
          calls++;
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
}

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
      appearance: '绿色毛绒恐龙',
      catchphrase: '冲啊！',
    );

String storyJson(String title, String story) =>
    jsonEncode({'title': title, 'story': story});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 从占位页 push 进入助手页，并把返回值记录到 [popped]。
  Future<void> pumpComposer(
    WidgetTester tester, {
    List<CharacterCard> cards = const [],
    BookEngineService? engine,
    required List<StoryDraftResult?> popped,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () async {
                  final result = await Navigator.push<StoryDraftResult>(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => StoryComposerScreen(
                        cards: cards,
                        engine: engine,
                        loadSettings: () async => openAiSettings(),
                      ),
                    ),
                  );
                  popped.add(result);
                },
                child: const Text('打开助手'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开助手'));
    await tester.pumpAndSettle();
  }

  Finder briefField() => find.widgetWithText(
        TextField,
        '你想讲一个什么样的故事？比如：豆豆和小满在雨天迷路了，最后学会互相帮助',
      );

  testWidgets('没有角色卡时提示 AI 会自行设计角色', (tester) async {
    await pumpComposer(tester, popped: []);
    expect(find.text('未选择角色卡，AI 会自行设计角色'), findsOneWidget);
    expect(find.text('用这个故事'), findsNothing);
  });

  testWidgets('点击灵感芯片把带角色名的模板句填入描述框', (tester) async {
    await pumpComposer(tester, cards: [dino()], popped: []);
    expect(find.text('豆豆'), findsWidgets);
    await tester.tap(find.text('它从哪里来'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(briefField());
    expect(field.controller!.text, contains('豆豆'));
    expect(field.controller!.text, contains('从哪里来'));
  });

  testWidgets('生成故事后可编辑并用这个故事返回结果', (tester) async {
    final popped = <StoryDraftResult?>[];
    final engine = BookEngineService(
      dio: sequencedOpenAiDio([storyJson('豆豆的雨天', '豆豆出门了。\n\n它迷路了。')], []),
    );
    await pumpComposer(tester, cards: [dino()], engine: engine, popped: popped);

    await tester.enterText(briefField(), '豆豆在雨天迷路了。');
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('生成故事')),
      until: () => find.text('用这个故事').evaluate().isNotEmpty,
    );
    expect(find.text('豆豆的雨天'), findsOneWidget);
    expect(find.textContaining('豆豆出门了。'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '故事标题'),
      '豆豆的雨天（手改）',
    );
    await tester.pump();
    await tester.tap(find.text('用这个故事'));
    await tester.pumpAndSettle();

    expect(popped.single!.title, '豆豆的雨天（手改）');
    expect(popped.single!.story, '豆豆出门了。\n\n它迷路了。');
    expect(find.byType(StoryComposerScreen), findsNothing);
  });

  testWidgets('按建议重写以现文本为基础，回到上一版可恢复', (tester) async {
    final sent = <dynamic>[];
    final engine = BookEngineService(
      dio: sequencedOpenAiDio([
        storyJson('第一版', '第一版正文。'),
        storyJson('第二版', '第二版正文，结局更温暖。'),
      ], sent),
    );
    await pumpComposer(tester, cards: [dino()], engine: engine, popped: []);
    await tester.enterText(briefField(), '豆豆在雨天迷路了。');
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('生成故事')),
      until: () => find.text('用这个故事').evaluate().isNotEmpty,
    );
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '回到上一版')).onPressed, isNull);

    // 手改正文后再提反馈：重写请求必须带上手改后的文本。
    await tester.enterText(
      find.widgetWithText(TextField, '故事正文'),
      '第一版正文。（我手改了这里）',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '想改哪里？比如：结局再温暖一点 / 加一段他们吵架又和好'),
      '结局再温暖一点',
    );
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('按建议重写')),
      until: () => find.textContaining('第二版正文').evaluate().isNotEmpty,
    );
    final rewriteUser = (sent.last as Map)['messages'][1]['content'] as String;
    expect(rewriteUser, contains('（我手改了这里）'));
    expect(rewriteUser, contains('结局再温暖一点'));
    expect(find.text('第二版'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, '想改哪里？比如：结局再温暖一点 / 加一段他们吵架又和好')).controller!.text,
      isEmpty,
    );

    await tester.tap(find.text('回到上一版'));
    await tester.pumpAndSettle();
    expect(find.text('第一版'), findsOneWidget);
    expect(find.textContaining('（我手改了这里）'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '回到上一版')).onPressed, isNull);
  });

  testWidgets('生成失败时提示原因，描述保留，故事区不出现', (tester) async {
    final engine = BookEngineService(
      dio: sequencedOpenAiDio(['这不是 JSON'], []),
    );
    await pumpComposer(tester, cards: [dino()], engine: engine, popped: []);
    await tester.enterText(briefField(), '豆豆在雨天迷路了。');
    await tester.pump();
    await runIo(
      tester,
      () => tester.tap(find.text('生成故事')),
      until: () => find.text('故事生成结果格式不正确').evaluate().isNotEmpty,
    );
    expect(find.text('故事生成结果格式不正确'), findsOneWidget);
    expect(tester.widget<TextField>(briefField()).controller!.text, '豆豆在雨天迷路了。');
    expect(find.text('用这个故事'), findsNothing);
  });
}
