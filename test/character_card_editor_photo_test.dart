import 'dart:convert';
import 'dart:io';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/character_card.dart';
import 'package:bookbuddy/screens/character_card_editor_screen.dart';
import 'package:bookbuddy/services/book_engine_service.dart';
import 'package:bookbuddy/services/character_storage_service.dart';
import 'package:bookbuddy/services/photo_picker_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/run_io.dart';

class FakePhotoPicker extends PhotoPickerService {
  FakePhotoPicker({this.photo, this.camera = true, this.lost});

  final Uint8List? photo;
  final bool camera;
  final Uint8List? lost;
  final List<PhotoSource> requests = [];

  @override
  bool get supportsCamera => camera;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    requests.add(source);
    return photo;
  }

  @override
  Future<Uint8List?> retrieveLost() async => lost;
}

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

Uint8List toyPhoto() {
  final src = img.Image(width: 1600, height: 1200);
  img.fill(src, color: img.ColorRgb8(60, 170, 90));
  return Uint8List.fromList(img.encodePng(src));
}

final draftReply = {
  'choices': [
    {
      'message': {
        'content': jsonEncode({
          'name': '豆豆',
          'kind': 'object',
          'species': '毛绒恐龙',
          'appearance': '绿色毛绒恐龙，肚皮米白',
          'defaultOutfit': '',
          'personality': '胆子大',
          'catchphrase': '冲啊！',
        }),
      },
    },
  ],
};

AppSettings visionSettings() => AppSettings(
      llmType: 'openai',
      llmBaseUrl: 'https://example.test',
      llmApiKey: 'k',
      llmModel: 'gpt-4o',
      imageType: 'gemini',
      imageBaseUrl: 'https://example.test',
      imageApiKey: 'k',
      imageModel: 'gemini-2.5-flash-image',
    );

ButtonStyleButton buttonWithText(WidgetTester tester, String text) =>
    tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .first,
    );

List<Directory> cardDirs(Directory root) =>
    root.listSync().whereType<Directory>().toList();

