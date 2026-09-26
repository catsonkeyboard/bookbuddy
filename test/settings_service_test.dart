import 'dart:convert';

import 'package:bookbuddy/models/app_settings.dart';
import 'package:bookbuddy/services/settings_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'saves secrets only to secure storage and restores all profiles',
    () async {
      final settings = AppSettings();
      settings.llmProfiles[0].apiKey = 'llm-secret';
      settings.llmProfiles[1].apiKey = 'other-llm-secret';
      settings.imageProfiles[0].apiKey = 'image-secret';
      settings.imageProfiles[1].apiKey = 'other-image-secret';
      settings.fallbackImageApiKey = 'fallback-secret';
      settings.minimaxApiKey = 'tts-secret';

      final service = SettingsService();
      await service.saveSettings(settings);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('bookbuddy_settings'), isNot(contains('secret')));
      expect(prefs.getString('bk_llm_api_key'), isNull);
      expect(prefs.getString('bk_image_api_key'), isNull);
      expect(prefs.getString('bk_fb_image_api_key'), isNull);

      final restored = await service.loadSettings();
      expect(restored.llmProfiles[0].apiKey, 'llm-secret');
      expect(restored.llmProfiles[1].apiKey, 'other-llm-secret');
      expect(restored.imageProfiles[0].apiKey, 'image-secret');
      expect(restored.imageProfiles[1].apiKey, 'other-image-secret');
      expect(restored.fallbackImageApiKey, 'fallback-secret');
      expect(restored.minimaxApiKey, 'tts-secret');
    },
  );

  test('migrates plaintext settings without losing configured keys', () async {
    final settings = AppSettings();
    settings.llmProfiles[1].apiKey = 'legacy-llm';
    settings.imageProfiles[1].apiKey = 'legacy-image';
    settings.minimaxApiKey = 'legacy-tts';
    SharedPreferences.setMockInitialValues({
      'bookbuddy_settings': jsonEncode(settings.toJson()),
    });

    final restored = await SettingsService().loadSettings();
    expect(restored.llmProfiles[1].apiKey, 'legacy-llm');
    expect(restored.imageProfiles[1].apiKey, 'legacy-image');
    expect(restored.minimaxApiKey, 'legacy-tts');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bookbuddy_settings'), isNot(contains('legacy-')));
    final secure = const FlutterSecureStorage();
    expect(
      await secure.read(key: 'sec_full_settings_v2'),
      contains('legacy-tts'),
    );
  });
}
