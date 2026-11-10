import 'dart:io';

import 'package:bookbuddy/services/image_export_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var granted = true;
  String? errorCode;
  final png = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    granted = true;
    errorCode = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('gal'),
      (call) async {
        calls.add(call);
        if (call.method == 'requestAccess') return granted;
        if (call.method == 'putImageBytes' && errorCode != null) {
          throw PlatformException(code: errorCode!);
        }
        return null;
      },
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('gal'),
      null,
    );
  });

  test('保存原图字节到相册，清理文件名中的路径字符', () async {
    final result = await ImageExportService().save(png, name: '豆豆/第1页');
    expect(result, ImageExportResult.gallery);
    final args =
        calls.singleWhere((c) => c.method == 'putImageBytes').arguments as Map;
    expect(args['bytes'], png);
    expect(args['name'], '豆豆_第1页');
    expect(args['album'], isNull);
  });

  test('权限拒绝时不写入相册并返回可操作的提示', () async {
    granted = false;
    await expectLater(
      ImageExportService().save(png, name: '豆豆'),
      throwsA(
        isA<ImageExportException>().having(
          (e) => e.message,
          'message',
          contains('系统设置'),
        ),
      ),
    );
    expect(calls.where((c) => c.method == 'putImageBytes'), isEmpty);
  });

  test('损坏图片在申请权限之前被拒绝', () async {
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList([1, 2, 3]),
    ]) {
      await expectLater(
        ImageExportService().save(bytes, name: '豆豆'),
        throwsA(isA<ImageExportException>()),
      );
    }
    expect(calls, isEmpty);
  });

  test('相册存储空间不足时返回中文提示', () async {
    errorCode = 'NOT_ENOUGH_SPACE';
    await expectLater(
      ImageExportService().save(png, name: '豆豆'),
      throwsA(
        isA<ImageExportException>().having(
          (e) => e.message,
          'message',
          contains('空间不足'),
        ),
      ),
    );
  });

  test('iOS 同样把原图写入相册', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      await ImageExportService().save(png, name: '豆豆'),
      ImageExportResult.gallery,
    );
    expect(
      calls.singleWhere((c) => c.method == 'putImageBytes').arguments['bytes'],
      png,
    );
  });

  group('桌面保存窗口', () {
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    late Directory dir;
    String? outputPath;
    MethodCall? dialogCall;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      dir = Directory.systemTemp.createTempSync('bookbuddy-image-export-');
      dialogCall = null;
      outputPath = null;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        dialogCall = call;
        return outputPath;
      });
    });
    tearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      dir.deleteSync(recursive: true);
    });

    test('根据实际 JPEG 格式命名，补齐扩展名并保留原始字节', () async {
      final jpg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 2, height: 2)),
      );
      outputPath = '${dir.path}/saved';
      expect(
        await ImageExportService().save(jpg, name: '绘本_第1页'),
        ImageExportResult.file,
      );
      expect(dialogCall!.arguments['suggestedName'], '绘本_第1页.jpg');
      expect(await File('${dir.path}/saved.jpg').readAsBytes(), jpg);
      expect(calls, isEmpty);
    });

    test('取消保存窗口不写文件', () async {
      expect(
        await ImageExportService().save(png, name: '绘本'),
        ImageExportResult.cancelled,
      );
      expect(dir.listSync(), isEmpty);
      expect(calls, isEmpty);
    });
  });
}
