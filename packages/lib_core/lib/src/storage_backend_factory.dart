import 'storage_backend.dart';
import 'storage_backend_stub.dart'
    if (dart.library.io) 'storage_backend_io.dart'
    if (dart.library.js_interop) 'storage_backend_web.dart';

/// Returns the platform-appropriate storage backend.
StorageBackend createStorageBackend() => buildStorageBackend();
