/// TTS backend. Two implementations:
///   - Youdao + audioplayers + on-disk cache (desktop / mobile)
///   - Web Speech API speechSynthesis (web)
///
/// Selected at runtime via conditional import.
abstract class TtsBackend {
  /// Play the audio for [text]. Returns true on success, false on any
  /// failure. Implementations should never throw — failures are
  /// logged and swallowed so a single bad word can't break the flow.
  Future<bool> speak({required String text, String lang});
}
