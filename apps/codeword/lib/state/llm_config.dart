import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';

/// Optional fallback API key (e.g. bundled from a local asset).
/// When the user hasn't configured a key via secure storage, this
/// fallback is used so the app works out of the box.
final llmFallbackKeyProvider = Provider<String?>((ref) => null);

/// Riverpod provider for the current [LlmConfig]. Auto-loads from
/// secure storage on first read; mutations are persisted transparently.
/// If secure storage has no key, falls back to [llmFallbackKeyProvider].
///
/// Concurrency: the [_load] and [save] operations are mutexed via
/// [_loadedOrAssigned] so a user who pastes an API key and taps
/// "Save" BEFORE the initial storage read completes will never have
/// their input overwritten by the stale result of that read.
class LlmConfigNotifier extends StateNotifier<LlmConfig> {
  final LlmConfigStore _store;
  final String? _fallbackKey;

  /// Set to `true` as soon as the user calls [save]/[clear], OR as
  /// soon as the initial [_load] finishes writing to [state]. Guards
  /// against the init-time race where [save] runs while [_load] is
  /// awaiting its storage read.
  bool _loadedOrAssigned = false;

  LlmConfigNotifier(this._store, this._fallbackKey)
      : super(LlmConfig.defaults()) {
    _load();
  }

  /// Load persisted config from secure storage.
  ///
  /// * Any failure in [_store.read] surfaces (does not return defaults
  ///   silently) so the notifier-level fallback + error handling can
  ///   apply uniformly.
  /// * Only updates [state] if neither [save] nor [clear] ran while we
  ///   were awaiting the read — this is the critical mutex.
  Future<void> _load() async {
    final LlmConfig stored;
    try {
      stored = await _store.read();
    } catch (_) {
      // Read failure. Fall back to either the bundled fallback key or
      // true defaults — but ONLY if save() hasn't already been called
      // while we were awaiting.
      if (_loadedOrAssigned) return;
      _loadedOrAssigned = true;
      final fbk = _fallbackKey;
      if (fbk != null && fbk.isNotEmpty) {
        state = LlmConfig(
          baseUrl: LlmConfig.defaultBaseUrl,
          apiKey: fbk,
          model: LlmConfig.defaultModel,
        );
      } else {
        state = LlmConfig.defaults();
      }
      return;
    }

    if (_loadedOrAssigned) return;
    _loadedOrAssigned = true;

    if (stored.apiKey.isNotEmpty) {
      state = stored;
    } else {
      final fbk = _fallbackKey;
      if (fbk != null && fbk.isNotEmpty) {
        // Storage has no key but a local fallback exists — keep the
        // user's stored baseUrl / model (if any) and only inject the key.
        state = LlmConfig(
          baseUrl: stored.baseUrl.isEmpty ? LlmConfig.defaultBaseUrl : stored.baseUrl,
          apiKey: fbk,
          model: stored.model.isEmpty ? LlmConfig.defaultModel : stored.model,
        );
      } else {
        state = stored;
      }
    }
  }

  /// Persist a new config.
  ///
  /// Ordering: storage WRITE succeeds BEFORE the in-memory [state] is
  /// updated. This guarantees that on the next app restart the config
  /// we read from storage matches what the in-memory state claims —
  /// there is no window where the UI shows "saved" but killing the
  /// process reverts the change.
  ///
  /// Any storage failure is rethrown so callers can present a snackbar.
  Future<void> save(LlmConfig config) async {
    // Mark the mutex BEFORE awaiting so a concurrent _load() cannot
    // overwrite our state even if it resumes right after the write.
    _loadedOrAssigned = true;
    await _store.write(config);
    state = config;
  }

  /// Reset to defaults and wipe all three fields from secure storage.
  ///
  /// Same ordering guarantee as [save]: only updates memory after the
  /// storage wipe has confirmed.
  Future<void> clear() async {
    _loadedOrAssigned = true;
    await _store.clear();
    state = LlmConfig.defaults();
  }
}

final llmConfigProvider =
    StateNotifierProvider<LlmConfigNotifier, LlmConfig>((ref) {
  return LlmConfigNotifier(
    LlmConfigStore(),
    ref.watch(llmFallbackKeyProvider),
  );
});

/// An LLM client bound to the current config. Re-builds whenever the
/// config changes; the previous client's HTTP connection pool is
/// closed on disposal so socket handles don't leak across reconfigs.
final llmClientProvider = Provider<LlmClient>((ref) {
  final config = ref.watch(llmConfigProvider);
  final client = LlmClient(config: config);
  ref.onDispose(() {
    try {
      client.close();
    } catch (_) {
      // Best-effort cleanup.
    }
  });
  return client;
});

/// Quick "is the user set up?" gate used by gated UI (Reading tab,
/// future "AI explain" buttons, etc.).
final llmConfiguredProvider = Provider<bool>((ref) {
  final c = ref.watch(llmConfigProvider);
  return c.isConfigured;
});
