import 'storage_backend.dart';

/// In-memory [StorageBackend] for unit tests — no path_provider needed.
class InMemoryStorageBackend implements StorageBackend {
  Map<String, dynamic>? review;
  Map<String, dynamic>? activity;
  Map<String, dynamic>? userData;

  @override
  Future<Map<String, dynamic>?> loadReviewState() async => review;

  @override
  Future<void> saveReviewState(Map<String, dynamic> json) async {
    review = Map<String, dynamic>.from(json);
  }

  @override
  Future<Map<String, dynamic>?> loadActivity() async => activity;

  @override
  Future<void> saveActivity(Map<String, dynamic> json) async {
    activity = Map<String, dynamic>.from(json);
  }

  @override
  Future<Map<String, dynamic>?> loadUserData() async => userData;

  @override
  Future<void> saveUserData(Map<String, dynamic> json) async {
    userData = Map<String, dynamic>.from(json);
  }

  @override
  Future<void> wipeReviewAndActivity() async {
    review = null;
    activity = null;
  }

  @override
  Future<void> wipeAll() async {
    review = null;
    activity = null;
    userData = null;
  }
}