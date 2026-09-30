import 'dart:convert';
import 'dart:typed_data';

import 'package:bookbuddy/services/photo_preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

bool containsAscii(Uint8List bytes, String marker) {
  final pattern = ascii.encode(marker);
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    var hit = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return true;
  }
  return false;
}

void main() {
  test('大图按 EXIF 方向摆正、长边缩到 1024，输出不含 EXIF 的 JPEG', () {
    final src = img.Image(width: 2000, height: 1500);
    img.fill(src, color: img.ColorRgb8(40, 160, 90));
    src.exif.imageIfd.orientation = 6; // 需要顺时针转 90° 才是正的
    src.exif.imageIfd['Make'] = img.IfdValueAscii('TestCam');
    final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));
    expect(containsAscii(input, 'Exif'), isTrue, reason: '测试输入应当带 EXIF');

    final output = preprocessPhoto(input);

    expect(output[0], 0xFF);
    expect(output[1], 0xD8); // JPEG 文件头
    expect(containsAscii(output, 'Exif'), isFalse);
    expect(containsAscii(output, 'TestCam'), isFalse);
    final decoded = img.decodeJpg(output)!;
    expect(decoded.width, 768);
    expect(decoded.height, 1024);
  });

  test('小图不放大，只重编码为 JPEG', () {
    final src = img.Image(width: 300, height: 200);
    img.fill(src, color: img.ColorRgb8(200, 100, 50));
    final output = preprocessPhoto(Uint8List.fromList(img.encodePng(src)));
    final decoded = img.decodeJpg(output)!;
    expect(decoded.width, 300);
    expect(decoded.height, 200);
  });

  test('无法解码的字节抛出约定的 FormatException', () {
    expect(
      () => preprocessPhoto(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(
        isA<FormatException>().having((e) => e.message, 'message', '无法读取这张图片'),
      ),
    );
  });
}
