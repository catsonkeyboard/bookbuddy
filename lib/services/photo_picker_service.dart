import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

/// 取图的薄封装：页面只依赖这个类，测试里可以换成假实现。
class PhotoPickerService {
  PhotoPickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// 只有手机能直接拍照；桌面与 Web 只提供从相册 / 文件选图。
  bool get supportsCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 返回原始图片字节；用户取消时返回 null。先让系统把超大图缩一轮，后续还会统一预处理。
  Future<Uint8List?> pick(PhotoSource source) async {
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  /// Android 上拍照时进程可能被系统回收；重新进入编辑页时找回那张照片。其他平台返回 null。
  Future<Uint8List?> retrieveLost() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty) return null;
      final files = response.files;
      final file = response.file ??
          (files != null && files.isNotEmpty ? files.first : null);
      return await file?.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
