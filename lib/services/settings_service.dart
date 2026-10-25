import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsService {
  static const _prefsKey = 'bookbuddy_settings';
  static const _secureFullKey = 'sec_full_settings_v2';
  static const _secureLlmKey = 'sec_llm_api_key';
  static const _secureImgKey = 'sec_image_api_key';
  static const _secureFbImgKey = 'sec_fb_image_api_key';

  static const _backupLlmKey = 'bk_llm_api_key';
  static const _backupImgKey = 'bk_image_api_key';
  static const _backupFbImgKey = 'bk_fb_image_api_key';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _triedLegacyCleanup = false;

  /// 本进程内安全存储读取是否失败过（Keystore 损坏等）。置位后 [_doSave]
  /// 会先做恢复读，防止「读到空密钥 → 保存覆盖 → 密钥永久丢失」。
  static bool _secureReadFailed = false;

  /// 进程内保存队列：loadSettings 里的 legacy 清理会触发 saveSettings，
  /// 与用户侧并发保存交错时按调用顺序串行执行，防 last-write-wins 丢更新。
  static Future<void>? _saveQueue;

  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    AppSettings settings;
    if (raw != null) {
      try {
        settings = AppSettings.fromJson(jsonDecode(raw));
      } catch (_) {
        settings = AppSettings();
      }
    } else {
      settings = AppSettings();
    }

    // 尝试从 Keychain 安全硬件存储读取更完整的配置
    try {
      final secFull = await _secureStorage.read(key: _secureFullKey);
      _secureReadFailed = false;
      if (secFull != null && secFull.isNotEmpty) {
        final secSettings = AppSettings.fromJson(jsonDecode(secFull));
        _mergeSecretKeys(settings, secSettings);
      }
    } catch (_) {
      // 安全存储读取失败（Android Keystore 损坏/恢复后是已知故障源）：
      // 标记本次会话读取不健康。此时内存里的密钥全空只是「没读到」，
      // 后续保存若直接覆盖安全存储会把用户所有 API Key 永久清空。
      _secureReadFailed = true;
    }

    // 兼容旧版单密钥存储：仅在确认为无 profiles 的纯老版本数据时迁移，
    // 否则旧 key 会注入当前激活 profile，造成跨 profile 密钥污染
    // （例如旧版 Gemini 的 key 被写进 DeepSeek profile）。
    final legacySingleKeyData = _isLegacySingleKeyData(raw);
    if (legacySingleKeyData && settings.llmApiKey.isEmpty) {
      try {
        final secLlm = await _secureStorage.read(key: _secureLlmKey);
        if (secLlm != null && secLlm.isNotEmpty) {
          settings.llmApiKey = secLlm;
        } else {
          settings.llmApiKey = prefs.getString(_backupLlmKey) ?? '';
        }
      } catch (_) {
        settings.llmApiKey = prefs.getString(_backupLlmKey) ?? '';
      }
    }

    if (legacySingleKeyData && settings.imageApiKey.isEmpty) {
      try {
        final secImg = await _secureStorage.read(key: _secureImgKey);
        if (secImg != null && secImg.isNotEmpty) {
          settings.imageApiKey = secImg;
        } else {
          settings.imageApiKey = prefs.getString(_backupImgKey) ?? '';
        }
      } catch (_) {
        settings.imageApiKey = prefs.getString(_backupImgKey) ?? '';
      }
    }

    if (settings.fallbackImageApiKey.isEmpty) {
      try {
        final secFbImg = await _secureStorage.read(key: _secureFbImgKey);
        if (secFbImg != null && secFbImg.isNotEmpty) {
          settings.fallbackImageApiKey = secFbImg;
        } else {
          settings.fallbackImageApiKey = prefs.getString(_backupFbImgKey) ?? '';
        }
      } catch (_) {
        settings.fallbackImageApiKey = prefs.getString(_backupFbImgKey) ?? '';
      }
    }

    // Upgrade older plaintext preferences only after the secure copy can be
    // written. If secure storage is unavailable, retain the legacy fallback.
    final hasLegacySecrets =
        (raw != null && _containsSecrets(raw)) ||
        [
          _backupLlmKey,
          _backupImgKey,
          _backupFbImgKey,
        ].any((key) => (prefs.getString(key)?.isNotEmpty ?? false));
    if (hasLegacySecrets && !_triedLegacyCleanup) {
      _triedLegacyCleanup = true;
      try {
        await saveSettings(settings);
      } catch (_) {
        // Keep serving settings even if cleanup cannot be completed yet.
      }
    }
    return settings;
  }

  /// 纯老版本数据（无 llmProfiles / imageProfiles 列表）才允许做单密钥迁移。
  bool _isLegacySingleKeyData(String? raw) {
    if (raw == null) return false;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return (data['llmProfiles'] as List? ?? const []).isEmpty &&
          (data['imageProfiles'] as List? ?? const []).isEmpty;
    } catch (_) {
      return false;
    }
  }

  bool _containsSecrets(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if ([
        'llmApiKey',
        'imageApiKey',
        'fallbackImageApiKey',
        'minimaxApiKey',
      ].any((key) => (data[key] as String?)?.isNotEmpty ?? false)) {
        return true;
      }
      for (final key in ['llmProfiles', 'imageProfiles']) {
        final profiles = data[key];
        if (profiles is List &&
            profiles.any(
              (profile) =>
                  profile is Map &&
                  (profile['apiKey'] as String?)?.isNotEmpty == true,
            )) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> saveSettings(AppSettings settings) {
    final previous = _saveQueue;
    final save = _runSave(previous, settings);
    _saveQueue = save;
    // 队列里排在前面的保存先完成；失败不阻塞后续保存。
    return save.whenComplete(() {
      if (identical(_saveQueue, save)) _saveQueue = null;
    });
  }

  Future<void> _runSave(Future<void>? previous, AppSettings settings) async {
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // A failed earlier save must not block later attempts.
      }
    }
    await _doSave(settings);
  }

  /// 把 [source]（安全存储读出的完整配置）中的密钥按「只填空」策略合并进 [target]。
  static void _mergeSecretKeys(AppSettings target, AppSettings source) {
    for (var p in source.llmProfiles) {
      final t = target.llmProfiles.where((x) => x.id == p.id).firstOrNull;
      if (t != null && t.apiKey.isEmpty && p.apiKey.isNotEmpty) {
        t.apiKey = p.apiKey;
      }
    }
    for (var p in source.imageProfiles) {
      final t = target.imageProfiles.where((x) => x.id == p.id).firstOrNull;
      if (t != null && t.apiKey.isEmpty && p.apiKey.isNotEmpty) {
        t.apiKey = p.apiKey;
      }
    }
    if (target.fallbackImageApiKey.isEmpty &&
        source.fallbackImageApiKey.isNotEmpty) {
      target.fallbackImageApiKey = source.fallbackImageApiKey;
    }
    if (target.minimaxApiKey.isEmpty && source.minimaxApiKey.isNotEmpty) {
      target.minimaxApiKey = source.minimaxApiKey;
    }
  }

  Future<void> _doSave(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    if (_secureReadFailed) {
      // 本会话安全存储读取失败过：内存里的密钥可能只是「没读到」而非「真没有」。
      // 先尝试恢复读一次：读到了就把真实密钥按只填空策略并回来再保存；
      // 仍然失败说明安全存储当前不可用，只写无密钥的公开配置并放弃本次
      // 密钥写回——绝不能用可能缺失密钥的内存状态覆盖安全存储。
      try {
        final secFull = await _secureStorage.read(key: _secureFullKey);
        _secureReadFailed = false;
        if (secFull != null && secFull.isNotEmpty) {
          _mergeSecretKeys(settings, AppSettings.fromJson(jsonDecode(secFull)));
        }
      } catch (_) {
        await prefs.setString(_prefsKey, jsonEncode(settings.toPublicJson()));
        return;
      }
    }

    final jsonString = jsonEncode(settings.toJson());

    // 尝试写入 Keychain / Keystore 安全硬件存储
    bool secureSuccess = true;
    try {
      await _secureStorage.write(key: _secureFullKey, value: jsonString);
      await _secureStorage.write(key: _secureLlmKey, value: settings.llmApiKey);
      await _secureStorage.write(
        key: _secureImgKey,
        value: settings.imageApiKey,
      );
      await _secureStorage.write(
        key: _secureFbImgKey,
        value: settings.fallbackImageApiKey,
      );
    } catch (_) {
      secureSuccess = false;
    }

    if (secureSuccess) {
      await prefs.setString(_prefsKey, jsonEncode(settings.toPublicJson()));
      await prefs.remove(_backupLlmKey);
      await prefs.remove(_backupImgKey);
      await prefs.remove(_backupFbImgKey);
    } else {
      // Keep legacy settings usable on hosts where secure storage is unavailable.
      await prefs.setString(_prefsKey, jsonString);
      await prefs.setString(_backupLlmKey, settings.llmApiKey);
      await prefs.setString(_backupImgKey, settings.imageApiKey);
      await prefs.setString(_backupFbImgKey, settings.fallbackImageApiKey);
    }
  }
}
