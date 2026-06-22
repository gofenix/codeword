import 'storage_path_stub.dart'
    if (dart.library.io) 'storage_path_io.dart'
    if (dart.library.html) 'storage_path_web.dart';

/// Returns a human-readable description of where the app stores local
/// data. On web, returns "浏览器存储". On desktop / mobile, returns
/// the absolute path of the app documents directory. Returns null if
/// the path can't be resolved.
Future<String?> resolveStoragePath() => computeStoragePath();
