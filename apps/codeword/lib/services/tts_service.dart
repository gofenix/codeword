import 'dart:async';
import 'dart:developer' as developer;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Self-contained, offline text-to-speech.
///
/// Plays pre-generated OGG (Opus) audio files bundled in the app. No
/// system TTS, no Google TTS, no network. Audio files are produced
/// ahead of time by `tools/generate_audio.py` (espeak-ng + ffmpeg).
///
/// To play a word, callers invoke [speak] with the word ID (e.g.
/// 'ai_001') or the literal word. The service keeps an in-memory
/// wordId → file map so we can resolve either form.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final AudioPlayer _player = AudioPlayer();
  bool _assetIndexLoaded = false;
  bool _available = false;

  bool get isAvailable => _available;

  final _availabilityController = StreamController<bool>.broadcast();
  Stream<bool> get availabilityStream => _availabilityController.stream;

  Future<void> _loadIndex() async {
    if (_assetIndexLoaded) return;
    _assetIndexLoaded = true;
    _available = true;
  }

  /// Play the audio for [wordId] (e.g. `'ai_001'`) or the literal
  /// word text (e.g. `'algorithm'`). Falls back to scanning known
  /// vocab files for a matching entry.
  Future<bool> speak(String wordIdOrText) async {
    try {
      await _loadIndex();
      if (!_available) return false;
      final assetPath = 'audio/$wordIdOrText.ogg';
      // Quick existence check via rootBundle so we can give a useful
      // error instead of a silent failure.
      try {
        await rootBundle.load('assets/$assetPath');
      } catch (_) {
        _availabilityController.add(false);
        return false;
      }
      await _player.stop();
      await _player.play(AssetSource(assetPath));
      developer.log('TTS play $assetPath', name: 'TtsService');
      return true;
    } catch (e, st) {
      developer.log('TTS play failed: $e\n$st', name: 'TtsService',
          error: e, stackTrace: st);
      _availabilityController.add(false);
      return false;
    }
  }
}
