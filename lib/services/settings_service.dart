import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

class SettingsService {
  static const _prefsKey = 'bookbuddy_settings';
  static const _secureLlmKey = 'sec_llm_api_key';
  static const _secureImgKey = 'sec_image_api_key';
  static const _secureFbImgKey = 'sec_fb_image_api_key';

  static const _backupLlmKey = 'bk_llm_api_key';
  static const _backupImgKey = 'bk_image_api_key';
  static const _backupFbImgKey = 'bk_fb_image_api_key';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

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

    // 优先从安全存储读取敏感 key，若环境不支持钥匙串（如未签名的调试沙箱）则从本地备份恢复
    try {
      final secLlm = await _secureStorage.read(key: _secureLlmKey);
      if (secLlm != null && secLlm.isNotEmpty) {
        settings.llmApiKey = secLlm;
      } else {
        settings.llmApiKey = prefs.getString(_backupLlmKey) ?? settings.llmApiKey;
      }
    } catch (_) {
      settings.llmApiKey = prefs.getString(_backupLlmKey) ?? settings.llmApiKey;
    }

    try {
      final secImg = await _secureStorage.read(key: _secureImgKey);
      if (secImg != null && secImg.isNotEmpty) {
        settings.imageApiKey = secImg;
      } else {
        settings.imageApiKey = prefs.getString(_backupImgKey) ?? settings.imageApiKey;
      }
    } catch (_) {
      settings.imageApiKey = prefs.getString(_backupImgKey) ?? settings.imageApiKey;
    }

    try {
      final secFbImg = await _secureStorage.read(key: _secureFbImgKey);
      if (secFbImg != null && secFbImg.isNotEmpty) {
        settings.fallbackImageApiKey = secFbImg;
      } else {
        settings.fallbackImageApiKey = prefs.getString(_backupFbImgKey) ?? settings.fallbackImageApiKey;
      }
    } catch (_) {
      settings.fallbackImageApiKey = prefs.getString(_backupFbImgKey) ?? settings.fallbackImageApiKey;
    }

    return settings;
  }

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    final toSave = AppSettings.fromJson(settings.toJson());
    toSave.llmApiKey = '';
    toSave.imageApiKey = '';
    toSave.fallbackImageApiKey = '';

    await prefs.setString(_prefsKey, jsonEncode(toSave.toJson()));

    // 尝试写入 Keychain / Keystore 安全硬件存储
    bool secureSuccess = true;
    try {
      await _secureStorage.write(key: _secureLlmKey, value: settings.llmApiKey);
      await _secureStorage.write(key: _secureImgKey, value: settings.imageApiKey);
      await _secureStorage.write(
          key: _secureFbImgKey, value: settings.fallbackImageApiKey);
    } catch (_) {
      secureSuccess = false;
    }

    // 降级兜底：当在 macOS 本地未签名调试或沙箱 Entitlement 冲突时，安全存储写入本地隔离 prefs
    if (!secureSuccess) {
      await prefs.setString(_backupLlmKey, settings.llmApiKey);
      await prefs.setString(_backupImgKey, settings.imageApiKey);
      await prefs.setString(_backupFbImgKey, settings.fallbackImageApiKey);
    }
  }
}
