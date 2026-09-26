import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';

class TtsService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  /// 获取某绘本某一页的本地音频文件路径
  Future<String> getLocalAudioPath({
    required String bookId,
    required int pageIndex,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final bookAudioDir = Directory('${appDir.path}/bookbuddy_audio/$bookId');
    if (!await bookAudioDir.exists()) {
      await bookAudioDir.create(recursive: true);
    }
    return '${bookAudioDir.path}/audio_p$pageIndex.mp3';
  }

  /// 检查某绘本某一页是否已有本地音频缓存
  Future<bool> hasCachedAudio({
    required String bookId,
    required int pageIndex,
    String? knownPath,
  }) async {
    return await getCachedAudioPath(
          bookId: bookId,
          pageIndex: pageIndex,
          knownPath: knownPath,
        ) !=
        null;
  }

  /// Return the path that actually exists; a stored path may become stale.
  Future<String?> getCachedAudioPath({
    required String bookId,
    required int pageIndex,
    String? knownPath,
  }) async {
    if (knownPath != null && knownPath.isNotEmpty) {
      final f = File(knownPath);
      if (await f.exists() && await f.length() > 0) {
        return knownPath;
      }
    }
    final path = await getLocalAudioPath(bookId: bookId, pageIndex: pageIndex);
    final f = File(path);
    if (await f.exists() && await f.length() > 0) return path;
    final backup = File('$path.bak');
    return await backup.exists() && await backup.length() > 0
        ? backup.path
        : null;
  }

  /// 为某页故事文本合成语音，并保存到本地
  /// 如果已有缓存且不强制刷新，则直接返回本地文件路径
  Future<String> synthesizePageAudio({
    required String bookId,
    required int pageIndex,
    required String text,
    required AppSettings settings,
    bool forceRefresh = false,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw Exception('当前页故事文本为空，无法合成语音');
    }

    final localPath = await getLocalAudioPath(
      bookId: bookId,
      pageIndex: pageIndex,
    );
    final localFile = File(localPath);

    // 检查缓存
    if (!forceRefresh &&
        await localFile.exists() &&
        await localFile.length() > 0) {
      return localPath;
    }

    // 校验配置
    final apiKey = settings.minimaxApiKey.trim();
    final groupId = settings.minimaxGroupId.trim();
    if (apiKey.isEmpty) {
      throw Exception('未配置 MiniMax API Key，请在【设置 -> 语音朗读】中填写');
    }
    if (groupId.isEmpty) {
      throw Exception('未配置 MiniMax Group ID，请在【设置 -> 语音朗读】中填写');
    }

    // 构建 MiniMax T2A v2 请求
    final url = 'https://api.minimax.chat/v1/t2a_v2?GroupId=$groupId';

    final requestBody = {
      'model': settings.minimaxModel.isNotEmpty
          ? settings.minimaxModel
          : 'speech-01-turbo',
      'text': cleanText,
      'stream': false,
      'voice_setting': {
        'voice_id': settings.minimaxVoiceId.isNotEmpty
            ? settings.minimaxVoiceId
            : 'audiobook_female_1',
        'speed': settings.minimaxSpeed,
        'vol': 1.0,
        'pitch': 0,
      },
      'audio_setting': {
        'sample_rate': 32000,
        'bitrate': 128000,
        'format': 'mp3',
        'channel': 1,
      },
    };

    try {
      final response = await _dio.post(
        url,
        data: requestBody,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      final respData = response.data;
      if (respData is! Map<String, dynamic>) {
        throw Exception('MiniMax 服务返回了无效数据格式');
      }

      // 检查 base_resp
      final baseResp = respData['base_resp'];
      if (baseResp != null && baseResp is Map<String, dynamic>) {
        final statusCode = baseResp['status_code'];
        if (statusCode != 0 && statusCode != null) {
          final msg = baseResp['status_msg'] ?? '未知错误';
          throw Exception('MiniMax 语音合成失败 ($statusCode): $msg');
        }
      }

      final dataField = respData['data'];
      if (dataField == null || dataField is! Map<String, dynamic>) {
        throw Exception('MiniMax 响应未包含音频数据');
      }

      final audioRaw = dataField['audio'];
      if (audioRaw == null || audioRaw is! String || audioRaw.isEmpty) {
        throw Exception('MiniMax 音频数据为空');
      }

      // 将返回数据转为字节码并写入本地文件
      final audioBytes = _decodeAudioData(audioRaw);
      final temp = File('$localPath.tmp');
      final backup = File('$localPath.bak');
      await temp.writeAsBytes(audioBytes, flush: true);
      var movedOriginal = false;
      try {
        if (await localFile.exists()) {
          if (await backup.exists()) await backup.delete();
          await localFile.rename(backup.path);
          movedOriginal = true;
        }
        await temp.rename(localPath);
      } catch (_) {
        if (movedOriginal &&
            !await localFile.exists() &&
            await backup.exists()) {
          await backup.copy(localPath);
        }
        rethrow;
      } finally {
        if (await temp.exists()) await temp.delete();
      }

      return localPath;
    } on DioException catch (e) {
      if (e.response != null) {
        final errBody = e.response?.data;
        throw Exception('MiniMax 网络请求失败 [${e.response?.statusCode}]: $errBody');
      }
      throw Exception('连接 MiniMax 语音服务失败: ${e.message}');
    }
  }

  /// 解码 MiniMax 音频数据（支持 Hex 编码及 Base64 编码自动适配）
  Uint8List _decodeAudioData(String raw) {
    final trimmed = raw.trim();

    // 1. 判断是否是纯十六进制字符串 (Hex)
    final hexRegExp = RegExp(r'^[0-9a-fA-F]+$');
    if (trimmed.length % 2 == 0 && hexRegExp.hasMatch(trimmed)) {
      try {
        final len = trimmed.length;
        final result = Uint8List(len ~/ 2);
        for (var i = 0; i < len; i += 2) {
          result[i ~/ 2] = int.parse(trimmed.substring(i, i + 2), radix: 16);
        }
        return result;
      } catch (_) {
        // 解码异常则回退走 base64
      }
    }

    // 2. 尝试 Base64 解码
    try {
      return base64Decode(trimmed);
    } catch (e) {
      throw Exception('无法识别的 MiniMax 音频编码格式: $e');
    }
  }

  /// 清除某绘本的所有音频缓存
  Future<void> deleteBookAudios(String bookId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final bookAudioDir = Directory('${appDir.path}/bookbuddy_audio/$bookId');
      if (await bookAudioDir.exists()) {
        await bookAudioDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
