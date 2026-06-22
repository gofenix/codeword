import 'dart:async';
import 'dart:developer' as developer;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'tts_backend.dart';

/// Web TTS backend. Uses the browser's built-in `speechSynthesis` API.
/// No caching, no network — the browser handles everything. This means
/// the pronunciation accent depends on the user's OS / browser, not on
/// Youdao's US/UK voices.
class WebTtsBackend implements TtsBackend {
  @override
  Future<bool> speak({required String text, String lang = 'us'}) async {
    try {
      final synth = html.window.speechSynthesis;
      if (synth == null) return false;
      synth.cancel();
      final utter = html.SpeechSynthesisUtterance(text);
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
      developer.log('TTS web speak failed: $e\n$st',
          name: 'TtsService', error: e, stackTrace: st);
      return false;
    }
  }
}

/// Top-level factory used by the conditional import.
TtsBackend buildTtsBackend() => WebTtsBackend();
