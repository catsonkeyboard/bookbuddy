import 'dart:convert';
import 'dart:io';
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

List<int> _be32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

/// PNG 规范的标准 CRC-32。
int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc >> 1) ^ (0xEDB88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// 手工构造一张 1bpp 灰度 PNG（所有像素为白色）。
/// 用 1bpp 是为了让输入只有几 MB，而解码后仍是 width × height 的全尺寸图像。
Uint8List _hugeWhitePng(int width, int height) {
  final rowBytes = (width + 7) ~/ 8;
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter type: none
    for (var x = 0; x < rowBytes; x++) {
      raw.addByte(0xFF);
    }
  }
  final idat = zlib.encode(raw.toBytes());

  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = <int>[...ascii.encode(type), ...data];
    out.add(_be32(data.length));
    out.add(body);
    out.add(_be32(_crc32(body)));
  }

  chunk('IHDR', <int>[
    ..._be32(width),
    ..._be32(height),
    1, // bit depth: 1
    0, // color type: grayscale
    0, // compression: deflate
    0, // filter method
    0, // interlace: none
  ]);
  chunk('IDAT', idat);
  chunk('IEND', const <int>[]);
  return out.toBytes();
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

  test('超过输入像素上限的图片抛出「图片过大」FormatException', () {
    // 7072 × 7072 ≈ 50.01M 像素，刚刚越过 kPhotoMaxInputPixels(50M)。
    // 解码本身就要吃掉约 200MB，测试需要较长时间，放宽超时。
    final huge = _hugeWhitePng(7072, 7072);
    expect(
      () => preprocessPhoto(huge),
      throwsA(
        isA<FormatException>().having((e) => e.message, 'message', '图片过大，请选择更小的图片'),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('透明 PNG 转 JPEG 前铺白底，原透明像素变为白色', () {
    final src = img.Image(width: 240, height: 160, numChannels: 4);
    img.fill(src, color: img.ColorRgb8(30, 90, 200));
    for (var y = 40; y < 120; y++) {
      for (var x = 60; x < 180; x++) {
        src.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0)); // 全透明
      }
    }
    final input = Uint8List.fromList(img.encodePng(src));
    // 测试输入应当带 alpha 通道，确保走的是铺底分支。
    expect(img.decodePng(input)!.hasAlpha, isTrue);

    final output = preprocessPhoto(input);

    final decoded = img.decodeJpg(output)!;
    expect(decoded.width, 240);
    expect(decoded.height, 160);
    final transparent = decoded.getPixel(100, 80);
    expect(transparent.r, 255);
    expect(transparent.g, 255);
    expect(transparent.b, 255);
    // 不透明区域保留原色（JPEG 有损，允许小幅误差）。
    final opaque = decoded.getPixel(10, 10);
    expect(opaque.r, closeTo(30, 12));
    expect(opaque.g, closeTo(90, 12));
    expect(opaque.b, closeTo(200, 12));
  });
}
