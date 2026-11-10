import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;

enum ImageExportResult { gallery, file, cancelled }

class ImageExportException implements Exception {
  const ImageExportException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ImageExportService {
  Future<ImageExportResult> save(
    Uint8List bytes, {
    required String name,
  }) async {
    // 校验和格式识别在后台完成，导出时始终保留原始字节和分辨率。
    final extension = await compute(_imageExtension, bytes);
    final safeName = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
    final fileName = safeName.isEmpty ? 'BookBuddy' : safeName;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        if (!await Gal.requestAccess()) {
          throw const ImageExportException('无法保存：请在系统设置中允许 BookBuddy 添加照片到相册');
        }
        await Gal.putImageBytes(bytes, name: fileName);
        return ImageExportResult.gallery;
      } on GalException catch (e) {
        throw ImageExportException(switch (e.type) {
          GalExceptionType.accessDenied => '无法保存：请在系统设置中允许 BookBuddy 添加照片到相册',
          GalExceptionType.notEnoughSpace => '保存失败：设备存储空间不足，请清理后重试',
          GalExceptionType.notSupportedFormat => '保存失败：系统相册不支持这张图片的格式',
          GalExceptionType.unexpected => '图片保存失败，请稍后重试',
        });
      }
    }

    final location = await getSaveLocation(
      suggestedName: '$fileName.$extension',
      acceptedTypeGroups: [
        XTypeGroup(label: '图片', extensions: [extension]),
      ],
    );
    if (location == null) return ImageExportResult.cancelled;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.$extension')) path = '$path.$extension';
    await XFile.fromData(bytes).saveTo(path);
    return ImageExportResult.file;
  }
}

String _imageExtension(Uint8List bytes) {
  try {
    final decoder = img.findDecoderForData(bytes);
    if (decoder != null &&
        const {
          img.ImageFormat.png,
          img.ImageFormat.jpg,
          img.ImageFormat.webp,
          img.ImageFormat.gif,
          img.ImageFormat.bmp,
          img.ImageFormat.tiff,
        }.contains(decoder.format) &&
        decoder.decode(bytes, frame: 0) != null) {
      return decoder.format.name;
    }
  } catch (_) {
    // 缺失、截断或损坏的图像统一转成可展示的错误。
  }
  throw const ImageExportException('图片不存在、已损坏或格式不支持，无法保存');
}
