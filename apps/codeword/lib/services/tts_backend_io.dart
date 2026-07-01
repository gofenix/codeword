import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'qwerty_tts_resolver.dart';
import 'tts_backend.dart';
import 'tts_cache.dart';

/// Desktop / mobile TTS backend. Two-step:
///   1. Check on-disk cache (`<appDocs>/tts_cache/<sha1>.mp3`) — play if hit.
///   2. Otherwise fetch from Youdao `dictvoice` and cache the bytes, then play.
///
/// No bundled OGG assets; no system TTS. Always network on first hit,
/// offline after that. The Youdao endpoint is a public, no-auth,
/// CORS-open resource.
class IoTtsBackend implements TtsBackend {
  final AudioPlayer _player = AudioPlayer();
  static const String _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';

  TtsCache? _cache;

  Future<TtsCache> _ensureCache() async {
    if (_cache != null) return _cache!;
    final docs = await getApplicationDocumentsDirectory();
    final cache = TtsCache(Directory(p.join(docs.path, 'tts_cache')));
    await cache.ensureReady();
    _cache = cache;
    return cache;
  }

  @override
  Future<bool> speak({required String text, String lang = 'us'}) async {
    try {
      final cache = await _ensureCache();
      final entry = await cache.getOrFetchEntry(text, lang, () async {
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
          return null;
        }
        return resp.bodyBytes;
      });

      if (entry == null) return false;

      switch (entry.source) {
        case TtsCacheSource.cached:
          developer.log('TTS cache hit $text ($lang)', name: 'TtsService');
        case TtsCacheSource.fetched:
          developer.log(
            'TTS fetched + cached $text ($lang)',
            name: 'TtsService',
          );
        case TtsCacheSource.shared:
          developer.log(
            'TTS joined in-flight fetch $text ($lang)',
            name: 'TtsService',
          );
      }
      await _playFile(entry.file);
      return true;
    } catch (e, st) {
      developer.log(
        'TTS play failed: $e\n$st',
        name: 'TtsService',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  Future<void> _playFile(File f) async {
    await _player.stop();
    await _player.play(DeviceFileSource(f.path));
  }
}

/// Top-level factory used by the conditional import.
TtsBackend buildTtsBackend() => IoTtsBackend();
