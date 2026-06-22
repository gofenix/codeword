import 'tts_backend.dart';
import 'tts_backend_stub.dart'
    if (dart.library.io) 'tts_backend_io.dart'
    if (dart.library.js_interop) 'tts_backend_web.dart';

TtsBackend createTtsBackend() => buildTtsBackend();
