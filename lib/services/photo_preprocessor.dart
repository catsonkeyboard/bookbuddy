import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 角色照片的长边上限（像素）。
const int kPhotoMaxEdge = 1024;

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
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}
