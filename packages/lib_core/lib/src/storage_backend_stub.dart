import 'storage_backend.dart';

/// Fallback stub. The conditional import should never land here at
/// runtime, but a top-level function is required by the factory file.
StorageBackend buildStorageBackend() {
  throw UnsupportedError(
    'No storage backend available for this platform.',
  );
}
