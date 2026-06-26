import 'dart:async';

/// Storage backend for the user's review state, activity, and user data.
///
/// Two implementations exist: a file-based one for desktop / mobile
/// (see `storage_backend_io.dart`) and a localStorage-based one for
/// web (see `storage_backend_web.dart`). Selected at runtime via
/// conditional import in `storage_backend_factory.dart`.
abstract class StorageBackend {
  /// Load the per-word review-state JSON.
  /// Returns the decoded map, or `null` if the file/key doesn't exist.
  Future<Map<String, dynamic>?> loadReviewState();

  /// Save the per-word review-state JSON.
  Future<void> saveReviewState(Map<String, dynamic> json);

  /// Load the daily activity JSON.
  Future<Map<String, dynamic>?> loadActivity();

  /// Save the daily activity JSON.
  Future<void> saveActivity(Map<String, dynamic> json);

  /// Load the user-data JSON.
  Future<Map<String, dynamic>?> loadUserData();

  /// Save the user-data JSON.
  Future<void> saveUserData(Map<String, dynamic> json);

  /// Wipe ONLY the two legacy stores (review state + activity).
  ///
  /// MUST NOT touch user-data — that store carries the
  /// `schemaVersion` header that prevents infinite re-migration on
  /// every launch. Used by [ReviewRepository] during schema upgrades.
  ///
  /// Default implementation throws [UnsupportedError] so callers can
  /// fall back to writing empty payloads.
  Future<void> wipeReviewAndActivity() async {
    throw UnsupportedError('wipeReviewAndActivity is not implemented by this backend');
  }

  /// Wipe all three keys/files. Only used by testing / full-reset flows.
  Future<void> wipeAll();
}
