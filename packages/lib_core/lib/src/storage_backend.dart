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

  /// Wipe all three keys/files (used by the schema-version migration).
  Future<void> wipeAll();
}
