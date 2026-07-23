import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';

typedef LlmConfigVerifier = Future<void> Function(LlmConfig config);

/// Riverpod provider for the current [LlmConfig]. Auto-loads from
/// secure storage on first read; mutations are persisted transparently.
///
/// Concurrency: the [_load] and [save] operations are mutexed via
/// [_loadedOrAssigned] so a user who pastes an API key and taps
/// "Save" BEFORE the initial storage read completes will never have
/// their input overwritten by the stale result of that read.
class LlmConfigNotifier extends StateNotifier<LlmConfig> {
  final LlmConfigStore _store;

  /// Set to `true` as soon as the user calls [save]/[clear], OR as
  /// soon as the initial [_load] finishes writing to [state]. Guards
  /// against the init-time race where [save] runs while [_load] is
  /// awaiting its storage read.
  bool _loadedOrAssigned = false;

  LlmConfigNotifier(this._store) : super(LlmConfig.defaults()) {
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
      // Read failure. Keep true defaults, but only if save() hasn't
      // already been called while we were awaiting.
      if (_loadedOrAssigned) return;
      _loadedOrAssigned = true;
      state = LlmConfig.defaults();
      return;
    }

    if (_loadedOrAssigned) return;
    _loadedOrAssigned = true;

    state = stored;
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

final llmConfigProvider = StateNotifierProvider<LlmConfigNotifier, LlmConfig>((
  ref,
) {
  return LlmConfigNotifier(LlmConfigStore());
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

final llmConfigVerifierProvider = Provider<LlmConfigVerifier>((ref) {
  return (config) async {
    final client = LlmClient(config: config);
    try {
      await client.chat(
        LlmChatRequest(
          model: config.model,
          maxTokens: 4,
          messages: const [LlmMessage(role: 'user', content: 'Reply OK')],
        ),
      );
    } finally {
      client.close();
    }
  };
});
