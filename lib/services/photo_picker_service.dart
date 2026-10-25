import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

/// image_picker 各平台在权限被拒绝（或没有可用相机）时抛出的 PlatformException code。
/// 参见 image_picker_ios 的 FLTImagePickerPlugin.m 与 image_picker_android 的
/// ImagePickerDelegate.java（iOS 为 photo_access_denied / camera_access_denied，
/// Android 为 camera_access_denied / no_available_camera）。
const _kPermissionDeniedCodes = <String>{
  'photo_access_denied',
  'camera_access_denied',
  'access_denied',
  'no_available_camera',
};

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
    try {
      final file = await _picker.pickImage(
        source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (file == null) return null;
      return await file.readAsBytes();
    } on PlatformException catch (e) {
      debugPrint('PhotoPickerService.pick PlatformException: ${e.code} ${e.message}');
      // 权限被拒绝不能静默按「用户取消」处理（用户看不到任何反馈，会以为按钮坏了）。
      // 抛出具可操作文案的异常，由界面 toast 提示去系统设置里开启。
      if (_kPermissionDeniedCodes.contains(e.code)) {
        final target = source == PhotoSource.camera ? '相机' : '相册';
        throw Exception('$target权限被拒绝，请在系统设置中开启');
      }
      return null;
    } catch (e) {
      debugPrint('PhotoPickerService.pick 未预期异常: $e');
      return null;
    }
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
    } catch (e) {
      // 找回失败与「没有丢失数据」返回值相同（null）；至少留下日志，
      // 否则用户拍照后进程被回收且找回失败时照片无声丢失、无从排查。
      debugPrint('PhotoPickerService.retrieveLost 找回失败: $e');
      return null;
    }
  }
}
