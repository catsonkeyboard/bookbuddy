import 'dart:convert';
import 'dart:io';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/services/tts_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// 伪造 MiniMax T2A v2 的成功响应（hex 音频）。
Map<String, dynamic> _hexAudioReply(String hex) => {
  'base_resp': {'status_code': 0, 'status_msg': 'success'},
  'data': {'audio': hex},
};

String _hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory appDir;
  final requests = <RequestOptions>[];

  setUp(() {
    appDir = Directory.systemTemp.createTempSync('bookbuddy-tts-test-');
    requests.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return appDir.path;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (appDir.existsSync()) appDir.deleteSync(recursive: true);
  });

  Dio mockDio(
    Map<String, dynamic> Function() responder, {
    Duration delay = Duration.zero,
  }) {
    return Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(options);
            if (delay > Duration.zero) await Future.delayed(delay);
            handler.resolve(
              Response(requestOptions: options, data: responder()),
            );
          },
        ),
      );
  }

  group('TTS Model & Serialization Tests', () {
    test('BookPageItem audioPath toJson and fromJson', () {
      final page = BookPageItem(
        pageIndex: 0,
        text: '很久很久以前，森林里住着一只小鹿。',
        audioPath: '/data/user/0/com.example.bookbuddy/app_flutter/audio_p0.mp3',
      );

      final jsonMap = page.toJson();
      expect(jsonMap['audioPath'], '/data/user/0/com.example.bookbuddy/app_flutter/audio_p0.mp3');

      final restored = BookPageItem.fromJson(jsonMap);
      expect(restored.audioPath, page.audioPath);
      expect(restored.text, page.text);
    });

    test('AppSettings TTS fields default and serialization', () {
      final settings = AppSettings();
      expect(settings.ttsEnabled, isTrue);
      expect(settings.minimaxSpeed, 0.85);
      expect(settings.minimaxModel, 'speech-01-turbo');
      expect(settings.minimaxVoiceId, 'audiobook_female_1');

      settings.minimaxApiKey = 'test_key';
      settings.minimaxGroupId = 'test_group_id';
      settings.minimaxSpeed = 0.80;

      final jsonMap = settings.toJson();
      expect(jsonMap['minimaxApiKey'], 'test_key');
      expect(jsonMap['minimaxGroupId'], 'test_group_id');
      expect(jsonMap['minimaxSpeed'], 0.80);

      final restored = AppSettings.fromJson(jsonMap);
      expect(restored.minimaxApiKey, 'test_key');
      expect(restored.minimaxGroupId, 'test_group_id');
      expect(restored.minimaxSpeed, 0.80);
    });
  });

  group('decodeAudioData 顶层函数', () {
    test('纯 hex 串按 hex 解码', () {
      final bytes = <int>[0x00, 0x01, 0x0F, 0x10, 0xFE, 0xFF];
      expect(decodeAudioData(_hexOf(bytes)), equals(bytes));
    });

    test('纯 base64 串按 base64 解码', () {
      final bytes = <int>[0x00, 0x01, 0xFE, 0xFF];
      final encoded = base64Encode(bytes); // 含 + / = 等非 hex 字符
      expect(_hexOf(bytes), isNot(equals(encoded)));
      expect(decodeAudioData(encoded), equals(bytes));
    });

    test('前 64 字符是 hex 但后段混入非 hex 字符时安全回退 base64', () {
      // 64 个 hex 字符（采样段全绿）+ 4 个非 hex 字符；整串仍是合法 base64。
      final mixed = '${'0123456789ABCDEF' * 4}zzzz';
      expect(mixed.length, 68);
      expect(decodeAudioData(mixed), equals(base64Decode(mixed)));
    });

    test('全 hex 但长度为奇数的串不会截断解码，抛异常', () {
      // 'abcde' 长度为奇数：hex 路径直接跳过；而 Dart 的 base64 要求长度是 4 的
      // 倍数，奇数长度也不可能走通 base64，最终统一抛异常——绝不静默截断成 2 字节。
      expect(() => decodeAudioData('abcde'), throwsA(isA<Exception>()));
      expect(() => decodeAudioData('ABCDE'), throwsA(isA<Exception>()));
    });

    test('既非 hex 也非 base64 时抛异常', () {
      expect(() => decodeAudioData('!!!not-base64!!!'), throwsA(isA<Exception>()));
    });
  });

  group('synthesizePageAudio', () {
    final settings = AppSettings(minimaxApiKey: 'key', minimaxGroupId: 'group');
    final audioBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];

    test('缓存命中时不发请求，直接返回本地路径', () async {
      final service = TtsService(dio: mockDio(() => _hexAudioReply(_hexOf(audioBytes))));
      final path = await service.getLocalAudioPath(bookId: 'b_cache', pageIndex: 0);
      await File(path).writeAsBytes([1, 2, 3], flush: true);

      final result = await service.synthesizePageAudio(
        bookId: 'b_cache',
        pageIndex: 0,
        text: '小鹿过生日',
        // 缓存命中先于配置校验，空配置也应直接返回。
        settings: AppSettings(),
      );
      expect(result, path);
      expect(requests, isEmpty);
    });

    test('缺 API Key 时报错且不发请求', () async {
      final service = TtsService(dio: mockDio(() => _hexAudioReply('')));
      await expectLater(
        service.synthesizePageAudio(
          bookId: 'b_nokey',
          pageIndex: 0,
          text: '你好',
          settings: AppSettings(minimaxGroupId: 'group'),
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('API Key'))),
      );
      expect(requests, isEmpty);
    });

    test('缺 Group ID 时报错且不发请求', () async {
      final service = TtsService(dio: mockDio(() => _hexAudioReply('')));
      await expectLater(
        service.synthesizePageAudio(
          bookId: 'b_nogroup',
          pageIndex: 0,
          text: '你好',
          settings: AppSettings(minimaxApiKey: 'key'),
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Group ID'))),
      );
      expect(requests, isEmpty);
    });

    test('base_resp.status_code 非零时报错', () async {
      final service = TtsService(
        dio: mockDio(() => {
          'base_resp': {'status_code': 1004, 'status_msg': 'invalid api key'},
          'data': {'audio': ''},
        }),
      );
      await expectLater(
        service.synthesizePageAudio(
          bookId: 'b_err',
          pageIndex: 0,
          text: '你好',
          settings: settings,
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('1004'))),
      );
    });

    test('status_code 是字符串 "0" 时按成功处理', () async {
      final service = TtsService(
        dio: mockDio(() => {
          'base_resp': {'status_code': '0', 'status_msg': 'success'},
          'data': {'audio': _hexOf(audioBytes)},
        }),
      );
      final path = await service.synthesizePageAudio(
        bookId: 'b_str0',
        pageIndex: 0,
        text: '你好',
        settings: settings,
      );
      expect(await File(path).readAsBytes(), audioBytes);
    });

    test('成功合成后写入 hex 解码出的音频字节', () async {
      final service = TtsService(dio: mockDio(() => _hexAudioReply(_hexOf(audioBytes))));
      final path = await service.synthesizePageAudio(
        bookId: 'b_ok',
        pageIndex: 1,
        text: '小鹿过生日',
        settings: settings,
      );
      expect(await File(path).readAsBytes(), audioBytes);
      expect(requests.single.uri.toString(),
          'https://api.minimax.chat/v1/t2a_v2?GroupId=group');
    });

    test('GroupId 经 queryParameters 编码进 URL', () async {
      final service = TtsService(dio: mockDio(() => _hexAudioReply(_hexOf(audioBytes))));
      await service.synthesizePageAudio(
        bookId: 'b_url',
        pageIndex: 0,
        text: '你好',
        settings: AppSettings(minimaxApiKey: 'key', minimaxGroupId: 'group a&b'),
      );
      expect(requests.single.uri.queryParameters['GroupId'], 'group a&b');
    });

    test('并发合成同一页只发一次 HTTP，两次拿到同一结果', () async {
      final service = TtsService(
        dio: mockDio(() => _hexAudioReply(_hexOf(audioBytes)), delay: const Duration(milliseconds: 60)),
      );
      final f1 = service.synthesizePageAudio(
        bookId: 'b_race',
        pageIndex: 0,
        text: '小鹿过生日',
        settings: settings,
      );
      final f2 = service.synthesizePageAudio(
        bookId: 'b_race',
        pageIndex: 0,
        text: '小鹿过生日',
        settings: settings,
      );
      final results = await Future.wait([f1, f2]);
      expect(results[0], results[1]);
      expect(requests, hasLength(1));
      expect(await File(results[0]).readAsBytes(), audioBytes);
    });

    test('并发请求失败后不会在去重表里留下 stale Future', () async {
      var failNext = true;
      final service = TtsService(
        dio: mockDio(() {
          if (failNext) {
            return {
              'base_resp': {'status_code': 1004, 'status_msg': 'boom'},
            };
          }
          return _hexAudioReply(_hexOf(audioBytes));
        }),
      );
      await expectLater(
        service.synthesizePageAudio(
          bookId: 'b_stale',
          pageIndex: 0,
          text: '你好',
          settings: settings,
        ),
        throwsA(isA<Exception>()),
      );
      // 同一个 service 再合成同一页：若失败的 Future 残留在去重表里，
      // 这次会直接拿到旧的失败结果而不是重新请求。
      failNext = false;
      final path = await service.synthesizePageAudio(
        bookId: 'b_stale',
        pageIndex: 0,
        text: '你好',
        settings: settings,
      );
      expect(await File(path).readAsBytes(), audioBytes);
    });
  });
}
