import 'dart:async';
import 'dart:developer' as developer;

import 'package:web/web.dart' as web;

import 'tts_backend.dart';

/// Web TTS backend. Uses the browser's built-in `speechSynthesis` API.
/// No caching, no network — the browser handles everything. This means
/// the pronunciation accent depends on the user's OS / browser, not on
/// Youdao's US/UK voices.
class WebTtsBackend implements TtsBackend {
  @override
  Future<bool> speak({required String text, String lang = 'us'}) async {
    try {
      final synth = web.window.speechSynthesis;
      synth.cancel();
      final utter = web.SpeechSynthesisUtterance(text);
      // Map our `us`/`uk` codes onto BCP-47-ish locales the browser
      // is likely to understand. Browsers vary wildly here, so we
      // just pass the bare language code and let the engine pick.
      utter.lang = lang == 'uk' ? 'en-GB' : 'en-US';
      utter.rate = 1.0;
      utter.pitch = 1.0;
      synth.speak(utter);
      developer.log('TTS web speak $text ($lang)', name: 'TtsService');
      return true;
    } catch (e, st) {
      developer.log(
        'TTS web speak failed: $e\n$st',
        name: 'TtsService',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }
}

/// Top-level factory used by the conditional import.
TtsBackend buildTtsBackend() => WebTtsBackend();
