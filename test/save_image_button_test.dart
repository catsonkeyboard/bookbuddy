import 'dart:async';

import 'package:bookbuddy/widgets/save_image_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/run_io.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  var writes = 0;
  final png = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

  setUp(() {
    writes = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('gal'),
      (call) async {
        if (call.method == 'requestAccess') return true;
        if (call.method == 'putImageBytes') writes++;
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

  testWidgets('连续点击只保存一次，完成后显示相册成功提示', (tester) async {
    final pending = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SaveImageButton(
            name: '豆豆',
            label: '保存定妆图',
            loadBytes: () => pending.future,
          ),
        ),
      ),
    );
    await tester.tap(find.text('保存定妆图'));
    await tester.tap(find.text('保存定妆图'));
    await tester.pump();
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    await runIo(
      tester,
      () async => pending.complete(png),
      until: () => find.text('图片已保存到相册').evaluate().isNotEmpty,
    );
    expect(writes, 1);
    expect(find.text('图片已保存到相册'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('本地图片丢失时显示失败提示并恢复按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SaveImageButton(
            name: '豆豆',
            label: '保存定妆图',
            loadBytes: () async => throw StateError('missing'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('保存定妆图'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    expect(writes, 0);
    debugDefaultTargetPlatformOverride = null;
  });
}
