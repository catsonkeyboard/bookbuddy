import 'dart:convert';
import 'dart:io';

import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/screens/book_reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/run_io.dart';

String pagePng(int r, int g, int b) {
  final src = img.Image(width: 8, height: 8);
  img.fill(src, color: img.ColorRgb8(r, g, b));
  return base64Encode(img.encodePng(src));
}

PictureBook threePageBook({List<BookCharacter> characters = const []}) => PictureBook(
      id: 'book-reader-test',
      title: '豆豆的雨天',
      styleId: 'watercolor',
      styleName: '水彩童话',
      createdAt: DateTime.utc(2026, 10, 2),
      characters: characters,
      pages: [
        BookPageItem(pageIndex: 0, text: '第一页', imageBase64: pagePng(200, 60, 60)),
        BookPageItem(pageIndex: 1, text: '第二页', imageBase64: pagePng(60, 200, 60)),
        BookPageItem(pageIndex: 2, text: '第三页', imageBase64: pagePng(60, 60, 200)),
      ],
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 阅读器内部直接创建 AudioPlayer；测试环境没有平台实现，对它的通道统一应答空结果。
    binding.defaultBinaryMessenger.allMessagesHandler = (channel, handler, message) async {
      if (channel.startsWith('xyz.luan/audioplayers')) {
        return const StandardMethodCodec().encodeSuccessEnvelope(null);
      }
      return handler?.call(message);
    };
  });

  tearDown(() => binding.defaultBinaryMessenger.allMessagesHandler = null);

  Future<void> pumpReader(WidgetTester tester, PictureBook book) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: BookReaderScreen(book: book)));
    await tester.pump();
  }

  /// 卸载阅读器并走完播放器释放、SnackBar 等遗留的计时器。
  Future<void> closeReader(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 40));
  }

  /// 某一页插画组件当前使用的字节对象；Image.memory 靠它的同一性判断是不是同一张图。
  /// 提前构建的相邻页在视口外，finder 默认会跳过，所以都带 skipOffstage: false。
  Uint8List bytesOfPage(WidgetTester tester, String pageText) {
    final card = find.ancestor(
      of: find.text(pageText, skipOffstage: false),
      matching: find.byType(Card, skipOffstage: false),
    );
    final image = tester.widget<Image>(
      find.descendant(
        of: card,
        matching: find.byType(Image, skipOffstage: false),
        skipOffstage: false,
      ),
    );
    return (image.image as MemoryImage).bytes;
  }

  testWidgets('界面刷新时当前页插画沿用同一份解码结果，不会重新加载而闪烁', (tester) async {
    final book = threePageBook();
    await pumpReader(tester, book);
    final before = bytesOfPage(tester, '第一页');

    // 切换连读只是一次普通的界面刷新，朗读状态变化、翻页时也是同样的刷新。
    await tester.tap(find.text('连读关'));
    await tester.pump();
    expect(find.text('连读开'), findsOneWidget);

    expect(identical(bytesOfPage(tester, '第一页'), before), isTrue);
    await closeReader(tester);
  });

  testWidgets('页面插画被重绘替换后显示新图', (tester) async {
    final book = threePageBook();
    await pumpReader(tester, book);
    final before = bytesOfPage(tester, '第一页');

    final redrawn = pagePng(240, 240, 20);
    book.pages[0].imageBase64 = redrawn;
    await tester.tap(find.text('连读关'));
    await tester.pump();

    final after = bytesOfPage(tester, '第一页');
    expect(identical(after, before), isFalse);
    expect(after, base64Decode(redrawn));
    await closeReader(tester);
  });

  testWidgets('角色已有定妆照时点「重绘定妆照」先确认，取消则不开始生成', (tester) async {
    final book = threePageBook(
      characters: [
        BookCharacter(
          id: 'c1',
          name: '豆豆',
          appearance: '绿色毛绒恐龙',
          defaultOutfit: '红色小围巾',
          referenceImageBase64: pagePng(20, 160, 80),
        ),
      ],
    );
    await pumpReader(tester, book);

    await tester.tap(find.byTooltip('查看角色定妆照与固定设定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重绘定妆照'));
    await tester.pumpAndSettle();

    expect(find.text('重新生成定妆照？'), findsOneWidget);
    expect(find.textContaining('「豆豆」已经有定妆照了'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 没有进入生成状态：角色卡片上没有转圈，按钮仍可点。
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('重绘定妆照'), findsOneWidget);
    await closeReader(tester);
  });

  group('本页已有朗读语音', () {
    const regenTooltip = '重新使用 MiniMax 合成本页语音并覆盖';
    // 确认后会继续走到「检查语音配置」这一步；测试里没配密钥，所以出现这条提示就说明继续了。
    const missingKeyHint = '⚠️ 请先前往【设置 -> 绘本语音朗读】配置 MiniMax API Key 与 Group ID';
    final audioBytes = [1, 2, 3, 4];
    late Directory audioDir;
    late File audio;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      audioDir = Directory.systemTemp.createTempSync('bookbuddy-reader-audio-');
      audio = File('${audioDir.path}/audio_p0.mp3')..writeAsBytesSync(audioBytes);
    });

    tearDown(() {
      if (audioDir.existsSync()) audioDir.deleteSync(recursive: true);
    });

    Future<void> pumpWithAudio(WidgetTester tester) async {
      final book = threePageBook();
      book.pages[0].audioPath = audio.path;
      await pumpReader(tester, book);
    }

    /// 是否已有语音要查磁盘，所以点击和后续都在真实事件循环里推进。
    Future<void> tapRegenAndWaitForConfirm(WidgetTester tester) => runIo(
          tester,
          () => tester.tap(find.byTooltip(regenTooltip)),
          until: () => find.text('重新合成本页语音？').evaluate().isNotEmpty,
        );

    testWidgets('点重新合成先确认，取消则不继续', (tester) async {
      await pumpWithAudio(tester);

      await tapRegenAndWaitForConfirm(tester);
      expect(find.textContaining('第 1 页已经有朗读语音了'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await runIo(tester, () async {}, maxRounds: 5);

      expect(find.text(missingKeyHint), findsNothing);
      expect(find.textContaining('正在使用 MiniMax'), findsNothing);
      expect(audio.readAsBytesSync(), audioBytes);
      await closeReader(tester);
    });

    testWidgets('确认后才继续重新合成', (tester) async {
      await pumpWithAudio(tester);

      await tapRegenAndWaitForConfirm(tester);
      expect(find.text(missingKeyHint), findsNothing);
      await runIo(
        tester,
        () => tester.tap(find.text('重新合成')),
        until: () => find.text(missingKeyHint).evaluate().isNotEmpty,
      );

      expect(find.text(missingKeyHint), findsOneWidget);
      await closeReader(tester);
    });
  });

  testWidgets('翻页及全屏后保存的是当前页原图', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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
    final book = threePageBook();
    await pumpReader(tester, book);
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    await runIo(tester, () => tester.tap(find.text('保存当前页图片')),
      until: () => saved.isNotEmpty);
    expect(saved.single['bytes'], base64Decode(book.pages[1].imageBase64!));
    expect(saved.single['name'], '豆豆的雨天_第2页');

    await tester.tap(find.byTooltip('全屏预览绘本'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PageView));
    await tester.pumpAndSettle();
    await runIo(tester, () => tester.tap(find.byTooltip('保存当前页图片')),
      until: () => saved.length == 2);
    expect(saved.last['bytes'], base64Decode(book.pages[1].imageBase64!));
    await closeReader(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('手机窄屏下保存入口保持在屏幕内', (tester) async {
    await pumpReader(tester, threePageBook());
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      home: const Scaffold(body: Text('书架')),
      initialRoute: '/reader',
      routes: {'/reader': (_) => BookReaderScreen(book: threePageBook())},
    ));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    final rect = tester.getRect(find.text('保存当前页图片'));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(390));
    expect(rect.overlaps(tester.getRect(find.byType(BackButton))), isFalse);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开启自动翻页连读'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('关闭自动翻页连读'), findsOneWidget);
    expect(find.text('重绘当前页插画'), findsOneWidget);
    expect(find.text('重新合成本页语音'), findsOneWidget);
    await closeReader(tester);
  });

  testWidgets('没有插画的页面禁用保存', (tester) async {
    final book = threePageBook();
    book.pages[0].imageBase64 = null;
    await pumpReader(tester, book);
    final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '保存当前页图片'));
    expect(button.onPressed, isNull);
    await closeReader(tester);
  });

  testWidgets('下一页的插画在翻页前就已经准备好', (tester) async {
    await pumpReader(tester, threePageBook());

    // 第二页还没翻到，但已经在树里并开始加载；第三页不提前加载。
    expect(find.text('第二页', skipOffstage: false), findsOneWidget);
    expect(bytesOfPage(tester, '第二页'), isNotEmpty);
    expect(find.text('第三页', skipOffstage: false), findsNothing);
    await closeReader(tester);
  });

  testWidgets('空 pages 绘本渲染「绘本数据损坏」占位而不是崩溃', (tester) async {
    final book = PictureBook(
      id: 'book-empty-pages',
      title: '空绘本',
      styleId: 'watercolor',
      styleName: '水彩童话',
      createdAt: DateTime.utc(2026, 10, 2),
      pages: const [],
    );
    await pumpReader(tester, book);

    expect(find.text('绘本数据损坏'), findsOneWidget);
    expect(find.textContaining('《空绘本》没有任何页面内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeReader(tester);
  });

  group('全屏预览', () {
    Future<void> enterFullscreen(WidgetTester tester) async {
      await tester.tap(find.byTooltip('全屏预览绘本'));
      await tester.pumpAndSettle();
    }

    testWidgets('进入后隐藏顶栏与正文，插画铺满屏幕，控制条默认隐藏', (tester) async {
      await pumpReader(tester, threePageBook());

      expect(find.byTooltip('全屏预览绘本'), findsOneWidget);
      await enterFullscreen(tester);

      // 顶栏（连读开关等功能按钮）与正文区全部隐藏，界面被全屏插画取代。
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('连读关'), findsNothing);
      expect(find.text('第一页'), findsNothing);
      // 全屏插画以 contain 布局铺满屏幕。
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images.any((i) => i.fit == BoxFit.contain), isTrue);
      // 控制条默认隐藏，避免干扰看图。
      expect(find.byTooltip('退出全屏预览'), findsNothing);
      await closeReader(tester);
    });

    testWidgets('点按画面切换控制条显隐，控制条带页码', (tester) async {
      await pumpReader(tester, threePageBook());
      await enterFullscreen(tester);

      await tester.tap(find.byType(PageView));
      await tester.pumpAndSettle();
      expect(find.byTooltip('退出全屏预览'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.tap(find.byType(PageView));
      await tester.pumpAndSettle();
      expect(find.byTooltip('退出全屏预览'), findsNothing);
      await closeReader(tester);
    });

    testWidgets('全屏中翻页后退出，阅读器停在同一页并恢复顶栏与正文', (tester) async {
      await pumpReader(tester, threePageBook());
      await enterFullscreen(tester);

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PageView));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.tap(find.byTooltip('退出全屏预览'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('连读关'), findsOneWidget);
      expect(find.text('第二页'), findsOneWidget);
      expect(find.text('第一页'), findsNothing);
      await closeReader(tester);
    });

    testWidgets('全屏预览时系统返回键先退出预览而不是离开阅读器', (tester) async {
      await pumpReader(tester, threePageBook());
      await enterFullscreen(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // 第一次返回只退出全屏，阅读器本体还在当前页。
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('第一页'), findsOneWidget);
      expect(find.byTooltip('全屏预览绘本'), findsOneWidget);
      await closeReader(tester);
    });
  });
}
