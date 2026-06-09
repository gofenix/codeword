import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';

/// Riverpod provider for the current [LlmConfig]. Auto-loads from
/// secure storage on first read; mutations are persisted transparently.
class LlmConfigNotifier extends StateNotifier<LlmConfig> {
  final LlmConfigStore _store;

  LlmConfigNotifier(this._store) : super(LlmConfig.defaults()) {
    _load();
  }

  Future<void> _load() async {
    try {
      state = await _store.read();
    } catch (_) {
      // Keep defaults if storage is unavailable.
    }
  }

  /// Persist a new config. The key change applies immediately.
  Future<void> save(LlmConfig config) async {
    state = config;
    await _store.write(config);
  }

  /// Reset to defaults and wipe the key.
  Future<void> clear() async {
    state = LlmConfig.defaults();
    await _store.clear();
  }
}

final llmConfigProvider =
    StateNotifierProvider<LlmConfigNotifier, LlmConfig>((ref) {
  return LlmConfigNotifier(LlmConfigStore());
});

/// Convenience: an LLM client bound to the current config. Re-builds
/// whenever the config changes (e.g. user pastes a new key).
final llmClientProvider = Provider<LlmClient>((ref) {
  final config = ref.watch(llmConfigProvider);
  return LlmClient(config: config);
});

/// Quick "is the user set up?" gate used by gated UI (Reading tab,
/// future "AI explain" buttons, etc.).
final llmConfiguredProvider = Provider<bool>((ref) {
  final c = ref.watch(llmConfigProvider);
  return c.isConfigured;
});
