import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';

class TtsService {
  TtsService({Dio? dio})
      : _dio =
            dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 60),
              ),
            );

  final Dio _dio;

  /// 同一页音频的并发合成去重表，键为 '$bookId/$pageIndex'。
  /// 非 forceRefresh 的重复请求直接复用已在途的 Future：避免并发重复请求
  /// MiniMax 造成双倍计费，也避免两个请求写同一个固定名临时文件互相覆盖。
  /// 请求结束后只按 identity 移除自己这一条，防止误删后来者的在途记录。
  final _inFlight = <String, Future<String>>{};

  /// 获取某绘本某一页的本地音频文件路径
  ///
  /// 缓存键设计说明：路径只由 (bookId, pageIndex) 决定，不含文本指纹。
  /// 目前页面正文创建后不可编辑，因此不存在「同页文本变了但缓存不失效」的路径。
  /// 未来若支持编辑正文，必须在保存正文时同步失效该页音频缓存
  /// （删除本地文件并清空 BookPageItem.audioPath），否则会命中旧文本的音频。
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
  ///
  /// 同一页的并发调用会合并为一次真实请求（见 [_inFlight]）。
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

    final inFlightKey = '$bookId/$pageIndex';
    if (!forceRefresh) {
      final pending = _inFlight[inFlightKey];
      if (pending != null) return pending;
    }

    final future = _synthesizePageAudioInternal(
      bookId: bookId,
      pageIndex: pageIndex,
      cleanText: cleanText,
      settings: settings,
      forceRefresh: forceRefresh,
    );
    _inFlight[inFlightKey] = future;
    try {
      return await future;
    } finally {
      // 只移除自己这一次请求留下的记录，避免把后来者的在途 Future 误删。
      if (_inFlight[inFlightKey] == future) {
        _inFlight.remove(inFlightKey);
      }
    }
  }

  Future<String> _synthesizePageAudioInternal({
    required String bookId,
    required int pageIndex,
    required String cleanText,
    required AppSettings settings,
    required bool forceRefresh,
  }) async {
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

    // 构建 MiniMax T2A v2 请求。GroupId 走 queryParameters 由 Uri 统一编码，
    // 避免手工拼接时特殊字符（如空格、&）破坏 URL。
    final url = Uri.parse('https://api.minimax.chat/v1/t2a_v2')
        .replace(queryParameters: {'GroupId': groupId})
        .toString();

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

      // 检查 base_resp。status_code 可能是数字也可能是字符串（如 '0'）：
      // 非数字一律按「无状态码」处理，只有明确的非零数字才判失败，
      // 避免把成功的 '0' 误判成失败。
      final baseResp = respData['base_resp'];
      if (baseResp != null && baseResp is Map<String, dynamic>) {
        final rawCode = baseResp['status_code'];
        final code = rawCode is num ? rawCode.toInt() : null;
        if (code != null && code != 0) {
          final msg = baseResp['status_msg'] ?? '未知错误';
          throw Exception('MiniMax 语音合成失败 ($code): $msg');
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

      // 音频串可能长达数 MB，解码放后台 isolate，避免主线程卡顿。
      final audioBytes = await compute(decodeAudioData, audioRaw);
      // 临时文件名带唯一后缀：并发合成同一页时不会互相覆盖。
      final temp = File('$localPath.${const Uuid().v4()}.tmp');
      final backup = File('$localPath.bak');
      try {
        // 写临时文件也放进 try：磁盘满时半写的 uuid 临时文件能被 finally 清掉。
        await temp.writeAsBytes(audioBytes, flush: true);
        if (await localFile.exists()) {
          if (await backup.exists()) await backup.delete();
          await _renameOrCopy(localFile, backup.path);
        }
        await _renameOrCopy(temp, localPath);
      } catch (_) {
        // 移动过程中出现异常：旧文件已挪去 backup 时尽量恢复回原位，
        // 避免用户丢失原有的可用缓存。
        if (!await localFile.exists() && await backup.exists()) {
          await backup.copy(localPath);
        }
        rethrow;
      } finally {
        // finally 里的清理自身不能再抛，否则会顶替真正的失败原因。
        try {
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
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

  /// rename 在 Windows 上遇到目标/源文件被占用（例如音频正在被播放器锁着）
  /// 时会失败，此时降级为 copy + delete 完成同样的搬运。
  Future<void> _renameOrCopy(File source, String destinationPath) async {
    try {
      await source.rename(destinationPath);
    } catch (_) {
      await source.copy(destinationPath);
      try {
        await source.delete();
      } catch (_) {
        // copy 已达成数据目的；源文件被占用删不掉只留下一个临时残留，
        // 不能让「已保存成功」的音频对调用方报失败。
      }
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

/// 单个字符码点 → 16 进制数值（0-15）；非 hex 字符返回 -1。
/// 避免对数百万字符的音频串做全量正则与逐字节 substring（主线程卡死 + GC 风暴）。
int _hexValue(int codeUnit) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30; // 0-9
  if (codeUnit >= 0x41 && codeUnit <= 0x46) return codeUnit - 0x37; // A-F
  if (codeUnit >= 0x61 && codeUnit <= 0x66) return codeUnit - 0x57; // a-f
  return -1;
}

/// 解码 MiniMax 音频数据（支持 Hex 编码及 Base64 编码自动适配）。
/// 顶层函数：可以直接交给 `compute` 在后台 isolate 里跑，测试也可直接调用。
Uint8List decodeAudioData(String raw) {
  final trimmed = raw.trim();

  // 1. 仅采样前 64 个字符判断是否为 Hex：长度为偶数且采样段全为 hex 字符。
  //    音频数据体量极大，全量校验代价过高；首段不一致即可快速排除。
  if (trimmed.length % 2 == 0 && trimmed.isNotEmpty) {
    final sampleEnd = trimmed.length < 64 ? trimmed.length : 64;
    var isHex = true;
    for (var i = 0; i < sampleEnd; i++) {
      if (_hexValue(trimmed.codeUnitAt(i)) < 0) {
        isHex = false;
        break;
      }
    }
    if (isHex) {
      try {
        final len = trimmed.length;
        final result = Uint8List(len ~/ 2);
        for (var i = 0, j = 0; i < len; i += 2, j++) {
          final hi = _hexValue(trimmed.codeUnitAt(i));
          final lo = _hexValue(trimmed.codeUnitAt(i + 1));
          if (hi < 0 || lo < 0) throw const FormatException('含非 hex 字符');
          result[j] = (hi << 4) | lo;
        }
        return result;
      } on FormatException {
        // 中后段混入非 hex 字符（采样未覆盖），回退走 base64
      }
    }
  }

  // 2. 尝试 Base64 解码
  try {
    return base64Decode(trimmed);
  } catch (e) {
    throw Exception('无法识别的 MiniMax 音频编码格式: $e');
  }
}
