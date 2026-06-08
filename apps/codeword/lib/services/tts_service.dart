import 'package:flutter_tts/flutter_tts.dart';

/// Cross-platform text-to-speech wrapper. Lazily initializes a single
/// FlutterTts instance for the whole app.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  FlutterTts? _tts;
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _tts = FlutterTts();
    try {
      await _tts!.setLanguage('en-US');
    } catch (_) {
      // Some Android emulators / dev builds don't have en-US voices;
      // fall through to platform default.
    }
    try {
      await _tts!.setSpeechRate(0.45);
    } catch (_) {}
    try {
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
    } catch (_) {}
    _initialized = true;
  }

  /// Speak [text]. Fire-and-forget; never throws.
  Future<void> speak(String text) async {
    try {
      await _ensureInit();
      await _tts?.stop();
      await _tts?.speak(text);
    } catch (_) {
      // TTS unavailable on this platform (e.g. iOS sim without voices).
      // Silently swallow — audio is a nice-to-have, not a blocker.
    }
  }
}
