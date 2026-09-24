import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookbuddy/models/book.dart';
import 'package:bookbuddy/models/app_settings.dart';

void main() {
  group('TTS Model & Serialization Tests', () {
    test('BookPageItem audioPath toJson and fromJson', () {
      final page = BookPageItem(
        pageIndex: 0,
        text: '很久很久以前，森林里住着一只小鹿。',
        audioPath: '/data/user/0/com.example.bookbuddy/app_flutter/audio_p0.mp3',
      );

      final jsonMap = page.toJson();
      expect(jsonMap['audioPath'], '/data/user/0/com.example.bookbuddy/app_flutter/audio_p0.mp3');

      final restored = BookPageItem.fromJson(jsonMap);
      expect(restored.audioPath, page.audioPath);
      expect(restored.text, page.text);
    });

    test('AppSettings TTS fields default and serialization', () {
      final settings = AppSettings();
      expect(settings.ttsEnabled, isTrue);
      expect(settings.minimaxSpeed, 0.85);
      expect(settings.minimaxModel, 'speech-01-turbo');
      expect(settings.minimaxVoiceId, 'audiobook_female_1');

      settings.minimaxApiKey = 'test_key';
      settings.minimaxGroupId = 'test_group_id';
      settings.minimaxSpeed = 0.80;

      final jsonMap = settings.toJson();
      expect(jsonMap['minimaxApiKey'], 'test_key');
      expect(jsonMap['minimaxGroupId'], 'test_group_id');
      expect(jsonMap['minimaxSpeed'], 0.80);

      final restored = AppSettings.fromJson(jsonMap);
      expect(restored.minimaxApiKey, 'test_key');
      expect(restored.minimaxGroupId, 'test_group_id');
      expect(restored.minimaxSpeed, 0.80);
    });
  });
}
