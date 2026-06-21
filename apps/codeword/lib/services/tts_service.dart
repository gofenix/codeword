import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import 'qwerty_tts_resolver.dart';
import 'tts_cache.dart';

/// Self-contained text-to-speech for vocabulary words.
///
/// 1. Check on-disk cache (`<appDocs>/tts_cache/<sha1>.mp3`) — play if hit.
/// 2. Otherwise fetch from Youdao `dictvoice` and cache the bytes, then play.
///
/// No bundled OGG assets; no system TTS. Always network on first hit,
/// offline after that. The Youdao endpoint is a public, no-auth,
/// CORS-open resource.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final AudioPlayer _player = AudioPlayer();
  static const String _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';

  /// Play the audio for [text]. [lang] is `'us'` (default) or `'uk'`.
  /// Returns true on successful playback, false on any failure.
  Future<bool> speak({required String text, String lang = 'us'}) async {
    try {
      final cached = await TtsCache.get(text, lang);
      if (cached != null) {
        await _playFile(cached);
        developer.log('TTS cache hit $text ($lang)', name: 'TtsService');
        return true;
      }
      final resp = await http
          .get(
            Uri.parse(youdaoAudioUrl(text, lang)),
            headers: const {'User-Agent': _userAgent},
          )
          .timeout(const Duration(seconds: 8));
      final ct = resp.headers['content-type'] ?? '';
      if (resp.statusCode != 200 ||
          resp.bodyBytes.isEmpty ||
          !ct.contains('audio')) {
        developer.log(
          'TTS fetch bad: status=${resp.statusCode} ct=$ct for $text',
          name: 'TtsService',
        );
        return false;
      }
      final file = await TtsCache.put(text, lang, resp.bodyBytes);
      await _playFile(file);
      developer.log('TTS fetched + cached $text ($lang)', name: 'TtsService');
      return true;
    } catch (e, st) {
      developer.log('TTS play failed: $e\n$st',
          name: 'TtsService', error: e, stackTrace: st);
      return false;
    }
  }

  Future<void> _playFile(File f) async {
    await _player.stop();
    await _player.play(DeviceFileSource(f.path));
  }
}
