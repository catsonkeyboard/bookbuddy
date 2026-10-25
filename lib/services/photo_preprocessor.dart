import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 角色照片的长边上限（像素）。
const int kPhotoMaxEdge = 1024;

/// 角色照片的输入像素上限（宽 × 高）。桌面端可能直接选到 20MP+ 的原图，
/// 在 isolate 里全量解码再缩放 / 铺底会产生上百 MB 的峰值内存，直接拒绝。
const int kPhotoMaxInputPixels = 50000000;

/// 解码 → 按 EXIF 方向摆正 → 长边缩到 [kPhotoMaxEdge] → 清空 EXIF → 质量 85 的 JPEG。
/// 顶层函数，可以直接交给 `compute` 在后台 isolate 里跑。
Uint8List preprocessPhoto(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    // 过短或损坏的数据会让个别解码器的探测读越界（RangeError 等），统一当作无法解码。
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException('无法读取这张图片');
  }
  // 输入尺寸上限在解码后立即检查：再往后缩放、铺白底都会按全尺寸复制，
  // 峰值内存翻倍，超限的图直接拒绝并给出可操作的提示。
  if (decoded.width * decoded.height > kPhotoMaxInputPixels) {
    throw const FormatException('图片过大，请选择更小的图片');
  }
  // 手机照片常把方向写在 EXIF 里：先摆正再丢掉 EXIF，否则图会歪。
  var image = img.bakeOrientation(decoded);
  final longEdge = image.width > image.height ? image.width : image.height;
  if (longEdge > kPhotoMaxEdge) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: kPhotoMaxEdge,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: kPhotoMaxEdge,
            interpolation: img.Interpolation.average,
          );
  }
  // 位置、机型等元数据一律不带出本机。
  image.exif = img.ExifData();
  // 带 alpha 通道的图（如透明 PNG）直接转 JPEG，透明区域会变成黑色破坏识别，先铺纯白底再压。
  if (image.hasAlpha) {
    final flattened = img.Image(width: image.width, height: image.height);
    flattened.clear(img.ColorRgb8(255, 255, 255));
    img.compositeImage(flattened, image);
    image = flattened;
  }
  // encodeJpg 已返回 Uint8List，无需 Uint8List.fromList 再拷贝一次。
  return img.encodeJpg(image, quality: 85);
}
