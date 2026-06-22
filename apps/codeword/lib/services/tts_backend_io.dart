import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'qwerty_tts_resolver.dart';
import 'tts_backend.dart';

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

  Future<void>? _cacheDirReady;

  Future<void> _ensureCacheDir() async {
    if (_cacheDirReady != null) return _cacheDirReady;
    final c = Completer<void>();
    _cacheDirReady = c.future;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'tts_cache'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      c.complete();
    } catch (e, st) {
      c.completeError(e, st);
      _cacheDirReady = null;
    }
  }

  String _key(String text, String lang) {
    final h = sha1.convert(utf8.encode('$text|$lang')).toString();
    return h;
  }

  Future<File?> _cacheGet(String text, String lang) async {
    try {
      await _ensureCacheDir();
      final f = File(p.join(
        (await getApplicationDocumentsDirectory()).path,
        'tts_cache',
        '${_key(text, lang)}.mp3',
      ));
      if (await f.exists()) return f;
    } catch (_) {}
    return null;
  }

  Future<File> _cachePut(String text, String lang, List<int> bytes) async {
    await _ensureCacheDir();
    final f = File(p.join(
      (await getApplicationDocumentsDirectory()).path,
      'tts_cache',
      '${_key(text, lang)}.mp3',
    ));
    await f.writeAsBytes(bytes);
    return f;
  }

  @override
  Future<bool> speak({required String text, String lang = 'us'}) async {
    try {
      final cached = await _cacheGet(text, lang);
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
      final file = await _cachePut(text, lang, resp.bodyBytes);
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

/// Top-level factory used by the conditional import.
TtsBackend buildTtsBackend() => IoTtsBackend();
