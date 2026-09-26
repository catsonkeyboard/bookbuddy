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
      if (secFull != null && secFull.isNotEmpty) {
        final secSettings = AppSettings.fromJson(jsonDecode(secFull));
        // 将安全存储中的 profiles key 同步到设置中
        for (var p in secSettings.llmProfiles) {
          final target = settings.llmProfiles
              .where((x) => x.id == p.id)
              .firstOrNull;
          if (target != null && target.apiKey.isEmpty && p.apiKey.isNotEmpty) {
            target.apiKey = p.apiKey;
          }
        }
        for (var p in secSettings.imageProfiles) {
          final target = settings.imageProfiles
              .where((x) => x.id == p.id)
              .firstOrNull;
          if (target != null && target.apiKey.isEmpty && p.apiKey.isNotEmpty) {
            target.apiKey = p.apiKey;
          }
        }
        if (settings.fallbackImageApiKey.isEmpty &&
            secSettings.fallbackImageApiKey.isNotEmpty) {
          settings.fallbackImageApiKey = secSettings.fallbackImageApiKey;
        }
        if (settings.minimaxApiKey.isEmpty &&
            secSettings.minimaxApiKey.isNotEmpty) {
          settings.minimaxApiKey = secSettings.minimaxApiKey;
        }
      }
    } catch (_) {}

    // 兼容旧版：若当前激活 profile 的 key 为空，尝试从旧的安全存储中读取恢复
    if (settings.llmApiKey.isEmpty) {
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

    if (settings.imageApiKey.isEmpty) {
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

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

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