void main() {
  late Directory dir;
  late CharacterStorageService storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bookbuddy-editor-photo-');
    storage = CharacterStorageService(directory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    CharacterCard? card,
    required PhotoPickerService picker,
    BookEngineService? engine,
    AppSettings? settings,
    bool Function()? until,
    int maxRounds = 60,
  }) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await runIo(tester, () async {
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
                        loadSettings: () async => settings ?? visionSettings(),
                        photoPicker: picker,
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
        until: until ??
            () => find.byType(CharacterCardEditorScreen).evaluate().isNotEmpty,
        maxRounds: maxRounds);
  }

  Future<void> pickFromGallery(WidgetTester tester) => runIo(
        tester,
        () => tester.tap(find.text('从相册选择')),
        until: () => find.text('移除照片').evaluate().isNotEmpty,
        maxRounds: 120,
      );

  /// 新建且没保存的角色带着照片离开时，编辑页 dispose 会异步清理照片目录。
  /// 必须在用例结束前让它跑完：CharacterStorageService 的写队列是全局静态的，
  /// 留下未完成的清理会卡住后面所有用例的保存。
  /// 分两步：先等返回动画结束（此时页面才 dispose、清理才开始），再交替推进清理里的文件 IO。
  Future<void> leaveEditor(WidgetTester tester) async {
    await runIo(tester, () => tester.pageBack(), maxRounds: 1);
    await runIo(tester, () async {}, until: () => cardDirs(dir).isEmpty);
    expect(cardDirs(dir), isEmpty);
  }

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextField, '角色名 *'), '豆豆');
    await tester.enterText(
      find.widgetWithText(TextField, '外貌锚定描述 *（颜色、材质、体型、标志性细节）'),
      '绿色毛绒恐龙',
    );
    await tester.pump();
  }

  testWidgets('选图后照片压缩为 JPEG 落盘，保存后卡片来源为照片', (tester) async {
    await pumpEditor(tester, picker: FakePhotoPicker(photo: toyPhoto()));
    await pickFromGallery(tester);

    final dirs = cardDirs(dir);
    expect(dirs, hasLength(1));
    final file = File('${dirs.single.path}/photo.jpg');
    final saved = file.readAsBytesSync();
    expect(saved[0], 0xFF);
    expect(saved[1], 0xD8);
    final decoded = img.decodeJpg(saved)!;
    expect(decoded.width, 1024);
    expect(decoded.height, 768);

    await fillRequired(tester);
    await runIo(
      tester,
      () => tester.tap(find.text('保存')),
      until: () => find.text('打开编辑页').evaluate().isNotEmpty,
    );
    final card = (jsonDecode(File('${dir.path}/cards.json').readAsStringSync()) as List)
        .single as Map<String, dynamic>;
    expect(card['source'], 'photo');
    expect(card['photoPath'], '${card['id']}/photo.jpg');
  });

  testWidgets('没有照片时识别按钮不可用；不支持拍照的平台不显示拍照', (tester) async {
    await pumpEditor(tester, picker: FakePhotoPicker(camera: false));
    expect(find.text('拍照'), findsNothing);
    expect(find.text('从相册选择'), findsOneWidget);
    expect(buttonWithText(tester, '让 AI 认识它').onPressed, isNull);
  });

  testWidgets('让 AI 认识它：空表单直接填入识别结果', (tester) async {
    final sent = <dynamic>[];
    await pumpEditor(
      tester,
      picker: FakePhotoPicker(photo: toyPhoto()),
      engine: BookEngineService(dio: recordingDio(sent, () => draftReply)),
    );
    await pickFromGallery(tester);
    await runIo(
      tester,
      () => tester.tap(find.text('让 AI 认识它')),
      until: () => find.text('已填入识别结果，请检查后保存').evaluate().isNotEmpty,
    );

    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, '角色名 *')).controller!.text,
      '豆豆',
    );
    expect(find.text('绿色毛绒恐龙，肚皮米白'), findsOneWidget);
    expect(find.text('冲啊！'), findsOneWidget);
    expect(
      tester.widget<SegmentedButton<CharacterKind>>(find.byType(SegmentedButton<CharacterKind>)).selected,
      {CharacterKind.object},
    );
    final content = (sent.single as Map)['messages'][1]['content'] as List;
    expect(content.first['image_url']['url'], startsWith('data:image/jpeg;base64,'));
    await leaveEditor(tester);
  });

  testWidgets('已填内容时可以选择只填空白项', (tester) async {
    await pumpEditor(
      tester,
      picker: FakePhotoPicker(photo: toyPhoto()),
      engine: BookEngineService(dio: recordingDio([], () => draftReply)),
    );
    await pickFromGallery(tester);
    await tester.enterText(find.widgetWithText(TextField, '角色名 *'), '小满');
    await tester.pump();

    await runIo(
      tester,
      () => tester.tap(find.text('让 AI 认识它')),
      until: () => find.text('用识别结果填写表单？').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('只填空白项'));
    await tester.pumpAndSettle();
    // 对话框关闭后的后续填表在真实 zone 的微任务里，需要交替推进。
    await runIo(
      tester,
      () async {},
      until: () => find.text('已填入识别结果，请检查后保存').evaluate().isNotEmpty,
    );

    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, '角色名 *')).controller!.text,
      '小满',
    );
    expect(find.text('绿色毛绒恐龙，肚皮米白'), findsOneWidget);
    expect(
      tester.widget<SegmentedButton<CharacterKind>>(find.byType(SegmentedButton<CharacterKind>)).selected,
      {CharacterKind.animal},
    );
    await leaveEditor(tester);
  });

  testWidgets('生成定妆图时把照片作为参考图发出', (tester) async {
    final sent = <dynamic>[];
    final png = base64Encode([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
    await pumpEditor(
      tester,
      picker: FakePhotoPicker(photo: toyPhoto()),
      engine: BookEngineService(
        dio: recordingDio(sent, () => {
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
            }),
      ),
    );
    await pickFromGallery(tester);
    await fillRequired(tester);
    await runIo(
      tester,
      () => tester.tap(find.text('生成水彩童话定妆图')),
      until: () => find.text('重新生成水彩童话定妆图').evaluate().isNotEmpty,
      maxRounds: 120,
    );

    final photoOnDisk = base64Encode(
      File('${cardDirs(dir).single.path}/photo.jpg').readAsBytesSync(),
    );
    final parts = (sent.single as Map)['contents'][0]['parts'] as List;
    expect(parts.first['inlineData']['data'], photoOnDisk);
    expect(parts[1]['text'], contains('真实玩具或物件照片'));
  });

  testWidgets('生图通道不支持参考图时，前置对话框说明照片不会被参考', (tester) async {
    await pumpEditor(
      tester,
      picker: FakePhotoPicker(photo: toyPhoto()),
      settings: AppSettings(imageApiKey: 'k'),
    );
    await pickFromGallery(tester);
    await fillRequired(tester);
    await runIo(
      tester,
      () => tester.tap(find.text('生成水彩童话定妆图')),
      until: () => find.text('当前生图通道不支持参考图').evaluate().isNotEmpty,
    );
    expect(find.textContaining('照片不会被参考'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('已保存卡片移除照片后删除文件并更新卡片', (tester) async {
    final photoBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
    late CharacterCard card;
    await tester.runAsync(() async {
      final path = await storage.writeImage('card_toy', 'photo.jpg', photoBytes);
      card = CharacterCard(
        id: 'card_toy',
        source: CharacterCardSource.photo,
        name: '豆豆',
        appearance: '绿色',
        photoPath: path,
      );
      await storage.saveCard(card);
    });
    await pumpEditor(tester, card: card, picker: FakePhotoPicker());
    await runIo(tester, () async {}, until: () => find.text('移除照片').evaluate().isNotEmpty);

    await runIo(
      tester,
      () => tester.tap(find.text('移除照片')),
      until: () => find.text('移除照片').evaluate().isEmpty,
    );
    expect(File('${dir.path}/card_toy/photo.jpg').existsSync(), isFalse);
    final saved = (jsonDecode(File('${dir.path}/cards.json').readAsStringSync()) as List)
        .single as Map<String, dynamic>;
    expect(saved['photoPath'], isNull);
    expect(saved['source'], 'manual');
  });

  testWidgets('保存校验失败后移除照片，不会把未通过校验的表单一并存盘', (tester) async {
    final photoBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
    late CharacterCard card;
    await tester.runAsync(() async {
      final path = await storage.writeImage('card_toy', 'photo.jpg', photoBytes);
      card = CharacterCard(
        id: 'card_toy',
        source: CharacterCardSource.photo,
        name: '豆豆',
        appearance: '绿色',
        photoPath: path,
      );
      await storage.saveCard(card);
    });
    await pumpEditor(tester, card: card, picker: FakePhotoPicker());
    await runIo(tester, () async {}, until: () => find.text('移除照片').evaluate().isNotEmpty);

    // 清空角色名后保存：校验失败，但工作副本已经被表单值改写。
    await tester.enterText(find.widgetWithText(TextField, '角色名 *'), '');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('请填写角色名和外貌'), findsOneWidget);

    await runIo(
      tester,
      () => tester.tap(find.text('移除照片')),
      until: () => find.text('移除照片').evaluate().isEmpty,
    );
    expect(File('${dir.path}/card_toy/photo.jpg').existsSync(), isFalse);
    final saved = (jsonDecode(File('${dir.path}/cards.json').readAsStringSync()) as List)
        .single as Map<String, dynamic>;
    expect(saved['name'], '豆豆');
    expect(saved['photoPath'], isNull);
    expect(saved['source'], 'manual');
  });

  testWidgets('新建角色选了照片却没保存就离开时清理照片目录', (tester) async {
    await pumpEditor(tester, picker: FakePhotoPicker(photo: toyPhoto()));
    await pickFromGallery(tester);
    expect(cardDirs(dir), hasLength(1));

    await leaveEditor(tester);
  });

  testWidgets('新建角色时自动使用找回的照片', (tester) async {
    // 找回的照片在页面打开时就开始处理（忙碌转圈），所以要等「移除照片」出现再让页面静止。
    await pumpEditor(
      tester,
      picker: FakePhotoPicker(lost: toyPhoto()),
      until: () => find.text('移除照片').evaluate().isNotEmpty,
      maxRounds: 120,
    );
    expect(find.text('移除照片'), findsOneWidget);

    final dirs = cardDirs(dir);
    expect(dirs, hasLength(1));
    expect(File('${dirs.single.path}/photo.jpg').existsSync(), isTrue);

    await leaveEditor(tester);
  });

  testWidgets('已保存角色找回照片时先确认，取消后不覆盖', (tester) async {
    final photoBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
    late CharacterCard card;
    await tester.runAsync(() async {
      final path = await storage.writeImage('card_toy', 'photo.jpg', photoBytes);
      card = CharacterCard(
        id: 'card_toy',
        source: CharacterCardSource.photo,
        name: '豆豆',
        appearance: '绿色',
        photoPath: path,
      );
      await storage.saveCard(card);
    });
    final cardsJsonBefore = File('${dir.path}/cards.json').readAsStringSync();

    await pumpEditor(tester, card: card, picker: FakePhotoPicker(lost: toyPhoto()));
    await runIo(
      tester,
      () async {},
      until: () => find.text('找回了上次拍的照片').evaluate().isNotEmpty,
    );
    expect(find.text('要把它用在「豆豆」上吗？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await runIo(tester, () async {}, maxRounds: 5);

    expect(find.text('找回了上次拍的照片'), findsNothing);
    expect(File('${dir.path}/card_toy/photo.jpg').readAsBytesSync(), photoBytes);
    expect(File('${dir.path}/cards.json').readAsStringSync(), cardsJsonBefore);
    final saved = (jsonDecode(File('${dir.path}/cards.json').readAsStringSync()) as List)
        .single as Map<String, dynamic>;
    expect(saved['photoPath'], 'card_toy/photo.jpg');
  });

  test('真实取图服务只在手机上提供拍照', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(PhotoPickerService().supportsCamera, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(PhotoPickerService().supportsCamera, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(PhotoPickerService().supportsCamera, isTrue);
  });
}
