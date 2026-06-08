import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_tts/flutter_tts.dart';

/// Cross-platform text-to-speech wrapper.
///
/// On Android, the plugin delegates to whatever TTS engine the user has
/// installed (usually Google TTS or Samsung TTS). If no engine is
/// available, or en-US voice data isn't installed, [speak] returns
/// false and the caller should surface a helpful message.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  FlutterTts? _tts;
  bool _initialized = false;
  bool _available = false;
  String? _activeLanguage;

  bool get isAvailable => _available;
  String? get activeLanguage => _activeLanguage;

  /// Emits true when the TTS engine is ready and a voice pack is loaded,
  /// false when speak() was requested but the platform reported failure.
  final _availabilityController = StreamController<bool>.broadcast();
  Stream<bool> get availabilityStream => _availabilityController.stream;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _tts = FlutterTts();

    // 1. Pick the best engine on Android.
    try {
      final engines = await _tts!.getEngines;
      final engineList = (engines as List?)?.cast<String>() ?? const <String>[];
      developer.log('TTS engines: $engineList', name: 'TtsService');
      // Prefer Google TTS → com.samsung.tts.engine → anything else.
      const preferred = ['com.google.android.tts', 'com.samsung.tts.engine'];
      for (final want in preferred) {
        if (engineList.contains(want)) {
          await _tts!.setEngine(want);
          developer.log('TTS engine selected: $want', name: 'TtsService');
          break;
        }
      }
    } catch (e) {
      developer.log('TTS engine probe failed: $e', name: 'TtsService');
    }

    // 2. Pick a language that's actually available on this device.
    // en-US is the default the user asked for. Fall back through en-GB,
    // en, or whatever the platform says is installed.
    const candidates = ['en-US', 'en-GB', 'en'];
    String? chosen;
    for (final lang in candidates) {
      try {
        final ok = await _tts!.isLanguageAvailable(lang);
        // Android returns 1 for available, 0 for not. iOS returns true/false.
        if (ok == 1 || ok == true) {
          final set = await _tts!.setLanguage(lang);
          // setLanguage also returns 1/0 (Android) or true/false (iOS).
          if (set == 1 || set == true || set == null) {
            chosen = lang;
            break;
          }
        }
      } catch (e) {
        developer.log('TTS language $lang probe failed: $e', name: 'TtsService');
      }
    }
    if (chosen == null) {
      developer.log('No usable TTS language found', name: 'TtsService');
      _available = false;
      _initialized = true;
      return;
    }
    _activeLanguage = chosen;
    developer.log('TTS language: $chosen', name: 'TtsService');

    // 3. Configure voice.
    try {
      await _tts!.setSpeechRate(0.45);
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
    } catch (e) {
      developer.log('TTS voice config failed: $e', name: 'TtsService');
    }

    // 4. Wire up completion + error handlers so we know if speak() actually
    // produced audio.
    try {
      _tts!.setStartHandler(() {
        developer.log('TTS started', name: 'TtsService');
      });
      _tts!.setCompletionHandler(() {
        developer.log('TTS completed', name: 'TtsService');
      });
      _tts!.setErrorHandler((msg) {
        developer.log('TTS error: $msg', name: 'TtsService');
        _available = false;
        _availabilityController.add(false);
      });
      _tts!.setCancelHandler(() {
        developer.log('TTS cancelled', name: 'TtsService');
      });
    } catch (e) {
      developer.log('TTS handler wire-up failed: $e', name: 'TtsService');
    }

    _available = true;
    _initialized = true;
  }

  /// Speak [text]. Returns true if the utterance was dispatched to the
  /// platform TTS engine. Returns false (and emits on availabilityStream)
  /// if TTS is unavailable on this device.
  Future<bool> speak(String text) async {
    try {
      await _ensureInit();
      if (!_available || _tts == null) {
        _availabilityController.add(false);
        return false;
      }
      await _tts!.stop();
      final result = await _tts!.speak(text);
      // speak() returns 1/true on success, 0/false on failure.
      final ok = result == 1 || result == true || result == null;
      developer.log('TTS speak("$text") → $ok (raw: $result)',
          name: 'TtsService');
      return ok;
    } catch (e, st) {
      developer.log('TTS speak threw: $e\n$st', name: 'TtsService',
          error: e, stackTrace: st);
      _availabilityController.add(false);
      return false;
    }
  }
}
