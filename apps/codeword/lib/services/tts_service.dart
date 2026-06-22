import 'dart:async';
import 'dart:developer' as developer;

import 'tts_backend.dart';
import 'tts_backend_factory.dart';

/// Public TTS facade. The actual implementation (Youdao + audioplayers
/// on desktop/mobile, Web Speech API on web) is selected via
/// conditional import in [tts_backend_factory.dart].
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final TtsBackend _backend = createTtsBackend();

  /// Play the audio for [text]. [lang] is `'us'` (default) or `'uk'`.
  /// Returns true on successful playback, false on any failure.
  Future<bool> speak({required String text, String lang = 'us'}) {
    return _backend.speak(text: text, lang: lang).catchError((e, st) {
      developer.log('TTS backend failed: $e\n$st',
          name: 'TtsService', error: e, stackTrace: st);
      return false;
    });
  }
}
